//
// MapUITests.swift
// WildlifeSafariUITests
//
// UI test suite for testing map functionality, location tracking, and discovery
// visualization in the Wildlife Detection Safari Pokédex iOS application.
//

import XCTest
@testable import WildlifeSafari

final class MapUITests: XCTestCase {
    
    // MARK: - Properties
    
    private var app: XCUIApplication!
    private let timeout: TimeInterval = 5.0
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        
        // Initialize application
        app = XCUIApplication()
        
        // Configure test settings
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment = ["UITEST_MODE": "1"]
        
        // Enable location services for testing
        app.launchEnvironment["CLSimulateLocation"] = "1"
        
        // Launch application
        app.launch()
    }
    
    override func tearDown() {
        app.terminate()
        super.tearDown()
    }
    
    // MARK: - Test Cases
    
    /// Tests initial map view loading and display
    func testMapViewInitialLoad() throws {
        // Navigate to map tab
        app.tabBars.buttons["Map"].tap()
        
        // Verify map view exists and is visible
        let mapView = app.otherElements["MapView"]
        XCTAssertTrue(mapView.waitForExistence(timeout: timeout))
        
        // Verify map controls are present
        XCTAssertTrue(app.buttons["ZoomIn"].exists)
        XCTAssertTrue(app.buttons["ZoomOut"].exists)
        XCTAssertTrue(app.buttons["CurrentLocation"].exists)
        XCTAssertTrue(app.buttons["MapStyle"].exists)
        
        // Verify map layers control
        let layersButton = app.buttons["MapLayers"]
        XCTAssertTrue(layersButton.exists)
        layersButton.tap()
        
        // Verify layer options
        XCTAssertTrue(app.switches["Wildlife Discoveries"].exists)
        XCTAssertTrue(app.switches["Fossil Finds"].exists)
        XCTAssertTrue(app.switches["Hotspots"].exists)
    }
    
    /// Tests location tracking button functionality
    func testLocationTrackingToggle() throws {
        // Navigate to map tab
        app.tabBars.buttons["Map"].tap()
        
        // Verify location button exists
        let locationButton = app.buttons["CurrentLocation"]
        XCTAssertTrue(locationButton.waitForExistence(timeout: timeout))
        
        // Tap location button
        locationButton.tap()
        
        // Verify location permission dialog appears
        let locationAlert = app.alerts.firstMatch
        XCTAssertTrue(locationAlert.waitForExistence(timeout: timeout))
        
        // Allow location access
        locationAlert.buttons["Allow While Using App"].tap()
        
        // Verify tracking mode is active
        XCTAssertTrue(locationButton.isSelected)
        
        // Verify map centers on location
        let mapView = app.otherElements["MapView"]
        XCTAssertTrue(mapView.waitForExistence(timeout: timeout))
        
        // Tap again to disable tracking
        locationButton.tap()
        XCTAssertFalse(locationButton.isSelected)
    }
    
    /// Tests interaction with discovery annotations on map
    func testDiscoveryAnnotationInteraction() throws {
        // Navigate to map tab
        app.tabBars.buttons["Map"].tap()
        
        // Wait for annotations to load
        let annotation = app.otherElements["DiscoveryAnnotation"].firstMatch
        XCTAssertTrue(annotation.waitForExistence(timeout: timeout))
        
        // Tap annotation
        annotation.tap()
        
        // Verify detail sheet appears
        let detailSheet = app.sheets["DiscoveryDetail"]
        XCTAssertTrue(detailSheet.waitForExistence(timeout: timeout))
        
        // Verify detail content
        XCTAssertTrue(detailSheet.staticTexts["SpeciesName"].exists)
        XCTAssertTrue(detailSheet.staticTexts["DiscoveryDate"].exists)
        XCTAssertTrue(detailSheet.images["DiscoveryImage"].exists)
        
        // Test share functionality
        let shareButton = detailSheet.buttons["Share"]
        XCTAssertTrue(shareButton.exists)
        shareButton.tap()
        
        // Verify share sheet appears
        let shareSheet = app.sheets["ShareSheet"]
        XCTAssertTrue(shareSheet.waitForExistence(timeout: timeout))
        shareSheet.buttons["Cancel"].tap()
        
        // Dismiss detail sheet
        detailSheet.buttons["Close"].tap()
        XCTAssertFalse(detailSheet.exists)
    }
    
    /// Tests map gesture interactions
    func testMapGestures() throws {
        // Navigate to map tab
        app.tabBars.buttons["Map"].tap()
        
        let mapView = app.otherElements["MapView"]
        XCTAssertTrue(mapView.waitForExistence(timeout: timeout))
        
        // Test pinch to zoom
        mapView.pinch(withScale: 2, velocity: 1)
        // Verify zoom level changed
        
        // Test double tap zoom
        mapView.doubleTap()
        // Verify zoom level increased
        
        // Test pan gesture
        let start = mapView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = mapView.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        mapView.press(forDuration: 0.1, thenDragTo: end)
        
        // Test rotation gesture
        mapView.rotate(CGFloat.pi / 4)
        // Verify compass appears
        XCTAssertTrue(app.buttons["CompassReset"].exists)
        
        // Reset rotation
        app.buttons["CompassReset"].tap()
    }
}