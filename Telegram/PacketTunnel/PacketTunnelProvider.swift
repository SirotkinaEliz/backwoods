import NetworkExtension
import Foundation
import TunnelKit
import WireGuardTransport

// Backwoods: PacketTunnelProvider
// NEPacketTunnelProvider subclass that manages the WireGuard tunnel.
// This runs in a separate process (Network Extension) with ~50MB memory limit.
//
// Lifecycle:
// 1. iOS calls startTunnel() when the VPN is enabled
// 2. We read config from protocolConfiguration.providerConfiguration
// 3. Start WireGuard via WireGuardTransport
// 4. Monitor network path changes via NWPathMonitor
// 5. iOS calls stopTunnel() when VPN is disabled
//
// The extension persists independently of the main app (background tunnel).

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    // MARK: - Properties
    
    /// The WireGuard transport implementation
    private lazy var transport: WireGuardTransport = {
        return WireGuardTransport()
    }()
    
    /// Network path monitor for detecting WiFi ↔ LTE transitions
    private var pathMonitor: NWPathMonitor?
    
    /// The logger instance
    private let logger = TunnelLogger.shared
    
    /// Disposable bag for SwiftSignalKit subscriptions
    private var disposables: [Any] = []
    
    /// Whether the tunnel is currently active
    private var isActive = false
    
    // MARK: - NEPacketTunnelProvider Lifecycle
    
    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        logger.info("PacketTunnelProvider: startTunnel called")
        
        // Enable file logging in extension
        TunnelLogger.shared.writeToFile = true
        TunnelLogger.shared.minimumLevel = .debug
        
        // Load configuration from protocolConfiguration
        guard let providerConfig = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration,
              let config = TransportConfiguration.fromProviderConfiguration(providerConfig) else {
            logger.error("Failed to load transport configuration from protocolConfiguration")
            completionHandler(TransportError.configurationInvalid(reason: "No configuration in protocolConfiguration"))
            return
        }
        
        // Validate config
        switch config.validate() {
        case .failure(let error):
            logger.error("Configuration validation failed: \(error.localizedDescription)")
            completionHandler(error)
            return
        case .success:
            break
        }
        
        logger.info("Configuration loaded: transport=\(config.transportType.rawValue)")
        
        // Create the provider adapter for testability
        let providerAdapter = PacketTunnelProviderAdapter(provider: self)
        
        // Start the transport
        // We use a timeout wrapper because setTunnelNetworkSettings can hang (known iOS bug)
        let startSignal = transport.start(
            configuration: config,
            tunnelProvider: providerAdapter
        )
        
        var completed = false
        let timeoutWorkItem = DispatchWorkItem {
            guard !completed else { return }
            completed = true
            self.logger.warning("startTunnel timed out after \(TunnelConstants.networkSettingsTimeout)s — proceeding anyway")
            completionHandler(nil)
        }
        
        DispatchQueue.main.asyncAfter(
            deadline: .now() + TunnelConstants.networkSettingsTimeout * 2,
            execute: timeoutWorkItem
        )
        
        let disposable = startSignal.start(
            error: { [weak self] error in
                guard !completed else { return }
                completed = true
                timeoutWorkItem.cancel()
                self?.logger.error("Transport start failed: \(error.localizedDescription)")
                completionHandler(error)
            },
            completed: { [weak self] in
                guard !completed else { return }
                completed = true
                timeoutWorkItem.cancel()
                self?.isActive = true
                self?.startNetworkPathMonitor()
                self?.logger.info("Tunnel started successfully")
                completionHandler(nil)
            }
        )
        
        disposables.append(disposable)
    }
    
    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        logger.info("PacketTunnelProvider: stopTunnel called (reason: \(reason.rawValue))")
        
        isActive = false
        stopNetworkPathMonitor()
        
        let disposable = transport.stop().start(completed: { [weak self] in
            self?.logger.info("Tunnel stopped")
            completionHandler()
        })
        
        disposables.append(disposable)
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        logger.debug("Received app message (\(messageData.count) bytes)")
        
        let disposable = transport.handleAppMessage(messageData).start(next: { responseData in
            completionHandler?(responseData)
        })
        
        disposables.append(disposable)
    }
    
    override func sleep(completionHandler: @escaping () -> Void) {
        logger.debug("Extension going to sleep")
        completionHandler()
    }
    
    override func wake() {
        logger.debug("Extension waking up")
        // WireGuard handles re-handshake automatically on wake
    }
    
    // MARK: - Network Path Monitoring
    
    /// Start monitoring network path changes for seamless WiFi ↔ LTE transitions.
    /// When the path changes, we bump WireGuard's sockets to use the new interface.
    private func startNetworkPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self, self.isActive else { return }
            
            self.logger.info("Network path changed: status=\(path.status), interfaces=\(path.availableInterfaces.map { $0.name })")
            
            if path.status == .satisfied {
                #if canImport(WireGuardKit)
                self.transport.handleNetworkPathChange()
                #endif
            } else {
                self.logger.warning("Network unavailable — waiting for recovery")
                // WireGuard will re-handshake when network returns
            }
        }
        
        monitor.start(queue: DispatchQueue(label: "com.backwoods.tunnel.pathmonitor"))
        self.pathMonitor = monitor
    }
    
    private func stopNetworkPathMonitor() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }
}

// MARK: - PacketTunnelProviderAdapter

/// Adapter that wraps NEPacketTunnelProvider to conform to PacketTunnelProviding protocol.
/// Enables testing of WireGuardTransport without a real NEPacketTunnelProvider.
final class PacketTunnelProviderAdapter: PacketTunnelProviding {
    
    private weak var provider: NEPacketTunnelProvider?
    
    init(provider: NEPacketTunnelProvider) {
        self.provider = provider
    }
    
    func setTunnelNetworkSettings(
        _ tunnelNetworkSettings: Any?,
        completionHandler: ((Error?) -> Void)?
    ) {
        provider?.setTunnelNetworkSettings(
            tunnelNetworkSettings as? NETunnelNetworkSettings,
            completionHandler: completionHandler
        )
    }
    
    var tunnelPacketFlow: Any {
        return provider?.packetFlow as Any
    }
    
    func cancelTunnelWithError(_ error: Error?) {
        provider?.cancelTunnelWithError(error)
    }
    
    var tunnelReassertingFlag: Bool {
        get { provider?.reasserting ?? false }
        set { provider?.reasserting = newValue }
    }
}

// MARK: - NEProviderStopReason Description

extension NEProviderStopReason {
    var rawValue: Int {
        switch self {
        case .none: return 0
        case .userInitiated: return 1
        case .providerFailed: return 2
        case .noNetworkAvailable: return 3
        case .unrecoverableNetworkChange: return 4
        case .providerDisabled: return 5
        case .authenticationCanceled: return 6
        case .configurationFailed: return 7
        case .idleTimeout: return 8
        case .configurationDisabled: return 9
        case .configurationRemoved: return 10
        case .superceded: return 11
        case .userLogout: return 12
        case .userSwitch: return 13
        case .connectionFailed: return 14
        case .sleep: return 15
        case .appUpdate: return 16
        @unknown default: return -1
        }
    }
}
