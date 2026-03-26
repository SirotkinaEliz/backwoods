import Foundation
import NetworkExtension
import SwiftSignalKit
import TunnelKit

// Backwoods: WireGuard transport implementation
// Implements TransportProvider using WireGuardKit.
// This module is linked into the Network Extension target.

/// WireGuard implementation of TransportProvider.
/// Wraps WireGuardAdapter and manages the WireGuard tunnel lifecycle.
public final class WireGuardTransport: TransportProvider {
    
    // MARK: - Properties
    
    private let statusPromise = ValuePromise<TransportStatus>(.disconnected, ignoreRepeated: true)
    private let logger = TunnelLogger.shared
    
    /// The WireGuard adapter instance (from WireGuardKit)
    /// Type is `Any` to avoid hard compile dependency when WireGuardKit is not linked
    /// In production, this is cast to `WireGuardAdapter`
    private var adapter: Any?
    
    /// Current configuration
    private var currentConfig: WireGuardConfiguration?
    
    /// Connection start time
    private var connectedSince: Date?
    
    /// Weak reference to the tunnel provider
    private weak var tunnelProvider: PacketTunnelProviding?
    
    // MARK: - TransportProvider
    
    public var status: Signal<TransportStatus, NoError> {
        return self.statusPromise.get()
    }
    
    public init() {}
    
    public func start(
        configuration: TransportConfiguration,
        tunnelProvider: PacketTunnelProviding
    ) -> Signal<Never, TransportError> {
        return Signal { [weak self] subscriber in
            guard let self = self else {
                subscriber.putError(.connectionFailed(underlying: "Transport deallocated"))
                return EmptyDisposable
            }
            
            guard let wgConfig = configuration.wireGuard else {
                subscriber.putError(.configurationInvalid(reason: "WireGuard configuration is missing"))
                return EmptyDisposable
            }
            
            // Validate configuration
            switch wgConfig.validate() {
            case .failure(let error):
                subscriber.putError(error)
                return EmptyDisposable
            case .success:
                break
            }
            
            self.tunnelProvider = tunnelProvider
            self.currentConfig = wgConfig
            self.statusPromise.set(.connecting)
            
            self.logger.info("Starting WireGuard transport to \(wgConfig.peer.endpoint)")
            
            // Start the WireGuard adapter
            self.startWireGuardAdapter(
                config: wgConfig,
                tunnelProvider: tunnelProvider
            ) { result in
                switch result {
                case .success:
                    self.connectedSince = Date()
                    self.statusPromise.set(.connected)
                    self.logger.info("WireGuard tunnel established")
                    subscriber.putCompletion()
                    
                case .failure(let error):
                    self.statusPromise.set(.failed(.connectionFailed(underlying: error.localizedDescription)))
                    self.logger.error("WireGuard start failed: \(error.localizedDescription)")
                    subscriber.putError(.connectionFailed(underlying: error.localizedDescription))
                }
            }
            
            return ActionDisposable { [weak self] in
                self?.logger.debug("Start signal disposed")
            }
        }
    }
    
    public func stop() -> Signal<Never, NoError> {
        return Signal { [weak self] subscriber in
            guard let self = self else {
                subscriber.putCompletion()
                return EmptyDisposable
            }
            
            self.statusPromise.set(.disconnecting)
            self.logger.info("Stopping WireGuard transport")
            
            self.stopWireGuardAdapter { [weak self] in
                self?.connectedSince = nil
                self?.statusPromise.set(.disconnected)
                self?.logger.info("WireGuard tunnel stopped")
                subscriber.putCompletion()
            }
            
            return EmptyDisposable
        }
    }
    
