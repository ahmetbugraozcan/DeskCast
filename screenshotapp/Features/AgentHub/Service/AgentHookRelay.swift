import Foundation

/// Files the Claude Code hook bridge lives in.
nonisolated enum AgentHookPaths {
    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DeskCast", isDirectory: true)
    }

    /// Kept short: a Unix socket path has to fit in 104 bytes.
    static var socket: URL {
        supportDirectory.appendingPathComponent("agent-hook.sock")
    }

    static var relayScript: URL {
        supportDirectory.appendingPathComponent("bin/\(ClaudeHookConfiguration.marker)")
    }

    static var claudeSettings: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    static var codexHooks: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/hooks.json")
    }

    static func hooksFile(for target: AgentHookTarget) -> URL {
        target == .codex ? codexHooks : claudeSettings
    }
}

/// The command Claude Code runs for each hook. It forwards the hook's JSON
/// to DeskCast over a Unix socket and, for permission requests, prints
/// DeskCast's decision. Written in Perl, which every Mac has (Python needs
/// the developer tools). It always exits 0 and gives up quickly when DeskCast
/// isn't running, so Claude Code is never blocked.
nonisolated enum AgentHookRelay {
    static let script = #"""
    #!/usr/bin/perl
    # DeskCast hook relay for Claude Code. Always exits 0: Claude Code is never blocked.
    use strict;
    use warnings;
    use IO::Socket::UNIX;
    use IO::Select;
    use JSON::PP;

    my $raw = do { local $/; <STDIN> };
    exit 0 unless defined $raw && length $raw;
    my $json = JSON::PP->new->utf8;
    my $payload = eval { $json->decode($raw) };
    exit 0 unless ref $payload eq 'HASH';

    for (my $i = 0; $i < @ARGV - 1; $i++) {
        if ($ARGV[$i] eq '--agent') { $payload->{deskcast_agent} //= $ARGV[$i + 1]; last; }
    }

    my %env_keys = (
        term_program => 'TERM_PROGRAM',
        iterm_session_id => 'ITERM_SESSION_ID',
        term_session_id => 'TERM_SESSION_ID',
        bundle_id => '__CFBundleIdentifier',
    );
    while (my ($key, $name) = each %env_keys) { $payload->{$key} //= $ENV{$name} // ''; }
    $payload->{cwd} = $ENV{PWD} // '' unless $payload->{cwd};

    my $event = $payload->{hook_event_name} // '';
    if ($event =~ /^(SessionStart|UserPromptSubmit|PermissionRequest)$/) {
        # The terminal tab is found by the tty of the nearest parent that has one.
        my $pid = getppid();
        for (1 .. 8) {
            my $line = `/bin/ps -o ppid=,tty= -p $pid 2>/dev/null`;
            last unless defined $line && $line =~ /^\s*(\d+)\s+(\S+)/;
            my ($parent, $tty) = ($1, $2);
            if ($tty ne '??') { $payload->{tty} = "/dev/$tty"; last; }
            last if $parent <= 1;
            $pid = $parent;
        }
    }

    my $path = "$ENV{HOME}/Library/Application Support/DeskCast/agent-hook.sock";
    my $socket = IO::Socket::UNIX->new(Type => SOCK_STREAM(), Peer => $path, Timeout => 0.3) or exit 0;
    print {$socket} $json->encode($payload) . "\n";

    if ($event eq 'PermissionRequest') {
        # DeskCast answers once the user decides, or with an empty line to let
        # Claude Code ask in the terminal. Claude Code's own timeout ends the wait.
        my $select = IO::Select->new($socket);
        if ($select->can_read(3600)) {
            my $reply = <$socket>;
            if (defined $reply) {
                $reply =~ s/\s+$//;
                print "$reply\n" if length $reply;
            }
        }
    }
    close $socket;
    exit 0;
    """#

    /// Writes the relay (mode 0755) into Application Support when it's
    /// missing or out of date.
    static func install() throws {
        let fileManager = FileManager.default
        let url = AgentHookPaths.relayScript
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: AgentHookPaths.supportDirectory.path)

        let data = Data(script.utf8)
        if (try? Data(contentsOf: url)) != data {
            try data.write(to: url, options: .atomic)
        }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
