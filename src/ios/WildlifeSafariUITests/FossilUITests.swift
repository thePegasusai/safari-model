//
// FossilUITests.swift
// WildlifeSafariUITests
//
// UI test suite for fossil scanning and visualization features
// XCTest version: Latest
//

import XCTest

class FossilUITests: XCTestCase {
    
    // MARK: - Properties
    
    private var app: XCUIApplication!
    private let timeout: TimeInterval = 30
    private let processingTimeout: TimeInterval = 0.1 // 100ms performance requirement
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        
        // Initialize fresh application instance
        app = XCUIApplication()
        
        // Configure test launch arguments and environment
        app.launchArguments.append("--uitesting")
        app.launchEnvironment["UITEST_MODE"] = "1"
        
        // Enable test specific features
        app.launchEnvironment["FOSSIL_SCAN_MOCK"] = "1"
        app.launchEnvironment["USE_TEST_DATA"] = "1"
        
        // Launch the application
        app.launch()
    }
    
    override func tearDown() {
        // Terminate application and cleanup
        app.terminate()
        
        // Reset any test-specific states
        app = nil
        
        super.tearDown()
    }
    
    // MARK: - Test Cases
    
    func testFossilScanningFlow() throws {
        // Navigate to fossil scanning
        let fossilTab = app.tabBars.buttons["Fossil Mode"]
        XCTAssertTrue(fossilTab.waitForExistence(timeout: timeout))
        fossilTab.tap()
        
        // Verify scanning UI elements
        let scanButton = app.buttons["Start Scan"]
        XCTAssertTrue(scanButton.exists)
        
        // Verify instructions
        let instructions = app.staticTexts["Position the fossil within the frame"]
        XCTAssertTrue(instructions.exists)
        
        // Start scanning process
        scanButton.tap()
        
        // Verify camera permission handling
        let cameraPermission = app.alerts["Camera Access Required"].buttons["Allow"]
        if cameraPermission.exists {
            cameraPermission.tap()
        }
        
        // Monitor scanning progress
        let progressIndicator = app.progressIndicators.firstMatch
        XCTAssertTrue(progressIndicator.exists)
        
        // Verify scanning completion within performance requirements
        let start = Date()
        let resultView = app.otherElements["ScanResultView"]
        XCTAssertTrue(resultView.waitForExistence(timeout: processingTimeout))
        let processingTime = Date().timeIntervalSince(start)
        XCTAssertLessThanOrEqual(processingTime, processingTimeout)
        
        // Validate result accuracy
        let fossilNameLabel = resultView.staticTexts["FossilName"]
        XCTAssertTrue(fossilNameLabel.exists)
        XCTAssertFalse(fossilNameLabel.label.isEmpty)
    }
    
    func testFossilVisualization() throws {
        // Navigate to fossil detail view
        try navigateToFossilDetail()
        
        // Verify 3D model loading
        let modelView = app.otherElements["3DModelView"]
        XCTAssertTrue(modelView.waitForExistence(timeout: timeout))
        
        // Test rotation gesture
        let rotationGesture = modelView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        rotationGesture.press(forDuration: 0.1, thenDragTo: modelView.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
        
        // Test zoom gesture
        let zoomGesture = modelView.pinch(withScale: 2.0, velocity: 1.0)
        XCTAssertTrue(zoomGesture)
        
        // Verify model details
        let measurementsView = app.otherElements["MeasurementsView"]
        XCTAssertTrue(measurementsView.exists)
        
        // Test AR view transition
        let arButton = app.buttons["View in AR"]
        XCTAssertTrue(arButton.exists)
        arButton.tap()
        
        // Verify AR view loading
        let arView = app.otherElements["ARView"]
        XCTAssertTrue(arView.waitForExistence(timeout: timeout))
    }
    
    func testScanningCancellation() throws {
        // Start scanning process
        try startScanningProcess()
        
        // Verify cancel button
        let cancelButton = app.buttons["Cancel Scan"]
        XCTAssertTrue(cancelButton.exists)
        
        // Trigger cancellation
        cancelButton.tap()
        
        // Verify cleanup and reset
        let scanButton = app.buttons["Start Scan"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: timeout))
        
        // Verify resource deallocation
        XCTAssertFalse(app.progressIndicators.firstMatch.exists)
        XCTAssertFalse(app.otherElements["ScanningView"].exists)
    }
    
    func testErrorHandling() throws {
        // Test insufficient lighting
        app.launchEnvironment["SIMULATE_LOW_LIGHT"] = "1"
        try startScanningProcess()
        
        let lightingAlert = app.alerts["Insufficient Lighting"]
        XCTAssertTrue(lightingAlert.waitForExistence(timeout: timeout))
        lightingAlert.buttons["OK"].tap()
        
        // Test network error
        app.launchEnvironment["SIMULATE_NETWORK_ERROR"] = "1"
        try startScanningProcess()
        
        let networkAlert = app.alerts["Network Error"]
        XCTAssertTrue(networkAlert.waitForExistence(timeout: timeout))
        let retryButton = networkAlert.buttons["Retry"]
        XCTAssertTrue(retryButton.exists)
        retryButton.tap()
        
        // Test timeout scenario
        app.launchEnvironment["SIMULATE_TIMEOUT"] = "1"
        try startScanningProcess()
        
        let timeoutAlert = app.alerts["Scan Timeout"]
        XCTAssertTrue(timeoutAlert.waitForExistence(timeout: timeout))
        timeoutAlert.buttons["Try Again"].tap()
    }
    
    // MARK: - Helper Methods
    
    private func startScanningProcess() throws {
        let fossilTab = app.tabBars.buttons["Fossil Mode"]
        XCTAssertTrue(fossilTab.waitForExistence(timeout: timeout))
        fossilTab.tap()
        
        let scanButton = app.buttons["Start Scan"]
        XCTAssertTrue(scanButton.exists)
        scanButton.tap()
    }
    
    private func navigateToFossilDetail() throws {
        let fossilTab = app.tabBars.buttons["Fossil Mode"]
        XCTAssertTrue(fossilTab.waitForExistence(timeout: timeout))
        fossilTab.tap()
        
        let fossilList = app.collectionViews["FossilList"]
        XCTAssertTrue(fossilList.waitForExistence(timeout: timeout))
        
        let firstFossil = fossilList.cells.element(boundBy: 0)
        XCTAssertTrue(firstFossil.exists)
        firstFossil.tap()
    }
}