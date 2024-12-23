//
// Logger.swift
// WildlifeSafari
//
// A comprehensive logging utility that provides structured logging capabilities
// with configurable severity levels, contextual information capture, and
// performance tracking while integrating with the native iOS logging system.
//
// Foundation version: latest
// os.log version: latest
//

import Foundation
import os.log

/// Comprehensive enumeration of logging severity levels
@frozen public enum LogLevel: Int {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case critical = 4
    
    /// Maps LogLevel to corresponding OSLogType for system integration
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
    
    /// Visual indicator for log level
    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🆘"
        }
    }
}

/// Thread-safe log buffer for managing log entries
fileprivate class LogBuffer {
    private var entries: [(Date, String)] = []
    private let maxSize: Int
    private let queue = DispatchQueue(label: "com.wildlifesafari.logger.buffer")
    
    init(size: Int) {
        self.maxSize = size
    }
    
    func add(_ entry: String) {
        queue.async {
            self.entries.append((Date(), entry))
            if self.entries.count > self.maxSize {
                self.entries.removeFirst()
            }
        }
    }
    
    func flush() -> [(Date, String)] {
        var result: [(Date, String)] = []
        queue.sync {
            result = self.entries
            self.entries.removeAll()
        }
        return result
    }
}

/// Advanced logging class with comprehensive logging capabilities
@objc public class Logger: NSObject {
    // MARK: - Properties
    
    private let subsystem: String
    private let osLog: OSLog
    private let isDebugEnabled: Bool
    private let loggingQueue: DispatchQueue
    private let buffer: LogBuffer
    private let dateFormatter: DateFormatter
    
    // MARK: - Initialization
    
    /// Initializes a new logger instance with specified configuration
    /// - Parameters:
    ///   - subsystem: The subsystem identifier for logging
    ///   - isDebugEnabled: Flag to enable debug logging
    ///   - bufferSize: Size of the log buffer
    public init(subsystem: String, isDebugEnabled: Bool = false, bufferSize: Int = 1000) {
        self.subsystem = subsystem
        self.osLog = OSLog(subsystem: subsystem, category: "WildlifeSafari")
        self.isDebugEnabled = isDebugEnabled
        self.loggingQueue = DispatchQueue(label: "com.wildlifesafari.logger.\(subsystem)")
        self.buffer = LogBuffer(size: bufferSize)
        
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Enhanced logging method with context and performance tracking
    /// - Parameters:
    ///   - message: The message to log
    ///   - level: Severity level of the log
    ///   - file: Source file name
    ///   - line: Line number in source
    ///   - function: Function name
    public func log(
        _ message: String,
        level: LogLevel = .info,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        guard isDebugEnabled || level != .debug else { return }
        
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        
        let formattedMessage = """
            \(level.emoji) [\(timestamp)] [\(level)] [\(fileName):\(line)] \(function)
            \(message)
            """
        
        loggingQueue.async {
            if level >= .error {
                os_log("%{public}@", log: self.osLog, type: level.osLogType, formattedMessage)
            } else {
                self.buffer.add(formattedMessage)
            }
            
            #if DEBUG
            print(formattedMessage)
            #endif
        }
    }
    
    /// Comprehensive error logging with stack trace
    /// - Parameters:
    ///   - error: The error to log
    ///   - file: Source file name
    ///   - line: Line number in source
    ///   - function: Function name
    public func logError(
        _ error: Error,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        let errorMessage = """
            Error: \(error.localizedDescription)
            Type: \(type(of: error))
            Stack Trace:
            \(Thread.callStackSymbols.joined(separator: "\n"))
            """
        
        log(errorMessage, level: .error, file: file, line: line, function: function)
    }
    
    /// Specialized API error logging with endpoint and response details
    /// - Parameters:
    ///   - error: The API error to log
    ///   - endpoint: The API endpoint
    ///   - responseData: Optional response data
    public func logAPIError(
        _ error: APIError,
        endpoint: String,
        responseData: Data? = nil
    ) {
        let responseString = responseData.map { String(data: $0, encoding: .utf8) ?? "Unable to decode response data" }
        
        let errorMessage = """
            API Error: \(error.localizedDescription)
            Endpoint: \(endpoint)
            Response Data: \(responseString ?? "No response data")
            System Info:
            - iOS Version: \(UIDevice.current.systemVersion)
            - Device Model: \(UIDevice.current.model)
            - App Version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "Unknown")
            """
        
        log(errorMessage, level: .error)
    }
    
    /// Logs performance metrics with timing information
    /// - Parameters:
    ///   - operation: Name of the operation
    ///   - duration: Duration in milliseconds
    ///   - threshold: Optional custom threshold
    public func logPerformance(
        operation: String,
        duration: TimeInterval,
        threshold: TimeInterval? = nil
    ) {
        let performanceThreshold = threshold ?? AppConstants.API.requestTimeout
        let level: LogLevel = duration > performanceThreshold ? .warning : .info
        
        let message = """
            Performance Metric:
            Operation: \(operation)
            Duration: \(String(format: "%.2f", duration))ms
            Threshold: \(String(format: "%.2f", performanceThreshold))ms
            """
        
        log(message, level: level)
    }
    
    // MARK: - Private Methods
    
    private func flushBuffer() {
        loggingQueue.async {
            let entries = self.buffer.flush()
            entries.forEach { (date, message) in
                os_log("%{public}@", log: self.osLog, type: .default, message)
            }
        }
    }
}