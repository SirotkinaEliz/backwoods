import XCTest
@testable import TunnelKit
import SwiftSignalKit
import SwiftSignalKitTestHelpers

// Backwoods: TunnelKit unit tests
// Tests for configuration, validation, serialization, IPC codec, constants

final class TransportConfigurationTests: XCTestCase {
    
    // MARK: - WireGuard Configuration
    
    func testValidConfigurationPassesValidation() {
        let config = makeValidConfig()
        XCTAssertNoThrow(try config.validate())
    }
    
    func testMissingPrivateKeyFailsValidation() {
        var config = makeValidConfig()
        config.wireGuard?.interface.privateKey = ""
        XCTAssertThrowsError(try config.validate())
    }
    
    func testMissingPeerPublicKeyFailsValidation() {
        var config = makeValidConfig()
        config.wireGuard?.peer.publicKey = ""
        XCTAssertThrowsError(try config.validate())
    }
    
    func testMissingEndpointFailsValidation() {
        var config = makeValidConfig()
        config.wireGuard?.peer.endpoint = ""
        XCTAssertThrowsError(try config.validate())
    }
    
    func testMissingAddressesFailsValidation() {
        var config = makeValidConfig()
        config.wireGuard?.interface.addresses = []
        XCTAssertThrowsError(try config.validate())
    }
    
    func testMissingAllowedIPsFailsValidation() {
        var config = makeValidConfig()
        config.wireGuard?.peer.allowedIPs = []
        XCTAssertThrowsError(try config.validate())
    }
    
    func testNilWireGuardConfigFailsValidation() {
        var config = makeValidConfig()
        config.wireGuard = nil
        XCTAssertThrowsError(try config.validate())
    }
    
    // MARK: - wg-quick format
    
    func testToWgQuickConfigFormat() {
        let config = makeValidConfig()
        let wgQuick = config.wireGuard!.toWgQuickConfig()
        
        XCTAssertTrue(wgQuick.contains("[Interface]"))
        XCTAssertTrue(wgQuick.contains("[Peer]"))
        XCTAssertTrue(wgQuick.contains("PrivateKey = dGVzdC1wcml2YXRlLWtleQ=="))
        XCTAssertTrue(wgQuick.contains("Address = 10.0.0.2/32"))
        XCTAssertTrue(wgQuick.contains("DNS = 1.1.1.1"))
        XCTAssertTrue(wgQuick.contains("MTU = 1280"))
        XCTAssertTrue(wgQuick.contains("PublicKey = dGVzdC1wdWJsaWMta2V5"))
        XCTAssertTrue(wgQuick.contains("Endpoint = 203.0.113.1:51820"))
        XCTAssertTrue(wgQuick.contains("AllowedIPs = 0.0.0.0/0, ::/0"))
        XCTAssertTrue(wgQuick.contains("PersistentKeepalive = 25"))
    }
    
    func testWgQuickConfigIncludesPresharedKey() {
        var config = makeValidConfig()
        config.wireGuard?.peer.presharedKey = "cHJlc2hhcmVkLWtleQ=="
        let wgQuick = config.wireGuard!.toWgQuickConfig()
        
        XCTAssertTrue(wgQuick.contains("PresharedKey = cHJlc2hhcmVkLWtleQ=="))
    }
    
    func testWgQuickConfigOmitsPresharedKeyWhenNil() {
        let config = makeValidConfig()
        let wgQuick = config.wireGuard!.toWgQuickConfig()
        
        XCTAssertFalse(wgQuick.contains("PresharedKey"))
    }
    
    // MARK: - Codable Round-Trip
    
    func testCodableRoundTrip() throws {
        let original = makeValidConfig()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TransportConfiguration.self, from: data)
        
        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.wireGuard?.interface.privateKey, original.wireGuard?.interface.privateKey)
        XCTAssertEqual(decoded.wireGuard?.peer.publicKey, original.wireGuard?.peer.publicKey)
        XCTAssertEqual(decoded.wireGuard?.peer.endpoint, original.wireGuard?.peer.endpoint)
        XCTAssertEqual(decoded.wireGuard?.interface.addresses, original.wireGuard?.interface.addresses)
        XCTAssertEqual(decoded.wireGuard?.interface.dns, original.wireGuard?.interface.dns)
        XCTAssertEqual(decoded.wireGuard?.interface.mtu, original.wireGuard?.interface.mtu)
        XCTAssertEqual(decoded.wireGuard?.peer.allowedIPs, original.wireGuard?.peer.allowedIPs)
        XCTAssertEqual(decoded.wireGuard?.peer.persistentKeepalive, original.wireGuard?.peer.persistentKeepalive)
    }
    
    // MARK: - Provider Configuration Round-Trip
    
    func testProviderConfigurationRoundTrip() throws {
        let original = makeValidConfig()
        let dict = try original.toProviderConfiguration()
        let decoded = try TransportConfiguration.fromProviderConfiguration(dict)
        
        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.wireGuard?.peer.endpoint, original.wireGuard?.peer.endpoint)
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

