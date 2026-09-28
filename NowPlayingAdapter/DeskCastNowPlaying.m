// DeskCast Now Playing adapter.
//
// Since macOS 15.4, MediaRemote only answers now-playing queries from Apple
// platform binaries. DeskCast therefore loads this library into
// /usr/bin/perl (see NowPlayingBridge.swift) and reads the system-wide now
// playing session — Safari/Chrome/YouTube, Music, Spotify, Podcasts, … — from
// there. Every entry point prints JSON lines to stdout and exits the process;
// perl never gets control back, so the XSUB calling convention is irrelevant.
//
// Entry points:
//   deskcast_now_playing_get   – print the current state once.
//   deskcast_now_playing_watch – print the state now and after every change;
//                                exits when stdin closes (DeskCast quit).
//   deskcast_now_playing_send  – send DESKCAST_NP_COMMAND (MRCommand number),
//                                or seek to DESKCAST_NP_SEEK seconds.

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <unistd.h>

typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*MRGetIsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRRegisterFn)(dispatch_queue_t);
typedef Boolean (*MRSendCommandFn)(int, NSDictionary *);
typedef void (*MRSetElapsedFn)(double);

static MRGetInfoFn getInfo;
static MRGetIsPlayingFn getIsPlaying;
static MRRegisterFn registerNotifications;
static MRSendCommandFn sendCommand;
static MRSetElapsedFn setElapsed;
static Class requestClass;

static NSString *lastLine;
static NSString *lastArtworkHash;
static BOOL refreshScheduled;

static BOOL loadMediaRemote(void) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!handle) { return NO; }
    getInfo = (MRGetInfoFn)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
    getIsPlaying = (MRGetIsPlayingFn)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    registerNotifications = (MRRegisterFn)dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
    sendCommand = (MRSendCommandFn)dlsym(handle, "MRMediaRemoteSendCommand");
    setElapsed = (MRSetElapsedFn)dlsym(handle, "MRMediaRemoteSetElapsedTime");
    requestClass = NSClassFromString(@"MRNowPlayingRequest");
    return getInfo && getIsPlaying;
}

