import Foundation
import SwiftSignalKit

// Backwoods: Transport abstraction layer
// This protocol decouples the tunnel implementation from the specific VPN protocol.
// Phase 1: WireGuardTransport. Phase 2+: ObfuscatedTransport, XrayTransport, etc.

/// Status of the transport connection
public enum TransportStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case disconnecting
    case failed(TransportError)
    
    public static func == (lhs: TransportStatus, rhs: TransportStatus) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected),
             (.reconnecting, .reconnecting),
             (.disconnecting, .disconnecting):
            return true
        case (.failed(let lhsErr), .failed(let rhsErr)):
            return lhsErr == rhsErr
        default:
            return false
        }
    }
}

/// Errors that can occur during transport operations
public enum TransportError: Error, Equatable {
    case configurationInvalid(reason: String)
    case connectionFailed(underlying: String)
    case timeout
    case permissionDenied
    case extensionCrashed
    case serverUnreachable
    case networkUnavailable
    
    public var localizedDescription: String {
        switch self {
        case .configurationInvalid(let reason):
            return "Invalid configuration: \(reason)"
        case .connectionFailed(let underlying):
            return "Connection failed: \(underlying)"
        case .timeout:
            return "Connection timed out"
        case .permissionDenied:
            return "VPN permission denied"
        case .extensionCrashed:
            return "Tunnel extension was terminated"
        case .serverUnreachable:
            return "Server is unreachable"
        case .networkUnavailable:
            return "No network connection available"
        }
    }
}

/// IPC message types for communication between the main app and the tunnel extension
public enum TunnelIPCMessage: Codable, Equatable {
    case requestStatus
    case statusResponse(TransportStatusInfo)
    case requestReconnect
    case requestLog
    case logResponse(String)
    
    public struct TransportStatusInfo: Codable, Equatable {
        public let status: String
        public let connectedSince: Date?
        public let serverHost: String
        public let bytesReceived: UInt64
        public let bytesSent: UInt64
        
        public init(
            status: String,
            connectedSince: Date?,
            serverHost: String,
            bytesReceived: UInt64,
            bytesSent: UInt64
        ) {
            self.status = status
            self.connectedSince = connectedSince
            self.serverHost = serverHost
            self.bytesReceived = bytesReceived
            self.bytesSent = bytesSent
        }
    }
}

/// Protocol that all transport implementations must conform to.
/// Transport providers handle the actual VPN tunnel protocol (WireGuard, obfs4, etc.)
public protocol TransportProvider: AnyObject {
    
    /// Reactive stream of transport status changes
    var status: Signal<TransportStatus, NoError> { get }
    
    /// Start the transport with the given configuration.
    /// The implementation should configure NEPacketTunnelNetworkSettings
    /// and establish the tunnel connection.
    ///
    /// - Parameters:
    ///   - configuration: Transport-specific configuration
    ///   - tunnelProvider: The packet tunnel provider (for setting network settings)
    /// - Returns: A signal that completes on success or errors on failure
    func start(
        configuration: TransportConfiguration,
        tunnelProvider: PacketTunnelProviding
    ) -> Signal<Never, TransportError>
    
    /// Stop the transport gracefully.
    /// - Returns: A signal that completes when the tunnel is stopped
    func stop() -> Signal<Never, NoError>
    
    /// Handle an IPC message from the main app.
    /// - Parameter data: Encoded message data
    /// - Returns: Optional response data
    func handleAppMessage(_ data: Data) -> Signal<Data?, NoError>
}

/// Protocol abstracting NEPacketTunnelProvider for testability.
/// The real implementation wraps the actual NEPacketTunnelProvider.
public protocol PacketTunnelProviding: AnyObject {
    
    /// Set the tunnel network settings (routes, DNS, MTU, etc.)
    func setTunnelNetworkSettings(
        _ tunnelNetworkSettings: Any?,
        completionHandler: ((Error?) -> Void)?
    )
    
    /// The packet flow for reading/writing IP packets
    var tunnelPacketFlow: Any { get }
    
    /// Cancel the tunnel with an error
    func cancelTunnelWithError(_ error: Error?)
    
    /// Mark the tunnel as reasserting (reconnecting)
    var tunnelReassertingFlag: Bool { get set }
}

/// Protocol abstracting NETunnelProviderManager for testability.
public protocol TunnelProviderManaging: AnyObject {
    
    /// Load all saved VPN configurations
    static func loadAll(completionHandler: @escaping ([TunnelProviderManaging]?, Error?) -> Void)
    
    /// Save the VPN configuration
    func saveToPreferences(completionHandler: ((Error?) -> Void)?)
    
    /// Load the VPN configuration from preferences
    func loadFromPreferences(completionHandler: @escaping (Error?) -> Void)
    
    /// Remove the VPN configuration
    func removeFromPreferences(completionHandler: ((Error?) -> Void)?)
    
    /// The VPN connection object
    var tunnelConnection: VPNConnectionProviding { get }
    
    /// The VPN protocol configuration
    var tunnelProtocolConfiguration: Any? { get set }
    
    /// Whether the VPN is enabled
    var isVPNEnabled: Bool { get set }
    
    /// The localized description
    var vpnLocalizedDescription: String? { get set }
}

/// Protocol abstracting NEVPNConnection for testability.
public protocol VPNConnectionProviding: AnyObject {
    
    /// Current VPN connection status (maps to NEVPNStatus raw values)
    var vpnStatus: Int { get }
    
    /// Date when the connection was established
    var vpnConnectedDate: Date? { get }
    
    /// Start the VPN tunnel
    func startVPNTunnel(options: [String: NSObject]?) throws
    
    /// Stop the VPN tunnel
    func stopVPNTunnel()
    
    /// Send a message to the tunnel provider and get a response
    func sendProviderMessage(_ messageData: Data, responseHandler: ((Data?) -> Void)?) throws
}
