//
// SpeciesUITests.swift
// WildlifeSafariUITests
//
// UI test suite for testing species-related functionality in the Wildlife Detection
// Safari Pokédex iOS application, including species detail view, detection,
// collection integration, and accessibility compliance.
//

import XCTest

class SpeciesUITests: XCTestCase {
    
    // MARK: - Properties
    
    private var app: XCUIApplication!
    private let defaultTimeout: TimeInterval = 30
    private var isOfflineMode = false
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        
        // Initialize app with test configuration
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        app.launchEnvironment = [
            "RESET_DATABASE": "1",
            "MOCK_NETWORK": "1"
        ]
        
        // Configure test timeouts
        continueAfterFailure = false
        
        // Launch app
        app.launch()
    }
    
    override func tearDown() {
        // Clean up test data
        app.terminate()
        super.tearDown()
    }
    
    // MARK: - Test Cases
    
    /// Tests comprehensive species detail view with 3D visualization
    func testSpeciesDetailViewDisplay() throws {
        // Navigate to species detail
        let speciesCell = app.cells["Red-tailed Hawk"]
        XCTAssertTrue(speciesCell.waitForExistence(timeout: defaultTimeout))
        speciesCell.tap()
        
        // Verify species information
        let speciesName = app.staticTexts["Red-tailed Hawk"]
        let scientificName = app.staticTexts["Buteo jamaicensis"]
        let conservationStatus = app.staticTexts["Least Concern"]
        
        XCTAssertTrue(speciesName.exists)
        XCTAssertTrue(scientificName.exists)
        XCTAssertTrue(conservationStatus.exists)
        
        // Test 3D model interaction
        let modelView = app.otherElements["3DModelView"]
        XCTAssertTrue(modelView.exists)
        
        // Test rotation gesture
        modelView.pinch(withScale: 1.5, velocity: 1.0)
        modelView.rotate(CGFloat.pi/2)
        
        // Verify educational content
        let detailsSection = app.collectionViews.cells.containing(.staticText, identifier: "Details")
        XCTAssertTrue(detailsSection.exists)
        
        // Test image gallery
        let gallery = app.scrollViews["SpeciesImageGallery"]
        XCTAssertTrue(gallery.exists)
        gallery.swipeLeft()
        gallery.swipeRight()
        
        // Verify action buttons
        let addToCollectionButton = app.buttons["Add to Collection"]
        let shareButton = app.buttons["Share"]
        
        XCTAssertTrue(addToCollectionButton.exists)
        XCTAssertTrue(shareButton.exists)
    }
    
    /// Tests collection management with offline support
    func testSpeciesCollectionIntegration() throws {
        // Enable offline mode
        isOfflineMode = true
        app.switches["Offline Mode"].tap()
        
        // Add species to collection
        let speciesCell = app.cells["Red-tailed Hawk"]
        XCTAssertTrue(speciesCell.waitForExistence(timeout: defaultTimeout))
        speciesCell.tap()
        
        let addButton = app.buttons["Add to Collection"]
        XCTAssertTrue(addButton.exists)
        addButton.tap()
        
        // Verify offline indicator
        let offlineIndicator = app.images["OfflineIndicator"]
        XCTAssertTrue(offlineIndicator.exists)
        
        // Test collection sync when back online
        isOfflineMode = false
        app.switches["Offline Mode"].tap()
        
        // Verify sync completion
        let syncIndicator = app.activityIndicators["SyncIndicator"]
        XCTAssertTrue(syncIndicator.waitForExistence(timeout: defaultTimeout))
        XCTAssertFalse(syncIndicator.exists)
        
        // Verify species in collection
        let collectionsTab = app.tabBars.buttons["Collections"]
        collectionsTab.tap()
        
        let collectionCell = app.cells.containing(.staticText, identifier: "Red-tailed Hawk")
        XCTAssertTrue(collectionCell.exists)
    }
    
    /// Tests comprehensive accessibility compliance
    func testSpeciesAccessibility() throws {
        // Enable VoiceOver
        let voiceOverEnabled = UIAccessibility.isVoiceOverRunning
        if !voiceOverEnabled {
            XCUIDevice.shared.press(.home, forDuration: 3)
        }
        
        // Test dynamic type scaling
        let settings = app.buttons["Settings"]
        settings.tap()
        
        let textSize = app.sliders["Text Size"]
        textSize.adjust(toNormalizedSliderPosition: 0.8)
        
        // Verify accessibility labels
        let speciesCell = app.cells["Red-tailed Hawk"]
        XCTAssertTrue(speciesCell.waitForExistence(timeout: defaultTimeout))
        XCTAssertEqual(speciesCell.label, "Red-tailed Hawk, Common Bird Species")
        
        speciesCell.tap()
        
        // Test keyboard navigation
        let nextButton = app.buttons["Next"]
        let previousButton = app.buttons["Previous"]
        
        XCTAssertTrue(nextButton.exists)
        XCTAssertTrue(previousButton.exists)
        
        // Verify heading structure
        let headings = app.staticTexts.matching(identifier: "Heading")
        XCTAssertGreaterThan(headings.count, 0)
        
        // Test focus order
        let elements = app.descendants(matching: .any)
        var previousElement: XCUIElement?
        
        elements.allElementsBoundByIndex.forEach { element in
            if let previous = previousElement {
                XCTAssertGreaterThan(element.frame.minY, previous.frame.minY)
            }
            previousElement = element
        }
        
        // Disable VoiceOver if it was enabled for testing
        if !voiceOverEnabled {
            XCUIDevice.shared.press(.home, forDuration: 3)
        }
    }
}