//
// MapView.swift
// WildlifeSafari
//
// A privacy-focused map interface for visualizing wildlife discoveries and fossil finds
// with comprehensive offline support and location tracking capabilities.
//

import SwiftUI
import MapKit

// MARK: - Constants

private enum Constants {
    static let mapPadding = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    static let animationDuration: Double = 0.3
    static let clusteringRadius: Double = 50.0
    static let maxAnnotations: Int = 1000
    static let locationAccuracy = kCLLocationAccuracyBest
}

// MARK: - MapView

/// Privacy-focused map view component for wildlife and fossil discovery visualization
public struct MapView: View {
    // MARK: - Properties
    
    @StateObject private var viewModel: MapViewModel
    @State private var showingLocationDetail: Bool = false
    @State private var isTrackingLocation: Bool = false
    @State private var showingPrivacyAlert: Bool = false
    @State private var userLocation: CLLocationCoordinate2D?
    
    // MARK: - Initialization
    
    public init(viewModel: MapViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    // MARK: - Body
    
    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Main Map View
            Map(coordinateRegion: $viewModel.region,
                showsUserLocation: isTrackingLocation,
                annotationItems: viewModel.discoveries) { discovery in
                MapAnnotation(coordinate: discovery.location?.coordinate ?? CLLocationCoordinate2D()) {
                    MapAnnotationView(
                        discovery: discovery,
                        isSelected: viewModel.selectedDiscovery?.id == discovery.id
                    ) {
                        handleAnnotationTap(discovery)
                    }
                }
            }
            .ignoresSafeArea()
            
            // Offline Mode Indicator
            if viewModel.isOfflineMode {
                offlineModeIndicator
            }
            
            // Location Controls
            VStack(spacing: 16) {
                locationTrackingButton
                
                if isTrackingLocation {
                    recenterButton
                }
            }
            .padding(Constants.mapPadding)
        }
        .sheet(isPresented: $showingLocationDetail) {
            if let selectedDiscovery = viewModel.selectedDiscovery {
                LocationDetailView(
                    discovery: selectedDiscovery,
                    isOfflineMode: viewModel.isOfflineMode
                )
                .standardPadding()
            }
        }
        .alert("Location Privacy", isPresented: $showingPrivacyAlert) {
            Button("Settings", role: .cancel) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Location access is required for tracking. You can enable it in Settings.")
        }
    }
    
    // MARK: - Private Views
    
    private var offlineModeIndicator: some View {
        HStack {
            Image(systemName: "wifi.slash")
            Text("Offline Mode")
                .font(.subheadline.weight(.medium))
        }
        .foregroundColor(.white)
        .padding(8)
        .background(Color.secondary.opacity(0.8))
        .cornerRadius(8)
        .padding(Constants.mapPadding)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityLabel("Offline mode active")
    }
    
    private var locationTrackingButton: some View {
        Button(action: handleLocationTrackingToggle) {
            Image(systemName: locationTrackingIcon)
                .font(.title2)
                .foregroundColor(.primary)
                .padding(12)
                .background(Color.surface)
                .clipShape(Circle())
                .standardElevation()
        }
        .accessibleTouchTarget()
        .accessibilityLabel(locationTrackingLabel)
    }
    
    private var recenterButton: some View {
        Button(action: recenterOnUserLocation) {
            Image(systemName: "location.fill")
                .font(.title2)
                .foregroundColor(.primary)
                .padding(12)
                .background(Color.surface)
                .clipShape(Circle())
                .standardElevation()
        }
        .accessibleTouchTarget()
        .accessibilityLabel("Recenter map on current location")
    }
    
    // MARK: - Computed Properties
    
    private var locationTrackingIcon: String {
        switch viewModel.locationAuthorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return isTrackingLocation ? "location.fill" : "location"
        default:
            return "location.slash"
        }
    }
    
    private var locationTrackingLabel: String {
        if isTrackingLocation {
            return "Stop location tracking"
        } else {
            return "Start location tracking"
        }
    }
    
    // MARK: - Private Methods
    
    private func handleAnnotationTap(_ discovery: Discovery) {
        withAnimation(.easeInOut(duration: Constants.animationDuration)) {
            viewModel.selectedDiscovery = discovery
            showingLocationDetail = true
        }
    }
    
    private func handleLocationTrackingToggle() {
        switch viewModel.locationAuthorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            withAnimation {
                isTrackingLocation.toggle()
                if isTrackingLocation {
                    viewModel.startLocationTracking()
                } else {
                    viewModel.stopLocationTracking()
                }
            }
        default:
            showingPrivacyAlert = true
        }
    }
    
    private func recenterOnUserLocation() {
        guard let location = userLocation else { return }
        withAnimation {
            viewModel.region = MKCoordinateRegion(
                center: location,
                span: MKCoordinateSpan(
                    latitudeDelta: 0.05,
                    longitudeDelta: 0.05
                )
            )
        }
    }
}

// MARK: - Preview Provider

#if DEBUG
struct MapView_Previews: PreviewProvider {
    static var previews: some View {
        MapView(viewModel: MapViewModel(
            locationManager: LocationManager.shared,
            collectionService: CollectionService(
                apiClient: APIClient(),
                coreDataStack: CoreDataStack(modelName: "WildlifeSafari"),
                syncService: SyncService(
                    apiClient: APIClient(),
                    coreDataStack: CoreDataStack(modelName: "WildlifeSafari")
                )
            )
        ))
    }
}
#endif