static NSString *stringValue(id value) {
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSNumber *numberValue(id value) {
    return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

static NSString *sha1(NSData *data) {
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) { [hex appendFormat:@"%02x", digest[i]]; }
    return hex;
}

/// Reads the bundle id of the app that owns the now playing session.
static void addClient(NSMutableDictionary *state) {
    if (!requestClass || ![requestClass respondsToSelector:@selector(localNowPlayingPlayerPath)]) { return; }
    @try {
        id path = [requestClass performSelector:@selector(localNowPlayingPlayerPath)];
        id client = [path respondsToSelector:@selector(client)] ? [path performSelector:@selector(client)] : nil;
        if ([client respondsToSelector:@selector(bundleIdentifier)]) {
            NSString *bundle = stringValue([client performSelector:@selector(bundleIdentifier)]);
            if (bundle) { state[@"bundle"] = bundle; }
        }
        if ([client respondsToSelector:@selector(parentApplicationBundleIdentifier)]) {
            NSString *parent = stringValue([client performSelector:@selector(parentApplicationBundleIdentifier)]);
            if (parent) { state[@"parent"] = parent; }
        }
    } @catch (__unused NSException *exception) {}
}

/// Lists the enabled MRCommand numbers (4 = next, 5 = previous, 24 = seek, …).
static void addSupportedCommands(NSMutableDictionary *state) {
    if (!requestClass || ![requestClass respondsToSelector:@selector(localSupportedCommands)]) { return; }
    @try {
        NSArray *infos = [requestClass performSelector:@selector(localSupportedCommands)];
        if (![infos isKindOfClass:[NSArray class]]) { return; }
        NSMutableArray<NSNumber *> *commands = [NSMutableArray array];
        for (id info in infos) {
            if (![info respondsToSelector:@selector(command)] || ![info respondsToSelector:@selector(isEnabled)]) { continue; }
            NSInteger command = ((NSInteger (*)(id, SEL))objc_msgSend)(info, @selector(command));
            BOOL enabled = ((BOOL (*)(id, SEL))objc_msgSend)(info, @selector(isEnabled));
            if (enabled) { [commands addObject:@(command)]; }
        }
        [commands sortUsingSelector:@selector(compare:)];
        state[@"commands"] = commands;
    } @catch (__unused NSException *exception) {}
}

static void emit(NSDictionary *info, BOOL playing, BOOL alwaysIncludeArtwork) {
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    state[@"playing"] = @(playing);
    addClient(state);
    addSupportedCommands(state);

    NSString *title = stringValue(info[@"kMRMediaRemoteNowPlayingInfoTitle"]);
    if (title) { state[@"title"] = title; }
    NSString *artist = stringValue(info[@"kMRMediaRemoteNowPlayingInfoArtist"]);
    if (artist) { state[@"artist"] = artist; }
    NSString *album = stringValue(info[@"kMRMediaRemoteNowPlayingInfoAlbum"]);
    if (album) { state[@"album"] = album; }
    NSNumber *duration = numberValue(info[@"kMRMediaRemoteNowPlayingInfoDuration"]);
    if (duration) { state[@"duration"] = duration; }

    NSNumber *rate = numberValue(info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"]);
    NSNumber *elapsed = numberValue(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]);
    if (elapsed) {
        double seconds = elapsed.doubleValue;
        id timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
        if (playing && rate.doubleValue > 0 && [timestamp isKindOfClass:[NSDate class]]) {
            seconds += rate.doubleValue * -[(NSDate *)timestamp timeIntervalSinceNow];
        }
        state[@"elapsed"] = @(MAX(0, seconds));
    }

    NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
    NSString *artworkHash = nil;
    if ([artwork isKindOfClass:[NSData class]] && artwork.length > 0) {
        artworkHash = sha1(artwork);
        state[@"artworkHash"] = artworkHash;
    }

    // Deduplicate on everything but the artwork bytes and the (moving) position.
    NSMutableDictionary *comparable = [state mutableCopy];
    [comparable removeObjectForKey:@"elapsed"];
    NSData *comparableJSON = [NSJSONSerialization dataWithJSONObject:comparable options:NSJSONWritingSortedKeys error:nil];
    NSString *line = [[NSString alloc] initWithData:comparableJSON encoding:NSUTF8StringEncoding];
    if (!alwaysIncludeArtwork && [line isEqualToString:lastLine]) { return; }
    lastLine = line;

    if (artworkHash && (alwaysIncludeArtwork || ![artworkHash isEqualToString:lastArtworkHash])) {
        state[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
    }
    lastArtworkHash = artworkHash;

    NSData *json = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
    if (!json) { return; }
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static void refresh(BOOL alwaysIncludeArtwork, void (^completion)(void)) {
    dispatch_queue_t queue = dispatch_get_main_queue();
    getInfo(queue, ^(NSDictionary *info) {
        getIsPlaying(queue, ^(Boolean playing) {
            emit(info ?: @{}, playing, alwaysIncludeArtwork);
            if (completion) { completion(); }
        });
    });
}

static void scheduleRefresh(void) {
    if (refreshScheduled) { return; }
    refreshScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        refreshScheduled = NO;
        refresh(NO, nil);
    });
}

__attribute__((visibility("default")))
void deskcast_now_playing_get(void) {
    @autoreleasepool {
        if (!loadMediaRemote()) { exit(1); }
        refresh(YES, ^{ exit(0); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ exit(2); });
        CFRunLoopRun();
    }
    exit(0);
}

__attribute__((visibility("default")))
void deskcast_now_playing_watch(void) {
    @autoreleasepool {
        if (!loadMediaRemote()) { exit(1); }
        if (registerNotifications) { registerNotifications(dispatch_get_main_queue()); }
        NSArray<NSString *> *names = @[
            @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            @"kMRMediaRemoteNowPlayingPlaybackQueueChangedNotification",
        ];
        for (NSString *name in names) {
            [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil usingBlock:^(__unused NSNotification *note) {
                scheduleRefresh();
            }];
        }

        // DeskCast keeps our stdin open; EOF means it quit, so follow it.
        dispatch_source_t input = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(input, ^{
            char buffer[256];
            ssize_t count = read(STDIN_FILENO, buffer, sizeof buffer);
            if (count <= 0) { exit(0); }
            // Any line on stdin asks for a full refresh (artwork included).
            lastLine = nil;
            lastArtworkHash = nil;
            refresh(YES, nil);
        });
        dispatch_resume(input);

        refresh(YES, nil);
        CFRunLoopRun();
    }
    exit(0);
}

__attribute__((visibility("default")))
void deskcast_now_playing_send(void) {
    @autoreleasepool {
        if (!loadMediaRemote()) { exit(1); }
        const char *seek = getenv("DESKCAST_NP_SEEK");
        if (seek) {
            // MRCommand 24 = seekToPlaybackPosition; browsers only accept this form.
            NSDictionary *options = @{ @"kMRMediaRemoteOptionPlaybackPosition": @(atof(seek)) };
            if (sendCommand && sendCommand(24, options)) { exit(0); }
            if (setElapsed) { setElapsed(atof(seek)); }
            exit(0);
        }
        const char *command = getenv("DESKCAST_NP_COMMAND");
        if (!command || !sendCommand) { exit(1); }
        exit(sendCommand(atoi(command), nil) ? 0 : 1);
    }
}
