import XCTest
@testable import WireGuardTransport
@testable import TunnelKit
import SwiftSignalKit
import SwiftSignalKitTestHelpers

// Backwoods: WireGuardTransport unit tests
// Tests for config generation, environment setup, transport lifecycle

final class WireGuardTransportTests: XCTestCase {
    
    // MARK: - Transport Identifier
    
    func testTransportIdentifier() {
        let transport = WireGuardTransport()
        XCTAssertEqual(transport.transportIdentifier, "wireguard")
    }
    
    // MARK: - Initial Status
    
    func testInitialStatusIsDisconnected() {
        let transport = WireGuardTransport()
        XCTAssertEqual(transport.currentStatus, .disconnected)
    }
    
    // MARK: - Config Validation in Start
    
    func testStartWithInvalidConfigEmitsError() {
        let transport = WireGuardTransport()
        let provider = MockPacketTunnelProvider()
        
        // Empty config (no wireGuard section)
        let invalidConfig = TransportConfiguration(type: .wireGuard, wireGuard: nil)
        
        let error = expectError(
            transport.start(provider: provider, configuration: invalidConfig),
            timeout: 2.0
        )
        
        XCTAssertNotNil(error)
        if case .configurationInvalid = error {
            // Expected
        } else {
            XCTFail("Expected configurationInvalid error, got \(String(describing: error))")
        }
    }
    
    func testStartWithEmptyPrivateKeyEmitsError() {
        let transport = WireGuardTransport()
        let provider = MockPacketTunnelProvider()
        
        let badConfig = TransportConfiguration(
            type: .wireGuard,
            wireGuard: WireGuardConfiguration(
                interface: WireGuardInterface(
                    privateKey: "",
                    addresses: ["10.0.0.2/32"],
                    dns: ["1.1.1.1"],
                    mtu: 1280
                ),
                peer: WireGuardPeer(
                    publicKey: "dGVzdC1wdWJsaWMta2V5",
                    presharedKey: nil,
                    endpoint: "203.0.113.1:51820",
                    allowedIPs: ["0.0.0.0/0", "::/0"],
                    persistentKeepalive: 25
                )
            )
        )
        
        let error = expectError(
            transport.start(provider: provider, configuration: badConfig),
            timeout: 2.0
        )
        
        XCTAssertNotNil(error)
    }
    
    // MARK: - Stop Without Start
    
    func testStopWithoutStartCompletes() {
        let transport = WireGuardTransport()
        
        let result = collectValues(transport.stop(), timeout: 2.0)
        
        switch result {
        case .success:
            break // Expected — stop on idle transport should succeed
        case .failure:
            XCTFail("Stop on idle transport should not fail")
        }
    }
    
    // MARK: - Config Generation
    
    func testWgQuickConfigContainsAllFields() {
        let config = makeValidConfig()
        let wgQuick = config.wireGuard!.toWgQuickConfig()
        
        // Verify all required WireGuard fields
        XCTAssertTrue(wgQuick.contains("[Interface]"))
        XCTAssertTrue(wgQuick.contains("PrivateKey"))
        XCTAssertTrue(wgQuick.contains("Address"))
        XCTAssertTrue(wgQuick.contains("DNS"))
        XCTAssertTrue(wgQuick.contains("MTU"))
        XCTAssertTrue(wgQuick.contains("[Peer]"))
        XCTAssertTrue(wgQuick.contains("PublicKey"))
        XCTAssertTrue(wgQuick.contains("Endpoint"))
        XCTAssertTrue(wgQuick.contains("AllowedIPs"))
        XCTAssertTrue(wgQuick.contains("PersistentKeepalive"))
    }
    
    func testWgQuickConfigMultipleAddresses() {
        var config = makeValidConfig()
        config.wireGuard?.interface.addresses = ["10.0.0.2/32", "fd00::2/128"]
        let wgQuick = config.wireGuard!.toWgQuickConfig()
        
        XCTAssertTrue(wgQuick.contains("10.0.0.2/32, fd00::2/128"))
    }
    
    func testWgQuickConfigMultipleDNS() {
        var config = makeValidConfig()
        config.wireGuard?.interface.dns = ["1.1.1.1", "8.8.8.8", "9.9.9.9"]
        let wgQuick = config.wireGuard!.toWgQuickConfig()
        
        XCTAssertTrue(wgQuick.contains("DNS = 1.1.1.1, 8.8.8.8, 9.9.9.9"))
    }
    
    // MARK: - Handle App Message
    
    func testHandleAppMessageStatusRequest() {
        let transport = WireGuardTransport()
        let statusMsg = TunnelIPCMessage.requestStatus
        let data = try! TunnelIPCCodec.encode(statusMsg)
        
        let result = collectValues(
            transport.handleAppMessage(data),
            timeout: 2.0
        )
        
        switch result {
        case .success(let responses):
            // Should get at least one response
            XCTAssertFalse(responses.isEmpty)
        case .failure:
            XCTFail("Handle app message should not fail for status request")
        }
    }
    
    // MARK: - Helpers
    
    private func makeValidConfig() -> TransportConfiguration {
        return TransportConfiguration(
            type: .wireGuard,
            wireGuard: WireGuardConfiguration(
                interface: WireGuardInterface(
                    privateKey: "dGVzdC1wcml2YXRlLWtleQ==",
                    addresses: ["10.0.0.2/32"],
                    dns: ["1.1.1.1", "1.0.0.1"],
                    mtu: 1280
                ),
                peer: WireGuardPeer(
                    publicKey: "dGVzdC1wdWJsaWMta2V5",
                    presharedKey: nil,
                    endpoint: "203.0.113.1:51820",
                    allowedIPs: ["0.0.0.0/0", "::/0"],
                    persistentKeepalive: 25
                )
            )
        )
    }
}
