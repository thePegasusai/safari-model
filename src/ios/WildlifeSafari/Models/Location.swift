//
// Location.swift
// WildlifeSafari
//
// Secure location model for wildlife discoveries and fossil finds
// with support for data privacy and retention policies
//

import CoreLocation // Latest - iOS location services framework
import Foundation   // Latest - iOS foundation framework

/// Represents a geographical location with coordinate information and security features
@objc
@objcMembers
public class Location: NSObject, Codable {
    
    // MARK: - Properties
    
    /// The raw coordinate of the location
    private(set) var coordinate: CLLocationCoordinate2D
    
    /// The latitude component of the coordinate
    public var latitude: Double {
        return coordinate.latitude
    }
    
    /// The longitude component of the coordinate
    public var longitude: Double {
        return coordinate.longitude
    }
    
    /// Optional altitude in meters
    public private(set) var altitude: Double?
    
    /// Horizontal accuracy in meters
    public private(set) var horizontalAccuracy: Double?
    
    /// Vertical accuracy in meters
    public private(set) var verticalAccuracy: Double?
    
    /// Timestamp when the location was recorded
    public private(set) var timestamp: Date
    
    /// Additional context about the location (e.g., "Fossil Site", "Wildlife Sighting")
    public private(set) var locationContext: String?
    
    /// Flag indicating if the location has been anonymized
    public private(set) var isAnonymized: Bool
    
    /// Period for which this location data should be retained
    public private(set) var retentionPeriod: TimeInterval
    
    // MARK: - Constants
    
    private enum Constants {
        static let maximumLatitude: Double = 90.0
        static let maximumLongitude: Double = 180.0
        static let defaultRetentionPeriod: TimeInterval = 30 * 24 * 60 * 60 // 30 days
        static let anonymizationPrecision: Double = 0.01 // Roughly 1km
    }
    
    // MARK: - Initialization
    
    /// Initialize a new Location instance
    /// - Parameters:
    ///   - coordinate: The geographical coordinate
    ///   - altitude: Optional altitude in meters
    ///   - horizontalAccuracy: Horizontal accuracy in meters
    ///   - verticalAccuracy: Vertical accuracy in meters
    ///   - timestamp: Time of recording
    ///   - locationContext: Additional context about the location
    ///   - isAnonymized: Whether the location is anonymized
    ///   - retentionPeriod: How long to retain the data
    public init(
        coordinate: CLLocationCoordinate2D,
        altitude: Double? = nil,
        horizontalAccuracy: Double? = nil,
        verticalAccuracy: Double? = nil,
        timestamp: Date = Date(),
        locationContext: String? = nil,
        isAnonymized: Bool = false,
        retentionPeriod: TimeInterval = Constants.defaultRetentionPeriod
    ) {
        // Validate coordinate bounds
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            fatalError("Invalid coordinate provided")
        }
        
        self.coordinate = coordinate
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.timestamp = timestamp
        self.locationContext = locationContext
        self.isAnonymized = isAnonymized
        self.retentionPeriod = retentionPeriod
        