    public func handleAppMessage(_ data: Data) -> Signal<Data?, NoError> {
        return Signal { [weak self] subscriber in
            guard let self = self,
                  let message = TunnelIPCCodec.decode(data) else {
                subscriber.putNext(nil)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            
            switch message {
            case .requestStatus:
                let statusInfo = self.buildStatusInfo()
                let response = TunnelIPCMessage.statusResponse(statusInfo)
                let responseData = TunnelIPCCodec.encode(response)
                subscriber.putNext(responseData)
                
            case .requestReconnect:
                self.logger.info("Reconnect requested via IPC")
                // Reconnect will be handled by the PacketTunnelProvider
                subscriber.putNext(nil)
                
            case .requestLog:
                let log = TunnelLogger.readSharedLog(
                    groupIdentifier: "group.com.backwoods.app"
                ) ?? "No logs available"
                let response = TunnelIPCMessage.logResponse(log)
                let responseData = TunnelIPCCodec.encode(response)
                subscriber.putNext(responseData)
                
            default:
                subscriber.putNext(nil)
            }
            
            subscriber.putCompletion()
            return EmptyDisposable
        }
    }
    
    // MARK: - WireGuard Adapter Management
    
    /// Start the WireGuard adapter.
    /// This method bridges to WireGuardKit's WireGuardAdapter.
    ///
    /// In the actual build, WireGuardKit provides:
    /// - `WireGuardAdapter(with: NEPacketTunnelProvider, logHandler:)`
    /// - `adapter.start(tunnelConfiguration:completionHandler:)`
    ///
    /// We reference WireGuardKit types through a dynamic approach to keep
    /// this file compilable even without WireGuardKit linked (for testing).
    private func startWireGuardAdapter(
        config: WireGuardConfiguration,
        tunnelProvider: PacketTunnelProviding,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Set Go runtime memory limit before starting
        setGoRuntimeEnvironment()
        
        let wgQuickConfig = config.toWgQuickConfig()
        
        logger.debug("WireGuard config:\n\(redactConfig(wgQuickConfig))")
        
        // Bridge to WireGuardKit
        // In production build, this calls:
        //   let adapter = WireGuardAdapter(with: tunnelProvider as! NEPacketTunnelProvider, logHandler: { ... })
        //   let tunnelConfig = try TunnelConfiguration(fromWgQuickConfig: wgQuickConfig)
        //   adapter.start(tunnelConfiguration: tunnelConfig) { error in ... }
        //
        // For now, we define the interface contract and the real binding happens
        // when WireGuardKit.xcframework is linked.
        
        #if canImport(WireGuardKit)
        startWithWireGuardKit(config: wgQuickConfig, tunnelProvider: tunnelProvider, completion: completion)
        #else
        // Stub for compilation without WireGuardKit
        logger.warning("WireGuardKit not available — using stub")
        completion(.failure(TransportError.configurationInvalid(reason: "WireGuardKit not linked")))
        #endif
    }
    
    private func stopWireGuardAdapter(completion: @escaping () -> Void) {
        #if canImport(WireGuardKit)
        stopWithWireGuardKit(completion: completion)
        #else
        completion()
        #endif
    }
    
    /// Set Go runtime environment variables for memory management.
    /// Called before wgTurnOn to constrain Go heap within the extension's memory limit.
    private func setGoRuntimeEnvironment() {
        let memLimit = TunnelConstants.goMemoryLimitMiB
        setenv("GOMEMLIMIT", "\(memLimit)MiB", 1)
        setenv("GOGC", "\(TunnelConstants.goGCPercent)", 1)
        logger.debug("Go runtime: GOMEMLIMIT=\(memLimit)MiB, GOGC=\(TunnelConstants.goGCPercent)")
    }
    
    /// Redact sensitive keys from config for logging
    private func redactConfig(_ config: String) -> String {
        var redacted = config
        let patterns = ["PrivateKey = ", "PresharedKey = "]
        for pattern in patterns {
            if let range = redacted.range(of: pattern) {
                let afterKey = redacted[range.upperBound...]
                if let lineEnd = afterKey.firstIndex(of: "\n") {
                    redacted.replaceSubrange(range.upperBound..<lineEnd, with: "[REDACTED]")
                } else {
                    redacted.replaceSubrange(range.upperBound..., with: "[REDACTED]")
                }
            }
        }
        return redacted
    }
    
    /// Build status info for IPC response
    private func buildStatusInfo() -> TunnelIPCMessage.TransportStatusInfo {
        return TunnelIPCMessage.TransportStatusInfo(
            status: statusDescription(),
            connectedSince: connectedSince,
            serverHost: currentConfig?.peer.endpoint ?? "unknown",
            bytesReceived: 0, // TODO: Get from WireGuard adapter runtime config
            bytesSent: 0
        )
    }
    
    private func statusDescription() -> String {
        // Read current status synchronously for IPC
        // In production, query adapter.getRuntimeConfiguration()
        if connectedSince != nil {
            return "connected"
        } else {
            return "disconnected"
        }
    }
}

// MARK: - WireGuardKit Integration

#if canImport(WireGuardKit)
import WireGuardKit

extension WireGuardTransport {
    
    private func startWithWireGuardKit(
        config wgQuickConfig: String,
        tunnelProvider: PacketTunnelProviding,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let provider = tunnelProvider as? NEPacketTunnelProvider else {
            completion(.failure(TransportError.configurationInvalid(
                reason: "tunnelProvider is not NEPacketTunnelProvider"
            )))
            return
        }
        
        let wgAdapter = WireGuardAdapter(with: provider) { [weak self] logLevel, message in
            switch logLevel {
            case .verbose:
                self?.logger.debug("WG: \(message)")
            case .error:
                self?.logger.error("WG: \(message)")
            }
        }
        
        self.adapter = wgAdapter
        
        do {
            let tunnelConfiguration = try TunnelConfiguration(fromWgQuickConfig: wgQuickConfig, called: "tunnel")
            
            wgAdapter.start(tunnelConfiguration: tunnelConfiguration) { adapterError in
                if let error = adapterError {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    private func stopWithWireGuardKit(completion: @escaping () -> Void) {
        guard let wgAdapter = adapter as? WireGuardAdapter else {
            completion()
            return
        }
        
        wgAdapter.stop { _ in
            completion()
        }
    }
    
    /// Called when the network path changes (WiFi ↔ LTE).
    /// Bumps WireGuard sockets to use the new interface.
    public func handleNetworkPathChange() {
        guard let wgAdapter = adapter as? WireGuardAdapter else { return }
        
        logger.info("Network path changed — bumping WireGuard sockets")
        statusPromise.set(.reconnecting)
        
        wgAdapter.update(tunnelConfiguration: nil) { [weak self] error in
            if let error = error {
                self?.logger.error("Socket bump failed: \(error.localizedDescription)")
            } else {
                self?.statusPromise.set(.connected)
                self?.logger.info("WireGuard sockets bumped successfully")
            }
        }
    }
}
#endif
