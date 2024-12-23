//
// CameraUITests.swift
// WildlifeSafari
//
// Comprehensive UI test suite for validating camera functionality,
// species detection performance, and accessibility compliance.
//

import XCTest // Latest - UI testing framework

// MARK: - Constants

private enum Constants {
    static let TIMEOUT_DURATION: TimeInterval = 10.0
    static let ANIMATION_DURATION: TimeInterval = 1.0
    static let PERFORMANCE_THRESHOLD_MS: Double = 100.0
    static let ACCURACY_THRESHOLD: Double = 0.90
    static let THERMAL_CHECK_INTERVAL: TimeInterval = 1.0
}

class CameraUITests: XCTestCase {
    
    // MARK: - Properties
    
    private var app: XCUIApplication!
    private var processInfo: ProcessInfo!
    private var currentDevice: XCUIDevice!
    
    // MARK: - Setup
    
    override func setUp() {
        super.setUp()
        
        // Initialize application
        app = XCUIApplication()
        processInfo = ProcessInfo.processInfo
        currentDevice = XCUIDevice.shared
        
        // Configure test settings
        app.launchArguments = ["UI-Testing"]
        app.launchEnvironment = [
            "TESTING_MODE": "1",
            "DISABLE_ANIMATIONS": "1"
        ]
        
        // Set up performance metrics monitoring
        continueAfterFailure = false
        
        // Launch application
        app.launch()
    }
    
    // MARK: - Camera Permission Tests
    
    func testCameraPermissions() throws {
        // Navigate to camera view
        let cameraButton = app.buttons["Camera"]
        XCTAssertTrue(cameraButton.waitForExistence(timeout: Constants.TIMEOUT_DURATION))
        cameraButton.tap()
        
        // Verify permission dialog
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alertAllowButton = springboard.buttons["Allow"]
        
        if alertAllowButton.exists {
            alertAllowButton.tap()
            
            // Verify camera access granted
            let cameraView = app.otherElements["CameraView"]
            XCTAssertTrue(cameraView.waitForExistence(timeout: Constants.TIMEOUT_DURATION))
        }
        
        // Verify camera preview visible
        let cameraPreview = app.otherElements["CameraPreviewView"]
        XCTAssertTrue(cameraPreview.exists)
    }
    
    // MARK: - Thermal State Tests
    
    func testThermalStateHandling() throws {
        // Navigate to camera
        navigateToCamera()
        
        // Monitor initial thermal state
        let initialState = processInfo.thermalState
        XCTAssertNotEqual(initialState, ProcessInfo.ThermalState.critical)
        
        // Verify UI updates for different thermal states
        let thermalStates: [ProcessInfo.ThermalState] = [.nominal, .fair, .serious, .critical]
        
        for state in thermalStates {
            simulateThermalState(state)
            verifyThermalStateUI(state)
        }
        
        // Verify recovery from critical state
        simulateThermalState(.nominal)
        let cameraControls = app.otherElements["CameraControlsView"]
        XCTAssertTrue(cameraControls.isEnabled)
    }
    
    // MARK: - Performance Tests
    
    func testSpeciesDetectionPerformance() throws {
        // Navigate to camera
        navigateToCamera()
        
        // Set up performance metrics
        let measureOptions = XCTMeasureOptions()
        measureOptions.invocationOptions = [.manuallyStart]
        
        measure(metrics: [XCTCPUMetric(), XCTMemoryMetric(), XCTStorageMetric()],
                options: measureOptions) {
            // Perform species detection
            startMeasuring()
            
            let captureButton = app.buttons["Capture Photo"]
            captureButton.tap()
            
            // Verify detection overlay appears
            let detectionOverlay = app.otherElements["DetectionOverlayView"]
            XCTAssertTrue(detectionOverlay.waitForExistence(timeout: Constants.TIMEOUT_DURATION))
            
            stopMeasuring()
            
            // Verify performance thresholds
            let processingTime = app.staticTexts["ProcessingTime"].label
            XCTAssertNotNil(Double(processingTime))
            XCTAssertLessThanOrEqual(Double(processingTime) ?? 0, Constants.PERFORMANCE_THRESHOLD_MS)
        }
    }
    
    // MARK: - Accessibility Tests
    
    func testAccessibilityCompliance() throws {
        // Navigate to camera
        navigateToCamera()
        
        // Verify VoiceOver support
        XCTAssertTrue(app.isAccessibilityElement)
        
        // Test camera controls accessibility
        let controls = [
            "Capture Photo",
            "Flash Mode",
            "Wildlife Mode",
            "Fossil Mode"
        ]
        
        for control in controls {
            let element = app.buttons[control]
            XCTAssertTrue(element.exists)
            XCTAssertNotNil(element.label)
            XCTAssertNotNil(element.hint)
        }
        
        // Test dynamic type support
        let contentSizeCategories: [UIContentSizeCategory] = [
            .accessibilityMedium,
            .accessibilityLarge,
            .accessibilityExtraLarge
        ]
        
        for category in contentSizeCategories {
            setContentSize(category)
            verifyUILayout()
        }
    }
    
    // MARK: - Helper Methods
    
    private func navigateToCamera() {
        let cameraButton = app.buttons["Camera"]
        XCTAssertTrue(cameraButton.waitForExistence(timeout: Constants.TIMEOUT_DURATION))
        cameraButton.tap()
    }
    
    private func simulateThermalState(_ state: ProcessInfo.ThermalState) {
        // Simulate thermal state change
        NotificationCenter.default.post(
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            userInfo: ["ThermalState": state]
        )
        
        // Wait for UI to update
        Thread.sleep(forTimeInterval: Constants.ANIMATION_DURATION)
    }
    
    private func verifyThermalStateUI(_ state: ProcessInfo.ThermalState) {
        let cameraControls = app.otherElements["CameraControlsView"]
        
        switch state {
        case .nominal, .fair:
            XCTAssertTrue(cameraControls.isEnabled)
            
        case .serious:
            XCTAssertTrue(cameraControls.isEnabled)
            XCTAssertTrue(app.staticTexts["ThermalWarning"].exists)
            
        case .critical:
            XCTAssertFalse(cameraControls.isEnabled)
            XCTAssertTrue(app.alerts["ThermalAlert"].exists)
            
        @unknown default:
            XCTFail("Unknown thermal state")
        }
    }
    
    private func setContentSize(_ category: UIContentSizeCategory) {
        // Set content size category for testing
        app.launchEnvironment["UIPreferredContentSizeCategory"] = category.rawValue
        app.terminate()
        app.launch()
        
        // Wait for UI to update
        Thread.sleep(forTimeInterval: Constants.ANIMATION_DURATION)
    }
    
    private func verifyUILayout() {
        // Verify critical UI elements remain accessible
        let criticalElements = [
            "CameraPreviewView",
            "CameraControlsView",
            "DetectionOverlayView"
        ]
        
        for elementId in criticalElements {
            let element = app.otherElements[elementId]
            XCTAssertTrue(element.exists)
            XCTAssertTrue(element.isHittable)
        }
    }
}