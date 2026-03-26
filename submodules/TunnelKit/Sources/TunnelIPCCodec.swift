import Foundation

// Backwoods: IPC codec for app ↔ extension communication
// Uses JSON encoding for simplicity and debuggability.

public final class TunnelIPCCodec {
    
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    
    /// Encode an IPC message to Data for sendProviderMessage()
    public static func encode(_ message: TunnelIPCMessage) -> Data? {
        return try? encoder.encode(message)
    }
    
    /// Decode an IPC message from Data received in handleAppMessage()
    public static func decode(_ data: Data) -> TunnelIPCMessage? {
        return try? decoder.decode(TunnelIPCMessage.self, from: data)
    }
    
    /// Encode a TransportConfiguration for providerConfiguration
    public static func encodeConfiguration(_ config: TransportConfiguration) -> Data? {
        return try? encoder.encode(config)
    }
    
    /// Decode a TransportConfiguration from providerConfiguration
    public static func decodeConfiguration(_ data: Data) -> TransportConfiguration? {
        return try? decoder.decode(TransportConfiguration.self, from: data)
    }
}
