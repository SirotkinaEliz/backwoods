import Foundation

// Backwoods: Transport configuration
// Codable structure for WireGuard and future transport protocols.
// Embedded at build time or loaded from App Groups shared container.

/// Top-level transport configuration
public struct TransportConfiguration: Codable, Equatable {
    
    /// The transport type identifier
    public let transportType: TransportType
    
    /// WireGuard-specific configuration (when transportType == .wireGuard)
    public let wireGuard: WireGuardConfiguration?
    
    /// Future: additional transport configs
    // public let obfuscated: ObfuscatedConfiguration?
    
    public init(
        transportType: TransportType,
        wireGuard: WireGuardConfiguration? = nil
    ) {
        self.transportType = transportType
        self.wireGuard = wireGuard
    }
    
    /// Validate the configuration
    public func validate() -> Result<Void, TransportError> {
        switch transportType {
        case .wireGuard:
            guard let wg = wireGuard else {
                return .failure(.configurationInvalid(reason: "WireGuard configuration is missing"))
            }
            return wg.validate()
        }
    }
}

/// Supported transport types
public enum TransportType: String, Codable, Equatable {
    case wireGuard = "wireguard"
    // Future Phase 2+:
    // case obfuscatedWireGuard = "wireguard-obfs"
    // case xray = "xray"
}

/// WireGuard-specific configuration
public struct WireGuardConfiguration: Codable, Equatable {
    
    /// Interface (client) configuration
    public let interface: WireGuardInterface
    
    /// Peer (server) configuration
    public let peer: WireGuardPeer
    
    public init(interface: WireGuardInterface, peer: WireGuardPeer) {
        self.interface = interface
        self.peer = peer
    }
    
    /// Validate the WireGuard configuration
    public func validate() -> Result<Void, TransportError> {
        // Validate private key (base64, 32 bytes)
        guard let keyData = Data(base64Encoded: interface.privateKey),
              keyData.count == 32 else {
            return .failure(.configurationInvalid(reason: "Invalid interface private key"))
        }
        
        // Validate peer public key
        guard let peerKeyData = Data(base64Encoded: peer.publicKey),
              peerKeyData.count == 32 else {
            return .failure(.configurationInvalid(reason: "Invalid peer public key"))
        }
        
        // Validate endpoint
        guard !peer.endpoint.isEmpty else {
            return .failure(.configurationInvalid(reason: "Peer endpoint is empty"))
        }
        
        // Validate allowed IPs
        guard !peer.allowedIPs.isEmpty else {
            return .failure(.configurationInvalid(reason: "Peer allowed IPs is empty"))
        }
        
        return .success(())
    }
    
    /// Generate the wg-quick format string for this configuration
    public func toWgQuickConfig() -> String {
        var lines: [String] = []
        
        lines.append("[Interface]")
        lines.append("PrivateKey = \(interface.privateKey)")
        
        if !interface.addresses.isEmpty {
            lines.append("Address = \(interface.addresses.joined(separator: ", "))")
        }
        
        if !interface.dns.isEmpty {
            lines.append("DNS = \(interface.dns.joined(separator: ", "))")
        }
        
        if let mtu = interface.mtu {
            lines.append("MTU = \(mtu)")
        }
        
        lines.append("")
        lines.append("[Peer]")
        lines.append("PublicKey = \(peer.publicKey)")
        
        if let presharedKey = peer.presharedKey {
            lines.append("PresharedKey = \(presharedKey)")
        }
        
        lines.append("Endpoint = \(peer.endpoint)")
        lines.append("AllowedIPs = \(peer.allowedIPs.joined(separator: ", "))")
        
        if let keepalive = peer.persistentKeepalive {
            lines.append("PersistentKeepalive = \(keepalive)")
        }
        
        return lines.joined(separator: "\n")
    }
}

/// WireGuard interface (client-side) configuration
public struct WireGuardInterface: Codable, Equatable {
    
    /// Client private key (base64 encoded, 32 bytes)
    public let privateKey: String
    
    /// Client tunnel addresses (e.g., ["10.0.0.2/32", "fd00::2/128"])
    public let addresses: [String]
    
    /// DNS servers to use inside the tunnel (e.g., ["1.1.1.1", "8.8.8.8"])
    public let dns: [String]
    
    /// Tunnel MTU (nil = automatic, typically 1280 on iOS)
    public let mtu: Int?
    
    public init(
        privateKey: String,
        addresses: [String],
        dns: [String],
        mtu: Int? = nil
    ) {
        self.privateKey = privateKey
        self.addresses = addresses
        self.dns = dns
        self.mtu = mtu
    }
}

/// WireGuard peer (server-side) configuration
public struct WireGuardPeer: Codable, Equatable {
    
    /// Server public key (base64 encoded, 32 bytes)
    public let publicKey: String
    
    /// Optional preshared key for additional security (base64 encoded, 32 bytes)
    public let presharedKey: String?
    
    /// Server endpoint (e.g., "198.51.100.1:51820" or "vpn.example.com:51820")
    public let endpoint: String
    
    /// CIDRs to route through the tunnel (e.g., ["0.0.0.0/0", "::/0"] for full tunnel)
    public let allowedIPs: [String]
    
    /// Keepalive interval in seconds (25 recommended for NAT traversal)
    public let persistentKeepalive: Int?
    
    public init(
        publicKey: String,
        presharedKey: String? = nil,
        endpoint: String,
        allowedIPs: [String],
        persistentKeepalive: Int? = nil
    ) {
        self.publicKey = publicKey
        self.presharedKey = presharedKey
        self.endpoint = endpoint
        self.allowedIPs = allowedIPs
        self.persistentKeepalive = persistentKeepalive
    }
}

// MARK: - Configuration Loading

public extension TransportConfiguration {
    
    /// Load the embedded default configuration.
    /// In production, this reads from the bundled config file.
    /// Keys and server details are embedded at build time.
    static func loadEmbedded() -> TransportConfiguration? {
        guard let url = Bundle.main.url(forResource: "tunnel-config", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(TransportConfiguration.self, from: data) else {
            return nil
        }
        return config
    }
    
    /// Load configuration from the shared App Group container.
    /// Used when the extension needs to read config set by the main app.
    static func loadFromAppGroup(groupIdentifier: String) -> TransportConfiguration? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            return nil
        }
        
        let configURL = containerURL.appendingPathComponent("tunnel-config.json")
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(TransportConfiguration.self, from: data) else {
            return nil
        }
        return config
    }
    
    /// Save configuration to the shared App Group container.
    func saveToAppGroup(groupIdentifier: String) -> Bool {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            return false
        }
        
        let configURL = containerURL.appendingPathComponent("tunnel-config.json")
        do {
            let data = try JSONEncoder().encode(self)
            try data.write(to: configURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
    
    /// Encode this configuration as provider configuration dictionary
    /// for NETunnelProviderProtocol.providerConfiguration
    func toProviderConfiguration() -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(self),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
    
    /// Decode from provider configuration dictionary
    static func fromProviderConfiguration(_ dict: [String: Any]) -> TransportConfiguration? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let config = try? JSONDecoder().decode(TransportConfiguration.self, from: data) else {
            return nil
        }
        return config
    }
}