        super.init()
    }
    
    // MARK: - Factory Methods
    
    /// Create a Location instance from a CLLocation object
    /// - Parameters:
    ///   - location: The CLLocation object
    ///   - anonymize: Whether to anonymize the location
    ///   - retention: Data retention period
    /// - Returns: A new Location instance
    @objc
    public class func fromCLLocation(
        _ location: CLLocation,
        anonymize: Bool = false,
        retention: TimeInterval = Constants.defaultRetentionPeriod
    ) -> Location {
        let instance = Location(
            coordinate: location.coordinate,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            timestamp: location.timestamp,
            isAnonymized: anonymize,
            retentionPeriod: retention
        )
        
        return anonymize ? instance.anonymize() : instance
    }
    
    // MARK: - JSON Conversion
    
    /// Convert location to JSON dictionary
    /// - Returns: Dictionary representation of the location
    public func toJSON() -> [String: Any] {
        var json: [String: Any] = [
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude,
            "timestamp": timestamp.timeIntervalSince1970,
            "isAnonymized": isAnonymized,
            "retentionPeriod": retentionPeriod
        ]
        
        // Add optional values if present
        if let altitude = altitude {
            json["altitude"] = altitude
        }
        if let horizontalAccuracy = horizontalAccuracy {
            json["horizontalAccuracy"] = horizontalAccuracy
        }
        if let verticalAccuracy = verticalAccuracy {
            json["verticalAccuracy"] = verticalAccuracy
        }
        if let locationContext = locationContext {
            json["locationContext"] = locationContext
        }
        
        return json
    }
    
    /// Create Location from JSON dictionary
    /// - Parameter json: The JSON dictionary
    /// - Returns: Optional Location instance
    public class func fromJSON(_ json: [String: Any]) -> Location? {
        guard
            let latitude = json["latitude"] as? Double,
            let longitude = json["longitude"] as? Double,
            let timestamp = json["timestamp"] as? TimeInterval,
            let isAnonymized = json["isAnonymized"] as? Bool,
            let retentionPeriod = json["retentionPeriod"] as? TimeInterval,
            abs(latitude) <= Constants.maximumLatitude,
            abs(longitude) <= Constants.maximumLongitude
        else {
            return nil
        }
        
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        
        return Location(
            coordinate: coordinate,
            altitude: json["altitude"] as? Double,
            horizontalAccuracy: json["horizontalAccuracy"] as? Double,
            verticalAccuracy: json["verticalAccuracy"] as? Double,
            timestamp: Date(timeIntervalSince1970: timestamp),
            locationContext: json["locationContext"] as? String,
            isAnonymized: isAnonymized,
            retentionPeriod: retentionPeriod
        )
    }
    
    // MARK: - Utility Methods
    
    /// Calculate distance to another location
    /// - Parameter other: The other location
    /// - Returns: Distance in meters
    public func distanceTo(_ other: Location) -> CLLocationDistance {
        let selfLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let otherLocation = CLLocation(latitude: other.coordinate.latitude, longitude: other.coordinate.longitude)
        return selfLocation.distance(from: otherLocation)
    }
    
    /// Create an anonymized version of the location
    /// - Returns: Anonymized location
    public func anonymize() -> Location {
        // Round coordinates to reduce precision for privacy
        let roundedLatitude = (coordinate.latitude * (1.0 / Constants.anonymizationPrecision)).rounded() * Constants.anonymizationPrecision
        let roundedLongitude = (coordinate.longitude * (1.0 / Constants.anonymizationPrecision)).rounded() * Constants.anonymizationPrecision
        
        return Location(
            coordinate: CLLocationCoordinate2D(
                latitude: roundedLatitude,
                longitude: roundedLongitude
            ),
            timestamp: timestamp,
            locationContext: locationContext,
            isAnonymized: true,
            retentionPeriod: retentionPeriod
        )
    }
}

// MARK: - Codable Implementation

extension Location {
    private enum CodingKeys: String, CodingKey {
        case latitude, longitude, altitude, horizontalAccuracy, verticalAccuracy
        case timestamp, locationContext, isAnonymized, retentionPeriod
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encodeIfPresent(altitude, forKey: .altitude)
        try container.encodeIfPresent(horizontalAccuracy, forKey: .horizontalAccuracy)
        try container.encodeIfPresent(verticalAccuracy, forKey: .verticalAccuracy)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(locationContext, forKey: .locationContext)
        try container.encode(isAnonymized, forKey: .isAnonymized)
        try container.encode(retentionPeriod, forKey: .retentionPeriod)
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        
        guard abs(latitude) <= Constants.maximumLatitude,
              abs(longitude) <= Constants.maximumLongitude else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid coordinate values"
                )
            )
        }
        
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        altitude = try container.decodeIfPresent(Double.self, forKey: .altitude)
        horizontalAccuracy = try container.decodeIfPresent(Double.self, forKey: .horizontalAccuracy)
        verticalAccuracy = try container.decodeIfPresent(Double.self, forKey: .verticalAccuracy)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        locationContext = try container.decodeIfPresent(String.self, forKey: .locationContext)
        isAnonymized = try container.decode(Bool.self, forKey: .isAnonymized)
        retentionPeriod = try container.decode(TimeInterval.self, forKey: .retentionPeriod)
        
        super.init()
    }
}