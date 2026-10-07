import Foundation
import Testing
@testable import screenshotapp

struct WakeOnLANTests {
    @Test func readsMACAddressesInCommonFormats() {
        let expected: [UInt8] = [0xAA, 0xBB, 0xCC, 0x01, 0x02, 0x0F]
        for text in ["AA:BB:CC:01:02:0F", "aa-bb-cc-01-02-0f", "aabb.cc01.020f", " AABBCC01020F "] {
            #expect(WakeOnLAN.macBytes(text) == expected, "\(text)")
        }
        for text in ["", "AA:BB:CC:01:02", "AA:BB:CC:01:02:0F:11", "GG:BB:CC:01:02:0F"] {
            #expect(WakeOnLAN.macBytes(text) == nil, "\(text)")
        }
        #expect(WakeOnLAN.formatted(expected) == "AA:BB:CC:01:02:0F")
    }

    @Test func buildsTheMagicPacket() throws {
        let mac: [UInt8] = [1, 2, 3, 4, 5, 6]
        let packet = try #require(WakeOnLAN.magicPacket(for: mac))
        #expect(packet.count == 102)
        #expect(Array(packet.prefix(6)) == [UInt8](repeating: 0xFF, count: 6))
        for copy in 0..<16 {
            let start = 6 + copy * 6
            #expect(Array(packet[start..<start + 6]) == mac)
        }
        #expect(WakeOnLAN.magicPacket(for: [1, 2, 3]) == nil)
    }

    @Test func storesComputersAsPropertyLists() throws {
        let defaults = try #require(UserDefaults(suiteName: "WakeOnLANTests"))
        defaults.removePersistentDomain(forName: "WakeOnLANTests")
        let computers = [WakeComputer(name: "Gaming PC", mac: "AA:BB:CC:01:02:0F", host: "192.168.1.20"), WakeComputer()]
        WakeComputer.save(computers, to: defaults)
        #expect(WakeComputer.load(from: defaults) == computers)
        defaults.removePersistentDomain(forName: "WakeOnLANTests")
    }

    @Test func keepsWakingUntilOnlineOrTimedOut() {
        let start = Date(timeIntervalSince1970: 1_000)
        let waking = WakeComputerStatus.waking(since: start)
        #expect(WakeComputersViewModel.next(status: waking, online: false, now: start.addingTimeInterval(30)) == waking)
        #expect(WakeComputersViewModel.next(status: waking, online: true, now: start.addingTimeInterval(30)) == .online)
        let late = start.addingTimeInterval(WakeOnLAN.wakeTimeout + 1)
        #expect(WakeComputersViewModel.next(status: waking, online: false, now: late) == .offline)
        #expect(WakeComputersViewModel.next(status: .online, online: false, now: start) == .offline)
    }

    @Test func readsPrivateIPv4AddressesOnly() {
        #expect(LocalNetworkReach.privateIPv4("192.168.1.20") == 0xC0A8_0114)
        #expect(LocalNetworkReach.privateIPv4(" 10.0.0.5 ") == 0x0A00_0005)
        #expect(LocalNetworkReach.privateIPv4("172.20.1.1") != nil)
        #expect(LocalNetworkReach.privateIPv4("169.254.3.4") != nil)
        for text in ["172.32.0.1", "100.101.102.103", "8.8.8.8", "192.168.1", "192.168.1.256", "pc.local", ""] {
            #expect(LocalNetworkReach.privateIPv4(text) == nil, "\(text)")
        }
        #expect(LocalNetworkReach.isLocalName("Gaming-PC.LOCAL"))
        #expect(!LocalNetworkReach.isLocalName("pc.tailnet.ts.net"))
    }

    @Test func showsHomeAddressesAsAwayOnOtherNetworks() {
        let home = [IPv4Subnet(address: 0xC0A8_0105, mask: 0xFFFF_FF00)] // 192.168.1.5/24
        let cafe = [IPv4Subnet(address: 0x0A01_0203, mask: 0xFFFF_0000)] // 10.1.2.3/16
        #expect(!LocalNetworkReach.isAway(host: "192.168.1.20", lastKnownAddress: nil, subnets: home))
        #expect(LocalNetworkReach.isAway(host: "192.168.1.20", lastKnownAddress: nil, subnets: cafe))
        #expect(LocalNetworkReach.isAway(host: "192.168.1.20", lastKnownAddress: nil, subnets: []))
        // A .local name uses the last address it had; unknown means not away.
        #expect(LocalNetworkReach.isAway(host: "pc.local", lastKnownAddress: "192.168.1.20", subnets: cafe))
        #expect(!LocalNetworkReach.isAway(host: "pc.local", lastKnownAddress: "192.168.1.20", subnets: home))
        #expect(!LocalNetworkReach.isAway(host: "pc.local", lastKnownAddress: nil, subnets: cafe))
        // Tailscale and public addresses are reachable from anywhere.
        #expect(!LocalNetworkReach.isAway(host: "100.101.102.103", lastKnownAddress: nil, subnets: cafe))
    }
}
