import Foundation
import os.log

// Backwoods: Shared tunnel logger
// Uses os_log for structured logging. Logs can be written to shared App Group
// container for debug mode access from the main app.

public final class TunnelLogger {
    
    public enum Level: Int, Comparable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3
        
        public static func < (lhs: Level, rhs: Level) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
        
        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            }
        }
        
        var prefix: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            }
        }
    }
    
    public static let shared = TunnelLogger()
    
    private let osLog: OSLog
    private let fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.backwoods.tunnel.logger", qos: .utility)
    
    /// Minimum log level. Messages below this level are discarded.
    public var minimumLevel: Level = .info
    
    /// Whether to write logs to the shared file (for debug mode)
    public var writeToFile: Bool = false
    
    private init() {
        self.osLog = OSLog(subsystem: TunnelConstants.logSubsystem, category: "tunnel")
        
        // Attempt to open shared log file
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.backwoods.app"
        ) {
            let logURL = groupURL.appendingPathComponent(TunnelConstants.sharedLogFileName)
            
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            
            self.fileHandle = try? FileHandle(forWritingTo: logURL)
            self.fileHandle?.seekToEndOfFile()
        } else {
            self.fileHandle = nil
        }
    }
    
    deinit {
        fileHandle?.closeFile()
    }
    
    // MARK: - Logging Methods
    
    public func debug(_ message: @autoclosure () -> String, file: String = #file, function: String = #function) {
        log(level: .debug, message: message(), file: file, function: function)
    }
    
    public func info(_ message: @autoclosure () -> String, file: String = #file, function: String = #function) {
        log(level: .info, message: message(), file: file, function: function)
    }
    
    public func warning(_ message: @autoclosure () -> String, file: String = #file, function: String = #function) {
        log(level: .warning, message: message(), file: file, function: function)
    }
    
    public func error(_ message: @autoclosure () -> String, file: String = #file, function: String = #function) {
        log(level: .error, message: message(), file: file, function: function)
    }
    
    // MARK: - Core
    
    private func log(level: Level, message: String, file: String, function: String) {
        guard level >= minimumLevel else { return }
        
        let fileName = (file as NSString).lastPathComponent
        let logLine = "\(level.prefix) [\(fileName):\(function)] \(message)"
        
        // os_log for system console
        os_log("%{public}@", log: osLog, type: level.osLogType, logLine)
        
        // Optional file logging for debug mode
        if writeToFile {
            queue.async { [weak self] in
                self?.writeToLogFile(logLine)
            }
        }
    }
    
    private func writeToLogFile(_ line: String) {
        guard let fileHandle = fileHandle else { return }
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fullLine = "[\(timestamp)] \(line)\n"
        
        if let data = fullLine.data(using: .utf8) {
            fileHandle.write(data)
        }
        
        // Rotate if too large
        if fileHandle.offsetInFile > TunnelConstants.maxLogFileSize {
            fileHandle.truncateFile(atOffset: 0)
            fileHandle.seek(toFileOffset: 0)
            let header = "--- Log rotated at \(timestamp) ---\n"
            if let headerData = header.data(using: .utf8) {
                fileHandle.write(headerData)
            }
        }
    }
    
    // MARK: - Log Reading (from main app)
    
    /// Read the shared log file contents. Called from the main app for debug UI.
    public static func readSharedLog(groupIdentifier: String) -> String? {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            return nil
        }
        
        let logURL = groupURL.appendingPathComponent(TunnelConstants.sharedLogFileName)
        return try? String(contentsOf: logURL, encoding: .utf8)
    }
    
    /// Clear the shared log file. Called from the main app.
    public static func clearSharedLog(groupIdentifier: String) {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            return
        }
        
        let logURL = groupURL.appendingPathComponent(TunnelConstants.sharedLogFileName)
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
    }
}
