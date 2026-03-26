import Foundation
import NetworkExtension
import SwiftSignalKit
import TunnelKit

// Backwoods: TunnelManager
// Main app-side manager for the VPN tunnel.
// Wraps NETunnelProviderManager and provides reactive status via SwiftSignalKit.
//
// Responsibilities:
// 1. Create/load VPN configuration on first launch
// 2. Start/stop the tunnel
// 3. Monitor tunnel status via NEVPNStatusDidChange
// 4. Auto-reconnect on unexpected disconnects
// 5. IPC with the PacketTunnel extension
//
// Thread safety: All public methods deliver on MainQueue.

public final class TunnelManager {
    
    // MARK: - Singleton
    
    public static let shared = TunnelManager()
    
    // MARK: - Properties
    
    /// Reactive tunnel status
    private let statusPromise = ValuePromise<TransportStatus>(.disconnected, ignoreRepeated: true)
    public var status: Signal<TransportStatus, NoError> {
        return statusPromise.get()
    }
    
    /// Current status value (synchronous read)
    public private(set) var currentStatus: TransportStatus = .disconnected
    
    /// The NETunnelProviderManager instance (loaded from system preferences)
    private var vpnManager: NETunnelProviderManager?
    
    /// Status observation token
    private var statusObservation: NSObjectProtocol?
    
    /// Whether auto-reconnect is enabled
    public var autoReconnectEnabled: Bool = true
    
    /// The transport configuration
    private var configuration: TransportConfiguration?
    
    /// Disposable bag
    private var disposables = DisposableSet()
    
    /// Logger
    private let logger = TunnelLogger.shared
    
    /// Whether initial setup has been done
    private var isSetupComplete = false
    
    // MARK: - Initialization
    
    private init() {}
    
    deinit {
        disposables.dispose()
        if let observation = statusObservation {
            NotificationCenter.default.removeObserver(observation)
        }
    }
    
    // MARK: - Setup
    
    /// Initialize the tunnel manager. Must be called at app launch.
    /// Loads or creates the VPN configuration and starts status monitoring.
    ///
    /// - Parameter configuration: The transport configuration to use
    /// - Returns: Signal that completes when setup is done
    public func setup(configuration: TransportConfiguration) -> Signal<Void, TransportError> {
        return Signal { [weak self] subscriber in
            guard let self = self else {
                subscriber.putError(.connectionFailed(underlying: "TunnelManager deallocated"))
                return EmptyDisposable
            }
            
            self.configuration = configuration
            
            self.logger.info("TunnelManager: setup starting")
            
            self.loadOrCreateVPNConfiguration(configuration: configuration) { result in
                switch result {
                case .success:
                    self.startStatusObservation()
                    self.isSetupComplete = true
                    self.logger.info("TunnelManager: setup complete")
                    subscriber.putNext(Void())
                    subscriber.putCompletion()
                    
                case .failure(let error):
                    self.logger.error("TunnelManager: setup failed: \(error.localizedDescription)")
                    subscriber.putError(error)
                }
            }
            
            return ActionDisposable { }
        }
        |> deliverOnMainQueue
    }
    
    // MARK: - Connection Management
    
