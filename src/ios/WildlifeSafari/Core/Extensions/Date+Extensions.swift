//
// Date+Extensions.swift
// WildlifeSafari
//
// Thread-safe Date extensions providing comprehensive date formatting and
// manipulation capabilities with localization support for the Wildlife Safari app.
//
// Version: 1.0
// Foundation version: Latest
//

import Foundation
import Constants

// MARK: - Private Formatters and Calendar

extension Date {
    /// Thread-safe singleton date formatter for general timestamp formatting
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    /// Thread-safe singleton ISO8601 formatter for API communications
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    /// Thread-safe singleton calendar instance
    private static let calendar: Calendar = {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        return calendar
    }()
    
    /// Serial queue for thread-safe date operations
    private static let dateQueue = DispatchQueue(label: "com.wildlifesafari.date.operations")
}

// MARK: - Public Properties

extension Date {
    /// Indicates if the sync interval has passed since the last sync
    public var isPastSyncInterval: Bool {
        return timeIntervalSinceLastSync > AppConstants.Storage.syncInterval
    }
    
    /// Returns a formatted timestamp string for display
    public var formattedTimestamp: String {
        return Date.dateQueue.sync {
            Date.dateFormatter.string(from: self)
        }
    }
    
    /// Returns a localized relative time description (e.g., "2 hours ago")
    public var relativeTimeDescription: String {
        return Date.dateQueue.sync {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: self, relativeTo: Date())
        }
    }
    
    /// Returns a localized date string according to user's preferences
    public var localizedDate: String {
        return Date.dateQueue.sync {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            formatter.locale = Locale.current
            return formatter.string(from: self)
        }
    }
}

// MARK: - Public Methods

extension Date {
    /// Calculates the time interval since the last sync operation
    /// - Returns: Time interval in seconds since last sync
    public func timeIntervalSinceLastSync() -> TimeInterval {
        return Date.dateQueue.sync {
            guard let lastSync = UserDefaults.standard.object(forKey: "LastSyncDate") as? Date else {
                return TimeInterval.greatestFiniteMagnitude
            }
            return self.timeIntervalSince(lastSync)
        }
    }
    
    /// Formats the date in ISO8601 format for API requests
    /// - Returns: ISO8601 formatted string with millisecond precision
    public func formattedForAPI() -> String {
        return Date.dateQueue.sync {
            return Date.iso8601Formatter.string(from: self)
        }
    }
    
    /// Returns a new date by adding specified minutes
    /// - Parameter minutes: Number of minutes to add
    /// - Returns: New date with added minutes, nil if invalid input
    public func addingMinutes(_ minutes: Int) -> Date? {
        return Date.dateQueue.sync {
            guard minutes >= 0 else { return nil }
            
            var components = DateComponents()
            components.minute = minutes
            
            return Date.calendar.date(byAdding: components, to: self)
        }
    }
    
    /// Checks if the date is in the same day as another date
    /// - Parameter otherDate: Date to compare with
    /// - Returns: True if dates are in the same day
    public func isSameDay(as otherDate: Date) -> Bool {
        return Date.dateQueue.sync {
            let calendar = Date.calendar
            let components1 = calendar.dateComponents([.year, .month, .day], from: self)
            let components2 = calendar.dateComponents([.year, .month, .day], from: otherDate)
            
            return components1.year == components2.year &&
                   components1.month == components2.month &&
                   components1.day == components2.day
        }
    }
}

// MARK: - Error Handling Extension

extension Date {
    /// Safely executes a date operation with error handling
    /// - Parameter operation: The date operation to perform
    /// - Returns: Optional result of the operation
    private static func safelyExecute<T>(_ operation: () throws -> T) -> T? {
        do {
            return try operation()
        } catch {
            #if DEBUG
            print("Date operation failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }
}