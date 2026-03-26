import Foundation
import UIKit
import SwiftSignalKit
import TunnelKit
import TunnelManager
import TunnelUI

// Backwoods: Tunnel Bridge
// This file bridges the tunnel subsystem into the Telegram app lifecycle.
// It handles:
//   1. Tunnel initialization before Telegram networking starts
//   2. Status bar indicator injection
//   3. Settings screen registration
//   4. App lifecycle events (foreground/background)
//
// Integration: Call BackwoodsTunnelBridge.shared.initialize() in AppDelegate
// BEFORE any Telegram networking code runs.

public final class BackwoodsTunnelBridge {
    
    public static let shared = BackwoodsTunnelBridge()
    
    // MARK: - Properties
    
    private var isInitialized = false
    private var statusView: TunnelStatusView?
    private var statusDisposable: Disposable?
    private var lifecycleDisposable: Disposable?
    
    /// Signal that emits `true` when the tunnel is ready for networking.
    /// Telegram networking should wait for this signal before proceeding.
    public let tunnelReady = Promise<Bool>()
    
    /// Signal that emits the current tunnel status.
    public var tunnelStatus: Signal<TransportStatus, NoError> {
        return TunnelManager.shared.status
    }
    
    private init() {}
    
    // MARK: - Initialization
    
    /// Initialize the tunnel subsystem. Call this ONCE at app launch,
    /// BEFORE Telegram's networking layer starts.
    ///
    /// Flow:
    ///   1. Load embedded WireGuard configuration
    ///   2. Setup TunnelManager with the configuration
    ///   3. Start the tunnel
    ///   4. Wait for .connected status
    ///   5. Set tunnelReady to true
    ///
    /// If the tunnel fails to start, the app will still launch but
    /// networking will go through the tunnel (which will be down),
    /// effectively blocking all traffic (kill-switch behavior).
    public func initialize() {
        guard !isInitialized else {
            TunnelLogger.shared.log("BackwoodsTunnelBridge: уже инициализирован", level: .warning)
            return
        }
        isInitialized = true
        
        TunnelLogger.shared.log("BackwoodsTunnelBridge: инициализация...", level: .info)
        
        // Step 1: Load configuration
        guard let configuration = loadConfiguration() else {
            TunnelLogger.shared.log("BackwoodsTunnelBridge: не удалось загрузить конфигурацию", level: .error)
            tunnelReady.set(.single(false))
            return
        }
        
        // Step 2: Setup TunnelManager
        let setupSignal = TunnelManager.shared.setup(configuration: configuration)
        
        statusDisposable = (setupSignal
        |> deliverOnMainQueue).start(next: { [weak self] success in
            if success {
                TunnelLogger.shared.log("BackwoodsTunnelBridge: менеджер настроен", level: .info)
                self?.startTunnelAndWait()
            } else {
                TunnelLogger.shared.log("BackwoodsTunnelBridge: ошибка настройки менеджера", level: .error)
                self?.tunnelReady.set(.single(false))
            }
        })
        
        // Step 3: Register for lifecycle events
        registerLifecycleEvents()
    }
    
    // MARK: - Tunnel Lifecycle
    
    private func startTunnelAndWait() {
        TunnelLogger.shared.log("BackwoodsTunnelBridge: запуск туннеля...", level: .info)
        
        let connectSignal = TunnelManager.shared.ensureConnected()
        
        let _ = (connectSignal
        |> deliverOnMainQueue).start(next: { [weak self] connected in
            if connected {
                TunnelLogger.shared.log("BackwoodsTunnelBridge: туннель подключен ✓", level: .info)
                self?.tunnelReady.set(.single(true))
            } else {
                TunnelLogger.shared.log("BackwoodsTunnelBridge: не удалось подключить туннель", level: .error)
                // Kill-switch: tunnelReady stays false, all traffic blocked
                self?.tunnelReady.set(.single(false))
            }
        })
    }
    
    // MARK: - Configuration Loading
    
    private func loadConfiguration() -> TransportConfiguration? {
        // Try App Groups first (allows remote config updates)
        if let config = TransportConfiguration.loadFromAppGroup() {
            TunnelLogger.shared.log("BackwoodsTunnelBridge: конфигурация из App Group", level: .info)
            return config
        }
        
        // Fallback to embedded configuration
        if let config = TransportConfiguration.loadEmbedded() {
            TunnelLogger.shared.log("BackwoodsTunnelBridge: встроенная конфигурация", level: .info)
            return config
        }
        
        return nil
    }
    
    // MARK: - App Lifecycle
    
    private func registerLifecycleEvents() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidBecomeActive() {
        TunnelLogger.shared.log("BackwoodsTunnelBridge: приложение активно", level: .debug)
        // Check tunnel status and reconnect if needed
        let _ = TunnelManager.shared.ensureConnected()
    }
    
    @objc private func appDidEnterBackground() {
        TunnelLogger.shared.log("BackwoodsTunnelBridge: приложение в фоне", level: .debug)
        // Tunnel continues running via NEPacketTunnelProvider
        // No action needed — extension runs independently
    }
    
    // MARK: - Status Bar Indicator
    
    /// Install the tunnel status indicator in a navigation bar.
    /// Call this from the main chat list controller.
    ///
    /// - Parameter navigationItem: The navigation item to add the indicator to
    public func installStatusIndicator(in navigationItem: UINavigationItem) {
        let view = TunnelStatusView(frame: CGRect(x: 0, y: 0, width: 60, height: 20))
        self.statusView = view
        
        let barButton = UIBarButtonItem(customView: view)
        
        // Add as left bar button item (before the edit button)
        var leftItems = navigationItem.leftBarButtonItems ?? []
        leftItems.insert(barButton, at: 0)
        navigationItem.leftBarButtonItems = leftItems
    }
    
    // MARK: - Settings
    
    /// Create and return a TunnelSettingsController for pushing onto a navigation stack.
    public func createSettingsController() -> UIViewController {
        return TunnelSettingsController()
    }
    
    // MARK: - Cleanup
    
    deinit {
        statusDisposable?.dispose()
        lifecycleDisposable?.dispose()
        NotificationCenter.default.removeObserver(self)
    }
}
