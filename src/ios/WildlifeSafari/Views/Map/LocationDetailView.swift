//
// LocationDetailView.swift
// WildlifeSafari
//
// SwiftUI view component for displaying detailed location information
// with enhanced security and accessibility features.
//

import SwiftUI
import MapKit

// MARK: - Constants

private let kPadding: CGFloat = 16.0
private let kCornerRadius: CGFloat = 12.0
private let kCoordinateAnonymizationLevel: Int = 3
private let kMapZoomLevel: Double = 0.02

// MARK: - LocationDetailView

public struct LocationDetailView: View {
    // MARK: - Properties
    
    let discovery: Discovery
    let isOfflineMode: Bool
    
    @State private var region: MKCoordinateRegion
    @State private var hasLocationAccess: Bool = false
    @State private var showingFullCoordinates: Bool = false
    
    // MARK: - Initialization
    
    public init(discovery: Discovery, isOfflineMode: Bool = false) {
        self.discovery = discovery
        self.isOfflineMode = isOfflineMode
        
        // Initialize map region centered on discovery location
        let coordinate = discovery.location?.coordinate ?? CLLocationCoordinate2D()
        _region = State(initialValue: MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: kMapZoomLevel,
                longitudeDelta: kMapZoomLevel
            )
        ))
    }
    
    // MARK: - Body
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: kPadding) {
                // Map View
                mapSection
                
                // Location Details
                locationDetailsSection
                
                // Discovery Information
                discoveryInfoSection
                
                // Actions
                actionButtons
            }
            .padding(kPadding)
        }
        .navigationTitle("Location Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            hasLocationAccess = validateLocationAccess(discovery: discovery)
        }
    }
    
    // MARK: - View Components
    
    private var mapSection: some View {
        Map(coordinateRegion: $region, annotationItems: [discovery]) { discovery in
            MapAnnotation(coordinate: discovery.location?.coordinate ?? CLLocationCoordinate2D()) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.primary)
                    .font(.title)
                    .accessibilityLabel("Discovery location")
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: kCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: kCornerRadius)
                .stroke(Color.primary.opacity(0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Map showing discovery location")
    }
    
    private var locationDetailsSection: some View {
        VStack(alignment: .leading, spacing: kPadding/2) {
            Text("Coordinates")
                .font(.headline)
            
            if hasLocationAccess {
                coordinateDetails
            } else {
                Text("Coordinates hidden for species protection")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .cardStyle()
    }
    
    private var coordinateDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Latitude:")
                Text(formatCoordinate(
                    discovery.location?.latitude ?? 0,
                    shouldAnonymize: !showingFullCoordinates
                ))
                .monospaced()
            }
            
            HStack {
                Text("Longitude:")
                Text(formatCoordinate(
                    discovery.location?.longitude ?? 0,
                    shouldAnonymize: !showingFullCoordinates
                ))
                .monospaced()
            }
            
            if let altitude = discovery.location?.altitude {
                HStack {
                    Text("Altitude:")
                    Text("\(Int(altitude))m")
                        .monospaced()
                }
            }
            
            if hasLocationAccess {
                CustomButton(
                    showingFullCoordinates ? "Hide Full Coordinates" : "Show Full Coordinates",
                    style: .outline
                ) {
                    showingFullCoordinates.toggle()
                }
                .accessibilityHint("Double tap to toggle coordinate precision")
            }
        }
    }
    
    private var discoveryInfoSection: some View {
        VStack(alignment: .leading, spacing: kPadding/2) {
            Text("Discovery Information")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Date:")
                    Text(formatDate(discovery.timestamp))
                }
                
                HStack {
                    Text("Species:")
                    Text(discovery.species?.commonName ?? "Unknown")
                        .foregroundColor(.primary)
                }
                
                if isOfflineMode {
                    Text("Offline Mode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .cardStyle()
    }
    
    private var actionButtons: some View {
        HStack(spacing: kPadding) {
            CustomButton("Share Location", style: .secondary) {
                // Share functionality would be implemented here
            }
            .disabled(!hasLocationAccess)
            
            CustomButton("Directions", style: .primary) {
                // Navigation functionality would be implemented here
            }
        }
        .padding(.top, kPadding)
    }
    
    // MARK: - Helper Functions
    
    private func formatCoordinate(_ value: Double, shouldAnonymize: Bool) -> String {
        if shouldAnonymize {
            let factor = pow(10.0, Double(kCoordinateAnonymizationLevel))
            let anonymized = round(value * factor) / factor
            return String(format: "%.\(kCoordinateAnonymizationLevel)f", anonymized)
        }
        return String(format: "%.6f", value)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        
        let formattedDate = formatter.string(from: date)
        return formattedDate
    }
    
    private func validateLocationAccess(discovery: Discovery) -> Bool {
        // Check if species is sensitive and requires location protection
        guard let species = discovery.species else { return false }
        
        // Implement security checks based on species sensitivity and user authorization
        let isEndangered = species.isEndangered
        let hasAuthorization = !isOfflineMode // In real implementation, check user's authorization level
        
        return !isEndangered || hasAuthorization
    }
}

// MARK: - Preview Provider

#if DEBUG
struct LocationDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            LocationDetailView(
                discovery: Discovery(), // Mock discovery would be created here
                isOfflineMode: false
            )
        }
    }
}
#endif