    /// Ensure the tunnel is connected. If already connected, completes immediately.
    /// If disconnected, starts the tunnel and waits for connection.
    ///
    /// - Returns: Signal that completes when connected, or errors on failure
    public func ensureConnected() -> Signal<Void, TransportError> {
        return Signal { [weak self] subscriber in
            guard let self = self else {
                subscriber.putError(.connectionFailed(underlying: "TunnelManager deallocated"))
                return EmptyDisposable
            }
            
            // Check current status
            let vpnStatus = self.vpnManager?.connection.status ?? .invalid
            
            switch vpnStatus {
            case .connected:
                self.logger.info("Tunnel already connected")
                subscriber.putNext(Void())
                subscriber.putCompletion()
                return EmptyDisposable
                
            case .connecting, .reasserting:
                self.logger.info("Tunnel is connecting — waiting...")
                // Fall through to wait for connected status
                
            case .disconnected, .invalid:
                self.logger.info("Tunnel not connected — starting...")
                do {
                    try self.startTunnel()
                } catch {
                    subscriber.putError(.connectionFailed(underlying: error.localizedDescription))
                    return EmptyDisposable
                }
                
            case .disconnecting:
                self.logger.info("Tunnel disconnecting — will reconnect...")
                // Wait for disconnect to complete, then we'll auto-reconnect
                
            @unknown default:
                break
            }
            
            // Wait for connected status with timeout
            let timeoutDisposable = MetaDisposable()
            
            let statusDisposable = self.status.start(next: { status in
                switch status {
                case .connected:
                    timeoutDisposable.dispose()
                    subscriber.putNext(Void())
                    subscriber.putCompletion()
                    
                case .failed(let error):
                    timeoutDisposable.dispose()
                    subscriber.putError(error)
                    
                default:
                    break // Keep waiting
                }
            })
            
            // Timeout
            let timeout = DispatchWorkItem {
                statusDisposable.dispose()
                subscriber.putError(.timeout)
            }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + TunnelConstants.launchConnectionTimeout,
                execute: timeout
            )
            timeoutDisposable.set(ActionDisposable {
                timeout.cancel()
            })
            
            return ActionDisposable {
                statusDisposable.dispose()
                timeoutDisposable.dispose()
            }
        }
        |> deliverOnMainQueue
    }
    
    /// Start the VPN tunnel
    public func startTunnel() throws {
        guard let vpnManager = vpnManager else {
            throw TransportError.configurationInvalid(reason: "VPN manager not initialized")
        }
        
        logger.info("Starting VPN tunnel")
        statusPromise.set(.connecting)
        
        let session = vpnManager.connection as? NETunnelProviderSession
        try session?.startVPNTunnel()
    }
    
    /// Stop the VPN tunnel
    public func stopTunnel() {
        logger.info("Stopping VPN tunnel")
        statusPromise.set(.disconnecting)
        vpnManager?.connection.stopVPNTunnel()
    }
    
    /// Reconnect the tunnel (stop then start)
    public func reconnect() {
        logger.info("Reconnecting tunnel")
        stopTunnel()
        
        // Wait briefly for disconnect, then reconnect
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            try? self?.startTunnel()
        }
    }
    
    // MARK: - IPC
    
    /// Send an IPC message to the tunnel extension
    public func sendMessage(_ message: TunnelIPCMessage) -> Signal<TunnelIPCMessage?, NoError> {
        return Signal { [weak self] subscriber in
            guard let self = self,
                  let session = self.vpnManager?.connection as? NETunnelProviderSession,
                  let messageData = TunnelIPCCodec.encode(message) else {
                subscriber.putNext(nil)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            
            do {
                try session.sendProviderMessage(messageData) { responseData in
                    if let data = responseData,
                       let response = TunnelIPCCodec.decode(data) {
                        subscriber.putNext(response)
                    } else {
                        subscriber.putNext(nil)
                    }
                    subscriber.putCompletion()
                }
            } catch {
                self.logger.error("Failed to send IPC message: \(error.localizedDescription)")
                subscriber.putNext(nil)
                subscriber.putCompletion()
            }
            
            return EmptyDisposable
        }
        |> deliverOnMainQueue
    }
    
    /// Request detailed status from the extension
    public func requestDetailedStatus() -> Signal<TunnelIPCMessage.TransportStatusInfo?, NoError> {
        return sendMessage(.requestStatus)
        |> map { response -> TunnelIPCMessage.TransportStatusInfo? in
            if case .statusResponse(let info) = response {
                return info
            }
            return nil
        }
    }
    
    /// Request logs from the extension
    public func requestLogs() -> Signal<String?, NoError> {
        return sendMessage(.requestLog)
        |> map { response -> String? in
            if case .logResponse(let log) = response {
                return log
            }
            return nil
        }
    }
    
    // MARK: - VPN Configuration Management
    
    /// Load existing VPN configuration or create a new one
    private func loadOrCreateVPNConfiguration(
        configuration: TransportConfiguration,
        completion: @escaping (Result<Void, TransportError>) -> Void
    ) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("Failed to load VPN configurations: \(error.localizedDescription)")
                completion(.failure(.connectionFailed(underlying: error.localizedDescription)))
                return
            }
            
            // Find existing Backwoods VPN configuration
            if let existingManager = managers?.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier?.hasSuffix(".PacketTunnel") ?? false
            }) {
                self.logger.info("Found existing VPN configuration")
                self.vpnManager = existingManager
                
                // Update configuration if changed
                self.updateVPNConfiguration(manager: existingManager, configuration: configuration, completion: completion)
            } else {
                self.logger.info("No existing VPN configuration — creating new one")
                self.createVPNConfiguration(configuration: configuration, completion: completion)
            }
        }
    }
    
    /// Create a new VPN configuration
    private func createVPNConfiguration(
        configuration: TransportConfiguration,
        completion: @escaping (Result<Void, TransportError>) -> Void
    ) {
        let manager = NETunnelProviderManager()
        
        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = TunnelConstants.extensionBundleId(
            appBundleId: Bundle.main.bundleIdentifier ?? "com.backwoods.app"
        )
        tunnelProtocol.serverAddress = configuration.wireGuard?.peer.endpoint ?? "server"
        tunnelProtocol.providerConfiguration = configuration.toProviderConfiguration()
        
        // Disconnect on sleep = NO (keep tunnel alive)
        tunnelProtocol.disconnectOnSleep = false
        
        manager.protocolConfiguration = tunnelProtocol
        manager.localizedDescription = "Backwoods Tunnel"
        manager.isEnabled = true
        
        // Include all networks — kill switch behavior
        // When tunnel is active, all traffic MUST go through it
        if #available(iOS 14.0, *) {
            tunnelProtocol.includeAllNetworks = true
            tunnelProtocol.excludeLocalNetworks = true
        }
        
        manager.saveToPreferences { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to save VPN configuration: \(error.localizedDescription)")
                completion(.failure(.connectionFailed(underlying: error.localizedDescription)))
                return
            }
            
            // Must reload after saving for the first time
            manager.loadFromPreferences { [weak self] error in
                if let error = error {
                    self?.logger.error("Failed to reload VPN configuration: \(error.localizedDescription)")
                    completion(.failure(.connectionFailed(underlying: error.localizedDescription)))
                    return
                }
                
                self?.vpnManager = manager
                self?.logger.info("VPN configuration created and saved")
                completion(.success(()))
            }
        }
    }
    
    /// Update an existing VPN configuration with new settings
    private func updateVPNConfiguration(
        manager: NETunnelProviderManager,
        configuration: TransportConfiguration,
        completion: @escaping (Result<Void, TransportError>) -> Void
    ) {
        guard let tunnelProtocol = manager.protocolConfiguration as? NETunnelProviderProtocol else {
            completion(.failure(.configurationInvalid(reason: "Invalid existing protocol configuration")))
            return
        }
        
        tunnelProtocol.providerConfiguration = configuration.toProviderConfiguration()
        tunnelProtocol.serverAddress = configuration.wireGuard?.peer.endpoint ?? "server"
        tunnelProtocol.disconnectOnSleep = false
        
        if #available(iOS 14.0, *) {
            tunnelProtocol.includeAllNetworks = true
            tunnelProtocol.excludeLocalNetworks = true
        }
        
        manager.isEnabled = true
        
        manager.saveToPreferences { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to update VPN configuration: \(error.localizedDescription)")
                completion(.failure(.connectionFailed(underlying: error.localizedDescription)))
                return
            }
            
            self?.vpnManager = manager
            self?.logger.info("VPN configuration updated")
            completion(.success(()))
        }
    }
    
    // MARK: - Status Observation
    
    /// Start observing NEVPNStatusDidChange notifications
    private func startStatusObservation() {
        statusObservation = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: vpnManager?.connection,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let connection = notification.object as? NEVPNConnection else {
                return
            }
            
            self.handleVPNStatusChange(connection.status)
        }
        
        // Sync initial status
        if let currentVPNStatus = vpnManager?.connection.status {
            handleVPNStatusChange(currentVPNStatus)
        }
    }
    
    /// Map NEVPNStatus to our TransportStatus and handle auto-reconnect
    private func handleVPNStatusChange(_ vpnStatus: NEVPNStatus) {
        let newStatus: TransportStatus
        
        switch vpnStatus {
        case .invalid:
            newStatus = .disconnected
        case .disconnected:
            newStatus = .disconnected
        case .connecting:
            newStatus = .connecting
        case .connected:
            newStatus = .connected
        case .reasserting:
            newStatus = .reconnecting
        case .disconnecting:
            newStatus = .disconnecting
        @unknown default:
            newStatus = .disconnected
        }
        
        let previousStatus = currentStatus
        currentStatus = newStatus
        statusPromise.set(newStatus)
        
        logger.info("VPN status: \(vpnStatus.description) → TransportStatus: \(newStatus)")
        
        // Auto-reconnect: if we were connected/connecting and unexpectedly disconnected
        if autoReconnectEnabled &&
            newStatus == .disconnected &&
            (previousStatus == .connected || previousStatus == .reconnecting) {
            
            logger.warning("Unexpected disconnect — auto-reconnecting in \(TunnelConstants.retryInitialDelay)s")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + TunnelConstants.retryInitialDelay) { [weak self] in
                guard let self = self, self.autoReconnectEnabled, self.currentStatus == .disconnected else { return }
                try? self.startTunnel()
            }
        }
    }
}

// MARK: - NEVPNStatus Description

extension NEVPNStatus {
    var description: String {
        switch self {
        case .invalid: return "invalid"
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .reasserting: return "reasserting"
        case .disconnecting: return "disconnecting"
        @unknown default: return "unknown"
        }
    }
}
