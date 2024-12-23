/*
 * Instrumented Test Class: ExampleInstrumentedTest
 * Version: 1.0
 *
 * Dependencies:
 * - org.junit:junit:4.13.2
 * - androidx.test:runner:1.4.0
 * - androidx.test.platform:app:1.1.0
 */

package com.wildlifesafari.app

import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Before
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import timber.log.Timber

/**
 * Instrumented test class that validates core application functionality,
 * context initialization, and package configuration for the Wildlife Detection
 * Safari Pokédex application.
 *
 * Test coverage includes:
 * - Application context initialization
 * - Package name verification
 * - Application class type validation
 * - System service accessibility
 * - Basic configuration validation
 */
@RunWith(AndroidJUnit4::class)
class ExampleInstrumentedTest {

    private lateinit var appContext: WildlifeSafariApplication

    /**
     * Sets up the test environment before each test case.
     * Initializes application context and validates basic prerequisites.
     */
    @Before
    fun setup() {
        // Get application context
        appContext = InstrumentationRegistry.getInstrumentation()
            .targetContext.applicationContext as WildlifeSafariApplication

        // Verify context is properly initialized
        assertNotNull("Application context should not be null", appContext)
    }

    /**
     * Cleans up resources after each test case.
     */
    @After
    fun tearDown() {
        // Clean up any test-specific resources if needed
    }

    /**
     * Validates application context initialization and package configuration.
     * Verifies that the context is properly initialized and matches expected package.
     */
    @Test
    fun useAppContext() {
        // Verify package name
        assertEquals(
            "Package name should match expected value",
            "com.wildlifesafari.app",
            appContext.packageName
        )

        // Verify application class type
        assertTrue(
            "Context should be instance of WildlifeSafariApplication",
            appContext is WildlifeSafariApplication
        )
    }

    /**
     * Validates essential system services accessibility.
     * Ensures that required system services are available and properly configured.
     */
    @Test
    fun validateSystemServices() {
        // Test location service availability
        val locationManager = appContext.getSystemService(WildlifeSafariApplication.LOCATION_SERVICE)
        assertNotNull("Location service should be available", locationManager)

        // Test camera service availability
        val cameraManager = appContext.getSystemService(WildlifeSafariApplication.CAMERA_SERVICE)
        assertNotNull("Camera service should be available", cameraManager)

        // Test connectivity service availability
        val connectivityManager = 
            appContext.getSystemService(WildlifeSafariApplication.CONNECTIVITY_SERVICE)
        assertNotNull("Connectivity service should be available", connectivityManager)
    }

    /**
     * Validates application memory requirements.
     * Ensures that the device meets minimum memory requirements for ML operations.
     */
    @Test
    fun validateMemoryRequirements() {
        val runtime = Runtime.getRuntime()
        val maxMemory = runtime.maxMemory() / (1024 * 1024) // Convert to MB

        assertTrue(
            "Device should meet minimum memory requirements",
            maxMemory >= Constants.DEVICE_MIN_MEMORY_MB
        )
    }

    /**
     * Validates database initialization.
     * Ensures that the application database is properly initialized.
     */
    @Test
    fun validateDatabaseInitialization() {
        val db = appContext.appDatabase
        assertNotNull("Database should be initialized", db)

        // Verify database version
        assertEquals(
            "Database version should match expected value",
            Constants.DATABASE_VERSION,
            db.openHelper.readableDatabase.version
        )
    }

    /**
     * Validates ML model configuration.
     * Ensures that ML-related configurations are properly set.
     */
    @Test
    fun validateMLConfiguration() {
        assertTrue(
            "ML thread count should be within valid range",
            Constants.MLConstants.getOptimalThreadCount() in 1..Runtime.getRuntime().availableProcessors()
        )

        assertTrue(
            "ML model memory limit should be reasonable",
            Constants.MLConstants.MODEL_MEMORY_LIMIT_MB > 0 &&
            Constants.MLConstants.MODEL_MEMORY_LIMIT_MB <= Constants.DEVICE_RECOMMENDED_MEMORY_MB / 2
        )
    }

    /**
     * Validates network configuration.
     * Ensures that network-related settings are properly configured.
     */
    @Test
    fun validateNetworkConfiguration() {
        assertTrue(
            "Network timeout values should be reasonable",
            Constants.NetworkConstants.CONNECT_TIMEOUT_SECONDS in 1..60 &&
            Constants.NetworkConstants.READ_TIMEOUT_SECONDS in 1..60 &&
            Constants.NetworkConstants.WRITE_TIMEOUT_SECONDS in 1..60
        )

        assertTrue(
            "Retry configuration should be reasonable",
            Constants.NetworkConstants.MAX_RETRIES in 1..5 &&
            Constants.NetworkConstants.RETRY_DELAY_MS > 0
        )
    }

    /**
     * Validates cache configuration.
     * Ensures that cache-related settings are properly configured.
     */
    @Test
    fun validateCacheConfiguration() {
        assertTrue(
            "Cache size should be within reasonable limits",
            Constants.CacheConstants.MAX_MEMORY_CACHE_SIZE_BYTES > 0 &&
            Constants.CacheConstants.MAX_MEMORY_CACHE_SIZE_BYTES <= 
                Runtime.getRuntime().maxMemory() / 4
        )

        assertTrue(
            "Cache trim thresholds should be properly configured",
            Constants.CacheConstants.CACHE_TRIM_TARGET_BYTES < 
                Constants.CacheConstants.CACHE_TRIM_THRESHOLD_BYTES
        )
    }
}