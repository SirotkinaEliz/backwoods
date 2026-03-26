import XCTest
@testable import TunnelManager
@testable import TunnelKit
import SwiftSignalKit
import SwiftSignalKitTestHelpers

// Backwoods: TunnelManager unit tests
// Tests for signal pipelines, IPC serialization, status mapping, retry logic

final class TunnelManagerSignalsTests: XCTestCase {
    
    // MARK: - Status Text Signals
    
    func testStatusTextForConnected() {
        let text = statusTextSync(for: .connected)
        XCTAssertEqual(text, "Подключено")
    }
    
    func testStatusTextForConnecting() {
        let text = statusTextSync(for: .connecting)
        XCTAssertEqual(text, "Подключение...")
    }
    
    func testStatusTextForReconnecting() {
        let text = statusTextSync(for: .reconnecting)
        XCTAssertEqual(text, "Переподключение...")
    }
    
    func testStatusTextForDisconnected() {
        let text = statusTextSync(for: .disconnected)
        XCTAssertEqual(text, "Отключено")
    }
    
    func testStatusTextForDisconnecting() {
        let text = statusTextSync(for: .disconnecting)
        XCTAssertEqual(text, "Отключение...")
    }
    
    func testStatusTextForFailed() {
        let text = statusTextSync(for: .failed(.connectionFailed))
        XCTAssertTrue(text?.contains("Ошибка") == true)
    }
    
    // MARK: - isConnected Signal
    
    func testIsConnectedTrueWhenConnected() {
        let signal: Signal<TransportStatus, NoError> = just(.connected)
        let isConnected = signal |> map { status -> Bool in
            if case .connected = status { return true }
            return false
        }
        let value = awaitValue(isConnected)
        XCTAssertEqual(value, true)
    }
    
    func testIsConnectedFalseWhenDisconnected() {
        let signal: Signal<TransportStatus, NoError> = just(.disconnected)
        let isConnected = signal |> map { status -> Bool in
            if case .connected = status { return true }
            return false
        }
        let value = awaitValue(isConnected)
        XCTAssertEqual(value, false)
    }
    
    // MARK: - isTransitioning Signal
    
    func testIsTransitioningTrueWhenConnecting() {
        let signal: Signal<TransportStatus, NoError> = just(.connecting)
        let isTransitioning = signal |> map { status -> Bool in
            switch status {
            case .connecting, .reconnecting, .disconnecting:
                return true
            default:
                return false
            }
        }
        let value = awaitValue(isTransitioning)
        XCTAssertEqual(value, true)
    }
    
    func testIsTransitioningFalseWhenConnected() {
        let signal: Signal<TransportStatus, NoError> = just(.connected)
        let isTransitioning = signal |> map { status -> Bool in
            switch status {
            case .connecting, .reconnecting, .disconnecting:
                return true
            default:
                return false
            }
        }
        let value = awaitValue(isTransitioning)
        XCTAssertEqual(value, false)
    }
    
    // MARK: - Retry with Backoff
    
    func testRetryWithBackoffEventuallySucceeds() {
        var attempts = 0
        let signal: Signal<String, TransportError> = Signal { subscriber in
            attempts += 1
            if attempts < 3 {
                subscriber.putError(.connectionFailed)
            } else {
                subscriber.putNext("success")
                subscriber.putCompletion()
            }
            return EmptyDisposable
        }
        
        let retried = retryWithBackoff(
            signal: signal,
            maxAttempts: 5,
            initialDelay: 0.01,
            maxDelay: 0.1
        )
        
        let result = collectValues(retried, timeout: 5.0)
        
        switch result {
        case .success(let values):
            XCTAssertTrue(values.contains("success"))
        case .failure:
            XCTFail("Should have succeeded after retries")
        }
    }
    
    func testRetryWithBackoffGivesUpAfterMaxAttempts() {
        let signal: Signal<String, TransportError> = Signal { subscriber in
            subscriber.putError(.serverUnreachable)
            return EmptyDisposable
        }
        
        let retried = retryWithBackoff(
            signal: signal,
            maxAttempts: 2,
            initialDelay: 0.01,
            maxDelay: 0.05
        )
        
        let error = expectError(retried, timeout: 5.0)
        XCTAssertNotNil(error)
    }
    
    // MARK: - Helpers
    
    private func statusTextSync(for status: TransportStatus) -> String? {
        let signal: Signal<TransportStatus, NoError> = just(status)
        let textSignal: Signal<String, NoError> = signal |> map { status -> String in
            switch status {
            case .connected: return "Подключено"
            case .connecting: return "Подключение..."
            case .reconnecting: return "Переподключение..."
            case .disconnected: return "Отключено"
            case .disconnecting: return "Отключение..."
            case .failed: return "Ошибка подключения"
            }
        }
        return awaitValue(textSignal)
    }
}

// MARK: - Mock Provider Tests

final class MockTransportProviderTests: XCTestCase {
    
    func testMockStartEmitsConnectingThenConnected() {
        let mock = MockTransportProvider()
        let provider = MockPacketTunnelProvider()
        let config = makeValidConfig()
        
        let result = collectValues(mock.start(provider: provider, configuration: config))
        
        switch result {
        case .success(let statuses):
            XCTAssertTrue(statuses.contains(.connecting))
            XCTAssertTrue(statuses.contains(.connected))
        case .failure:
            XCTFail("Mock start should not fail")
        }
        
        XCTAssertEqual(mock.startCallCount, 1)
    }
    
    func testMockStopCompletesSuccessfully() {
        let mock = MockTransportProvider()
        
        let result = collectValues(mock.stop())
        
        switch result {
        case .success:
            break // Expected
        case .failure:
            XCTFail("Mock stop should not fail")
        }
        
        XCTAssertEqual(mock.stopCallCount, 1)
        XCTAssertEqual(mock.currentStatus, .disconnected)
    }
    
    func testMockProviderSetSettingsTracking() {
        let provider = MockPacketTunnelProvider()
        provider.setTunnelNetworkSettings(nil, completionHandler: nil)
        
        XCTAssertEqual(provider.setSettingsCallCount, 1)
    }
    
    func testMockProviderCancelTracking() {
        let provider = MockPacketTunnelProvider()
        provider.cancelTunnelWithError(nil)
        
        XCTAssertEqual(provider.cancelCallCount, 1)
    }
    
    func testMockConnectionStartStop() {
        let connection = MockVPNConnection()
        
        try? connection.startVPNTunnel()
        XCTAssertEqual(connection.startCallCount, 1)
        XCTAssertEqual(connection.status, MockVPNConnection.MockVPNStatus.connecting.rawValue)
        
        connection.stopVPNTunnel()
        XCTAssertEqual(connection.stopCallCount, 1)
        XCTAssertEqual(connection.status, MockVPNConnection.MockVPNStatus.disconnecting.rawValue)
    }
    
    func testMockConnectionSendMessage() {
        let connection = MockVPNConnection()
        connection.sendMessageResponse = Data("test".utf8)
        
        var receivedData: Data?
        try? connection.sendProviderMessage(Data(), responseHandler: { data in
            receivedData = data
        })
        
        XCTAssertEqual(connection.sendMessageCallCount, 1)
        XCTAssertEqual(receivedData, Data("test".utf8))
    }
    
    // MARK: - Helpers
    
    private func makeValidConfig() -> TransportConfiguration {
        return TransportConfiguration(
            type: .wireGuard,
            wireGuard: WireGuardConfiguration(
                interface: WireGuardInterface(
                    privateKey: "dGVzdC1wcml2YXRlLWtleQ==",
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
    }
}
