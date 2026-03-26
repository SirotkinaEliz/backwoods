import Foundation
import TunnelKit

// Backwoods: Mock implementations for testing
// These mocks implement the protocols from TunnelKit, enabling
// unit tests without any system dependencies (NEPacketTunnelProvider, etc.)

/// Mock implementation of PacketTunnelProviding
public final class MockPacketTunnelProvider: PacketTunnelProviding {
    
    public var reasserting: Bool = false
    
    public var setTunnelNetworkSettingsHandler: ((Any?, @escaping (Error?) -> Void) -> Void)?
    public var cancelTunnelHandler: ((Error?) -> Void)?
    
    private(set) public var setSettingsCallCount = 0
    private(set) public var cancelCallCount = 0
    private(set) public var lastNetworkSettings: Any?
    private(set) public var lastCancelError: Error?
    
    public init() {}
    
    public func setTunnelNetworkSettings(_ tunnelNetworkSettings: Any?, completionHandler: ((Error?) -> Void)?) {
        setSettingsCallCount += 1
        lastNetworkSettings = tunnelNetworkSettings
        
        if let handler = setTunnelNetworkSettingsHandler {
            handler(tunnelNetworkSettings, completionHandler ?? { _ in })
        } else {
            completionHandler?(nil)
        }
    }
    
    public func cancelTunnelWithError(_ error: Error?) {
        cancelCallCount += 1
        lastCancelError = error
        cancelTunnelHandler?(error)
    }
}

/// Mock implementation of TunnelProviderManaging
public final class MockTunnelProviderManager: TunnelProviderManaging {
    
    public var localizedDescription: String? = "Mock VPN"
    public var isEnabled: Bool = true
    public var isOnDemandEnabled: Bool = false
    public var connection: VPNConnectionProviding { return mockConnection }
    
    public let mockConnection = MockVPNConnection()
    
    private(set) public var loadCallCount = 0
    private(set) public var saveCallCount = 0
    private(set) public var removeCallCount = 0
    
    public var loadError: Error?
    public var saveError: Error?
    public var removeError: Error?
    
    public init() {}
    
    public func loadFromPreferences(completionHandler: @escaping (Error?) -> Void) {
        loadCallCount += 1
        completionHandler(loadError)
    }
    
    public func saveToPreferences(completionHandler: ((Error?) -> Void)?) {
        saveCallCount += 1
        completionHandler?(saveError)
    }
    
    public func removeFromPreferences(completionHandler: ((Error?) -> Void)?) {
        removeCallCount += 1
        completionHandler?(removeError)
    }
}

/// Mock implementation of VPNConnectionProviding
public final class MockVPNConnection: VPNConnectionProviding {
    
    public enum MockVPNStatus: Int {
        case invalid = 0
        case disconnected = 1
        case connecting = 2
        case connected = 3
        case reasserting = 4
        case disconnecting = 5
    }
    
    public var mockStatus: MockVPNStatus = .disconnected
    public var status: Int { return mockStatus.rawValue }
    
    private(set) public var startCallCount = 0
    private(set) public var stopCallCount = 0
    private(set) public var sendMessageCallCount = 0
    
    public var sendMessageResponse: Data?
    public var sendMessageError: Error?
    
    public init() {}
    
    public func startVPNTunnel() throws {
        startCallCount += 1
        mockStatus = .connecting
    }
    
    public func stopVPNTunnel() {
        stopCallCount += 1
        mockStatus = .disconnecting
    }
    
    public func sendProviderMessage(_ messageData: Data, responseHandler: ((Data?) -> Void)?) throws {
        sendMessageCallCount += 1
        if let error = sendMessageError {
            throw error
        }
        responseHandler?(sendMessageResponse)
    }
}

/// Mock TransportProvider for testing PacketTunnelProvider and TunnelManager
public final class MockTransportProvider: TransportProvider {
    
    public var transportIdentifier: String = "mock"
    public var currentStatus: TransportStatus = .disconnected
    
    private(set) public var startCallCount = 0
    private(set) public var stopCallCount = 0
    private(set) public var handleMessageCallCount = 0
    
    public var startResult: Signal<TransportStatus, TransportError>?
    public var stopResult: Signal<Void, TransportError>?
    
    public init() {}
    
    public func start(
        provider: PacketTunnelProviding,
        configuration: TransportConfiguration
    ) -> Signal<TransportStatus, TransportError> {
        startCallCount += 1
        currentStatus = .connecting
        
        if let result = startResult {
            return result
        }
        
        return Signal { subscriber in
            subscriber.putNext(.connecting)
            subscriber.putNext(.connected)
            subscriber.putCompletion()
            return EmptyDisposable
        }
    }
    
    public func stop() -> Signal<Void, TransportError> {
        stopCallCount += 1
        currentStatus = .disconnected
        
        if let result = stopResult {
            return result
        }
        
        return Signal { subscriber in
            subscriber.putNext(Void())
            subscriber.putCompletion()
            return EmptyDisposable
        }
    }
    
    public func handleAppMessage(_ data: Data) -> Signal<Data?, TransportError> {
        handleMessageCallCount += 1
        
        return Signal { subscriber in
            subscriber.putNext(nil)
            subscriber.putCompletion()
            return EmptyDisposable
        }
    }
}
