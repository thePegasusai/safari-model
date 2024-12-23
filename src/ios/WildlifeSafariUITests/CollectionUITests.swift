//
// CollectionUITests.swift
// WildlifeSafariUITests
//
// UI test suite for testing the Collection management functionality in the
// Wildlife Detection Safari Pokédex iOS application.
//

import XCTest
@testable import WildlifeSafari

final class CollectionUITests: XCTestCase {
    
    // MARK: - Properties
    
    private var app: XCUIApplication!
    private let timeout: TimeInterval = 10.0
    private var isOfflineMode = false
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        
        // Initialize application
        app = XCUIApplication()
        
        // Configure test environment
        app.launchArguments = ["UI-TESTING"]
        app.launchEnvironment = [
            "RESET_DATABASE": "true",
            "MOCK_NETWORK": "true"
        ]
        
        // Enable accessibility
        app.launchEnvironment["ENABLE_ACCESSIBILITY"] = "true"
        
        // Prepare for UI testing
        continueAfterFailure = false
        
        // Launch application
        app.launch()
    }
    
    override func tearDown() {
        // Reset test environment
        isOfflineMode = false
        
        // Clear test data
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "CollectionViewMode")
        
        app.terminate()
        super.tearDown()
    }
    
    // MARK: - Test Cases
    
    /// Tests the display and layout of collection view elements
    func testCollectionViewDisplays() throws {
        // Navigate to collections tab
        let collectionsTab = app.tabBars.buttons["Collections"]
        XCTAssertTrue(collectionsTab.waitForExistence(timeout: timeout))
        collectionsTab.tap()
        
        // Verify view mode toggle exists
        let gridButton = app.buttons["Grid"]
        let listButton = app.buttons["List"]
        XCTAssertTrue(gridButton.exists)
        XCTAssertTrue(listButton.exists)
        
        // Verify sort button exists
        let sortButton = app.buttons["Sort"]
        XCTAssertTrue(sortButton.exists)
        
        // Verify add collection button exists
        let addButton = app.buttons["Add Collection"]
        XCTAssertTrue(addButton.exists)
        
        // Test view mode switching
        gridButton.tap()
        XCTAssertTrue(app.collectionViews["CollectionGridView"].exists)
        
        listButton.tap()
        XCTAssertTrue(app.tables["CollectionListView"].exists)
    }
    
    /// Tests collection functionality in offline mode
    func testOfflineCapabilities() throws {
        // Enable offline mode
        isOfflineMode = true
        app.launchEnvironment["OFFLINE_MODE"] = "true"
        app.terminate()
        app.launch()
        
        // Navigate to collections
        app.tabBars.buttons["Collections"].tap()
        
        // Verify offline indicator is visible
        let offlineBanner = app.staticTexts["Offline Mode"]
        XCTAssertTrue(offlineBanner.exists)
        
        // Create collection in offline mode
        let addButton = app.buttons["Add Collection"]
        addButton.tap()
        
        let collectionNameField = app.textFields["Collection Name"]
        collectionNameField.tap()
        collectionNameField.typeText("Offline Collection")
        
        app.buttons["Create"].tap()
        
        // Verify collection was created locally
        let collectionCell = app.cells["Offline Collection"]
        XCTAssertTrue(collectionCell.waitForExistence(timeout: timeout))
        
        // Verify sync pending indicator
        let syncIndicator = collectionCell.images["cloud.slash"]
        XCTAssertTrue(syncIndicator.exists)
    }
    
    /// Tests accessibility features for collection views
    func testAccessibilityFeatures() throws {
        // Navigate to collections
        app.tabBars.buttons["Collections"].tap()
        
        // Test VoiceOver labels
        let addButton = app.buttons["Add Collection"]
        XCTAssertEqual(addButton.label, "Add Collection")
        
        // Test dynamic type
        let largeTextSize = UIContentSizeCategory.accessibilityLarge
        app.launchEnvironment["UI_TESTING_CONTENT_SIZE_CATEGORY"] = String(describing: largeTextSize)
        app.terminate()
        app.launch()
        
        // Verify text scales appropriately
        let collectionTitle = app.staticTexts["Collections"]
        XCTAssertTrue(collectionTitle.exists)
        
        // Test keyboard navigation
        addButton.tap()
        let nameField = app.textFields["Collection Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout))
        
        // Verify focus moves correctly
        XCTAssertTrue(nameField.hasKeyboardFocus)
    }
    
    /// Tests collection creation and management
    func testCollectionManagement() throws {
        // Navigate to collections
        app.tabBars.buttons["Collections"].tap()
        
        // Create new collection
        app.buttons["Add Collection"].tap()
        
        let nameField = app.textFields["Collection Name"]
        nameField.tap()
        nameField.typeText("Test Collection")
        
        app.buttons["Create"].tap()
        
        // Verify collection was created
        let collectionCell = app.cells["Test Collection"]
        XCTAssertTrue(collectionCell.waitForExistence(timeout: timeout))
        
        // Test collection deletion
        collectionCell.swipeLeft()
        app.buttons["Delete"].tap()
        
        // Confirm deletion
        app.alerts["Delete Collection"].buttons["Delete"].tap()
        
        // Verify collection was deleted
        XCTAssertFalse(collectionCell.exists)
    }
    
    /// Tests collection sorting and filtering
    func testCollectionSortingAndFiltering() throws {
        // Navigate to collections
        app.tabBars.buttons["Collections"].tap()
        
        // Create test collections
        createTestCollection(name: "Zebra Collection")
        createTestCollection(name: "Antelope Collection")
        
        // Test sorting
        app.buttons["Sort"].tap()
        app.buttons["Name (A-Z)"].tap()
        
        let cells = app.cells.allElementsBoundByIndex
        XCTAssertEqual(cells[0].label, "Antelope Collection")
        XCTAssertEqual(cells[1].label, "Zebra Collection")
        
        // Test search filtering
        let searchField = app.searchFields["Search collections"]
        searchField.tap()
        searchField.typeText("Zebra")
        
        XCTAssertEqual(app.cells.count, 1)
        XCTAssertTrue(app.cells["Zebra Collection"].exists)
    }
    
    // MARK: - Helper Methods
    
    private func createTestCollection(name: String) {
        app.buttons["Add Collection"].tap()
        
        let nameField = app.textFields["Collection Name"]
        nameField.tap()
        nameField.typeText(name)
        
        app.buttons["Create"].tap()
        
        // Wait for collection to be created
        let cell = app.cells[name]
        XCTAssertTrue(cell.waitForExistence(timeout: timeout))
    }
}