import Foundation

// Backwoods: Tunnel constants
// Centralized configuration for timeouts, retry intervals, and other constants.

public enum TunnelConstants {
    
    // MARK: - Connection Timeouts
    
    /// Maximum time to wait for tunnel connection during app launch (seconds)
    public static let launchConnectionTimeout: TimeInterval = 10.0
    
    /// Maximum time to wait for setTunnelNetworkSettings to complete (seconds)
    /// WireGuardKit uses 5s for a known iOS bug where the completion handler may never fire
    public static let networkSettingsTimeout: TimeInterval = 5.0
    
    /// Maximum time to wait for a reconnection attempt (seconds)
    public static let reconnectTimeout: TimeInterval = 15.0
    
    // MARK: - Retry Configuration
    
    /// Initial delay before first retry attempt (seconds)
    public static let retryInitialDelay: TimeInterval = 1.0
    
    /// Maximum delay between retry attempts (seconds)
    public static let retryMaxDelay: TimeInterval = 30.0
    
    /// Backoff multiplier for retry delays
    public static let retryBackoffMultiplier: Double = 2.0
    
    /// Maximum number of retry attempts before giving up
    public static let retryMaxAttempts: Int = 5
    
    // MARK: - WireGuard
    
    /// Default PersistentKeepalive interval (seconds)
    /// 25s is recommended for NAT traversal without excessive battery drain
    public static let wireGuardPersistentKeepalive: Int = 25
    
    /// Default MTU for iOS tunnel interface
    /// 1280 is the IPv6 minimum MTU and avoids fragmentation on most networks
    public static let wireGuardDefaultMTU: Int = 1280
    
    /// Default WireGuard server port
    public static let wireGuardDefaultPort: Int = 51820
    
    // MARK: - Go Runtime (Network Extension)
    
    /// Memory limit for the Go runtime in the Network Extension process
    /// Network Extension has ~50MB total limit; we cap Go at 30MB
    public static let goMemoryLimitMiB: Int = 30
    
    /// Go GC target percentage (100 = default, 200 = less frequent GC)
    public static let goGCPercent: Int = 100
    
    // MARK: - IPC
    
    /// Timeout for IPC messages between app and extension (seconds)
    public static let ipcMessageTimeout: TimeInterval = 5.0
    
    // MARK: - App Groups
    
    /// App Group identifier suffix (prepended with "group." + bundle_id)
    public static let appGroupSuffix: String = "tunnel"
    
    /// Shared config file name in App Group container
    public static let sharedConfigFileName: String = "tunnel-config.json"
    
    /// Shared log file name in App Group container
    public static let sharedLogFileName: String = "tunnel.log"
    
    // MARK: - Logging
    
    /// Maximum log file size before rotation (bytes)
    public static let maxLogFileSize: UInt64 = 5 * 1024 * 1024 // 5 MB
    
    /// Log subsystem identifier
    public static let logSubsystem: String = "com.backwoods.tunnel"
    
    // MARK: - Status Polling
    
    /// How often to poll the extension for detailed status (seconds)
    /// Used only for UI display; state changes are reported via NEVPNStatusDidChange
    public static let statusPollInterval: TimeInterval = 5.0
    
    // MARK: - Network
    
    /// DNS servers to use inside the tunnel when not specified in config
    public static let defaultDNSServers: [String] = ["1.1.1.1", "8.8.8.8"]
    
    /// Full tunnel: route all IPv4 and IPv6 traffic through the tunnel
    public static let fullTunnelAllowedIPs: [String] = ["0.0.0.0/0", "::/0"]
    
    // MARK: - Helper Functions
    
    /// Build the App Group identifier from the main app's bundle ID
    public static func appGroupIdentifier(bundleId: String) -> String {
        return "group.\(bundleId)"
    }
    
    /// Build the Network Extension bundle ID from the main app's bundle ID
    public static func extensionBundleId(appBundleId: String) -> String {
        return "\(appBundleId).PacketTunnel"
    }
}
