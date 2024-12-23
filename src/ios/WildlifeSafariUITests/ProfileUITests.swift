//
// ProfileUITests.swift
// WildlifeSafari
//
// UI test suite for comprehensive testing of the Profile interface functionality,
// accessibility, and error handling in the Wildlife Safari iOS application.
//

import XCTest

class ProfileUITests: XCTestCase {
    
    // MARK: - Properties
    
    private var app: XCUIApplication!
    private let defaultTimeout: TimeInterval = 10.0
    private var isNetworkAvailable = true
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        
        // Initialize application
        app = XCUIApplication()
        
        // Configure test environment
        app.launchArguments = ["UI-Testing"]
        app.launchEnvironment = [
            "NETWORK_AVAILABLE": String(isNetworkAvailable),
            "RESET_USER_DATA": "true"
        ]
        
        // Enable accessibility testing
        app.launchEnvironment["ENABLE_ACCESSIBILITY_CHECKS"] = "true"
        
        // Continue on failure to collect more test data
        continueAfterFailure = false
        
        // Launch app
        app.launch()
    }
    
    override func tearDown() {
        // Reset app state
        app.terminate()
        super.tearDown()
    }
    
    // MARK: - Test Cases
    
    func testProfileViewDisplay() throws {
        // Navigate to profile tab
        let profileTab = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: defaultTimeout))
        profileTab.tap()
        
        // Verify profile header
        let profileHeader = app.staticTexts["Profile"]
        XCTAssertTrue(profileHeader.exists)
        XCTAssertTrue(profileHeader.isHittable)
        
        // Verify user information section
        let userNameLabel = app.staticTexts.matching(identifier: "UserNameLabel").firstMatch
        XCTAssertTrue(userNameLabel.exists)
        
        // Verify statistics section
        let statisticsSection = app.otherElements["StatisticsSection"]
        XCTAssertTrue(statisticsSection.exists)
        
        // Verify settings button
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.exists)
        XCTAssertTrue(settingsButton.isEnabled)
        
        // Test accessibility
        XCTAssertTrue(profileHeader.isAccessibilityElement)
        XCTAssertTrue(statisticsSection.isAccessibilityElement)
        XCTAssertNotNil(settingsButton.accessibilityLabel)
        XCTAssertNotNil(settingsButton.accessibilityHint)
    }
    
    func testStatisticsNavigation() throws {
        // Navigate to profile
        app.tabBars.buttons["Profile"].tap()
        
        // Tap statistics section
        let statisticsSection = app.otherElements["StatisticsSection"]
        XCTAssertTrue(statisticsSection.waitForExistence(timeout: defaultTimeout))
        statisticsSection.tap()
        
        // Verify statistics detail view
        let statisticsTitle = app.staticTexts["Statistics"]
        XCTAssertTrue(statisticsTitle.waitForExistence(timeout: defaultTimeout))
        
        // Verify statistics content
        let discoveryCount = app.staticTexts["TotalDiscoveriesLabel"]
        XCTAssertTrue(discoveryCount.exists)
        
        let speciesCount = app.staticTexts["UniqueSpeciesLabel"]
        XCTAssertTrue(speciesCount.exists)
        
        // Test back navigation
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        backButton.tap()
        
        // Verify return to profile
        XCTAssertTrue(app.staticTexts["Profile"].exists)
    }
    
    func testSettingsNavigation() throws {
        // Navigate to profile
        app.tabBars.buttons["Profile"].tap()
        
        // Tap settings button
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: defaultTimeout))
        settingsButton.tap()
        
        // Verify settings view
        let settingsTitle = app.staticTexts["Settings"]
        XCTAssertTrue(settingsTitle.waitForExistence(timeout: defaultTimeout))
        
        // Verify settings options
        let accountSection = app.tables.cells["AccountSettings"]
        XCTAssertTrue(accountSection.exists)
        
        let notificationsToggle = app.switches["NotificationsToggle"]
        XCTAssertTrue(notificationsToggle.exists)
        
        let privacyButton = app.buttons["PrivacySettings"]
        XCTAssertTrue(privacyButton.exists)
        
        // Test back navigation
        app.navigationBars.buttons.element(boundBy: 0).tap()
        
        // Verify return to profile
        XCTAssertTrue(app.staticTexts["Profile"].exists)
    }
    
    func testProfileRefresh() throws {
        // Navigate to profile
        app.tabBars.buttons["Profile"].tap()
        
        // Record initial statistics
        let initialDiscoveries = app.staticTexts["TotalDiscoveriesLabel"].label
        
        // Perform pull-to-refresh
        let profileView = app.scrollViews.firstMatch
        profileView.swipeDown()
        
        // Verify refresh indicator
        let refreshControl = app.activityIndicators["RefreshControl"]
        XCTAssertTrue(refreshControl.exists)
        
        // Wait for refresh to complete
        let updatedDiscoveries = app.staticTexts["TotalDiscoveriesLabel"]
        XCTAssertTrue(updatedDiscoveries.waitForExistence(timeout: defaultTimeout))
        
        // Verify content updated
        XCTAssertNotEqual(initialDiscoveries, updatedDiscoveries.label)
    }
    
    func testErrorHandling() throws {
        // Simulate network error
        isNetworkAvailable = false
        app.terminate()
        app.launch()
        
        // Navigate to profile
        app.tabBars.buttons["Profile"].tap()
        
        // Attempt refresh
        app.scrollViews.firstMatch.swipeDown()
        
        // Verify error alert
        let errorAlert = app.alerts["Error"]
        XCTAssertTrue(errorAlert.waitForExistence(timeout: defaultTimeout))
        
        // Verify error message
        let errorMessage = app.alerts.staticTexts["NetworkErrorMessage"]
        XCTAssertTrue(errorMessage.exists)
        
        // Verify retry button
        let retryButton = errorAlert.buttons["Retry"]
        XCTAssertTrue(retryButton.exists)
        
        // Test retry functionality
        isNetworkAvailable = true
        retryButton.tap()
        
        // Verify error dismissed
        XCTAssertFalse(errorAlert.exists)
        
        // Verify content loaded
        let statisticsSection = app.otherElements["StatisticsSection"]
        XCTAssertTrue(statisticsSection.waitForExistence(timeout: defaultTimeout))
    }
}