// MARK: - IPC Codec Tests

final class TunnelIPCCodecTests: XCTestCase {
    
    func testEncodeDecodeRequestStatus() throws {
        let message = TunnelIPCMessage.requestStatus
        let data = try TunnelIPCCodec.encode(message)
        let decoded = try TunnelIPCCodec.decode(data)
        
        if case .requestStatus = decoded {
            // OK
        } else {
            XCTFail("Expected .requestStatus, got \(decoded)")
        }
    }
    
    func testEncodeDecodeStatusResponse() throws {
        let info: [String: String] = ["status": "connected", "uptime": "120"]
        let message = TunnelIPCMessage.statusResponse(info)
        let data = try TunnelIPCCodec.encode(message)
        let decoded = try TunnelIPCCodec.decode(data)
        
        if case .statusResponse(let decodedInfo) = decoded {
            XCTAssertEqual(decodedInfo["status"], "connected")
            XCTAssertEqual(decodedInfo["uptime"], "120")
        } else {
            XCTFail("Expected .statusResponse, got \(decoded)")
        }
    }
    
    func testEncodeDecodeRequestReconnect() throws {
        let message = TunnelIPCMessage.requestReconnect
        let data = try TunnelIPCCodec.encode(message)
        let decoded = try TunnelIPCCodec.decode(data)
        
        if case .requestReconnect = decoded {
            // OK
        } else {
            XCTFail("Expected .requestReconnect, got \(decoded)")
        }
    }
    
    func testEncodeDecodeRequestLog() throws {
        let message = TunnelIPCMessage.requestLog
        let data = try TunnelIPCCodec.encode(message)
        let decoded = try TunnelIPCCodec.decode(data)
        
        if case .requestLog = decoded {
            // OK
        } else {
            XCTFail("Expected .requestLog, got \(decoded)")
        }
    }
    
    func testEncodeDecodeLogResponse() throws {
        let logText = "2024-01-15 12:00:00 [INFO] Tunnel started successfully"
        let message = TunnelIPCMessage.logResponse(logText)
        let data = try TunnelIPCCodec.encode(message)
        let decoded = try TunnelIPCCodec.decode(data)
        
        if case .logResponse(let text) = decoded {
            XCTAssertEqual(text, logText)
        } else {
            XCTFail("Expected .logResponse, got \(decoded)")
        }
    }
    
    func testDecodeInvalidDataThrows() {
        let invalidData = Data([0x00, 0xFF, 0xAB])
        XCTAssertThrowsError(try TunnelIPCCodec.decode(invalidData))
    }
}

// MARK: - Transport Status Tests

final class TransportStatusTests: XCTestCase {
    
    func testAllStatusCasesExist() {
        let statuses: [TransportStatus] = [
            .disconnected,
            .connecting,
            .connected,
            .reconnecting,
            .disconnecting,
            .failed(.connectionFailed)
        ]
        XCTAssertEqual(statuses.count, 6)
    }
    
    func testTransportErrorDescriptions() {
        let errors: [TransportError] = [
            .configurationInvalid,
            .connectionFailed,
            .timeout,
            .permissionDenied,
            .extensionCrashed,
            .serverUnreachable,
            .networkUnavailable
        ]
        // All errors should have non-empty descriptions
        for error in errors {
            XCTAssertFalse(String(describing: error).isEmpty)
        }
    }
}

// MARK: - Tunnel Constants Tests

final class TunnelConstantsTests: XCTestCase {
    
    func testTimeoutsArePositive() {
        XCTAssertGreaterThan(TunnelConstants.Timeout.launchConnection, 0)
        XCTAssertGreaterThan(TunnelConstants.Timeout.networkSettings, 0)
    }
    
    func testRetryConfigIsReasonable() {
        XCTAssertGreaterThan(TunnelConstants.Retry.maxAttempts, 0)
        XCTAssertGreaterThan(TunnelConstants.Retry.initialDelay, 0)
        XCTAssertGreaterThanOrEqual(TunnelConstants.Retry.maxDelay, TunnelConstants.Retry.initialDelay)
    }
    
    func testWireGuardDefaults() {
        XCTAssertEqual(TunnelConstants.WireGuard.defaultMTU, 1280)
        XCTAssertEqual(TunnelConstants.WireGuard.persistentKeepalive, 25)
    }
    
    func testGoRuntimeLimits() {
        XCTAssertGreaterThan(TunnelConstants.GoRuntime.memoryLimitMiB, 0)
        XCTAssertLessThanOrEqual(TunnelConstants.GoRuntime.memoryLimitMiB, 50) // Extension limit
    }
    
    func testFullTunnelAllowedIPs() {
        let ips = TunnelConstants.WireGuard.fullTunnelAllowedIPs
        XCTAssertTrue(ips.contains("0.0.0.0/0"))
        XCTAssertTrue(ips.contains("::/0"))
    }
}
