/*
 * Main Application Class: WildlifeSafariApplication
 * Version: 1.0
 *
 * Dependencies:
 * - android.app.Application:latest
 * - dagger.hilt.android.HiltAndroidApp:2.48
 * - timber.log.Timber:5.0.1
 */

package com.wildlifesafari.app

import android.app.Application
import android.os.StrictMode
import android.util.Log
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.ProcessLifecycleOwner
import com.wildlifesafari.app.data.database.AppDatabase
import com.wildlifesafari.app.di.AppModule
import com.wildlifesafari.app.utils.Constants
import dagger.hilt.android.HiltAndroidApp
import timber.log.Timber
import java.util.concurrent.Executors
import javax.inject.Inject

/**
 * Main application class for the Wildlife Detection Safari Pokédex Android application.
 * Initializes core components, dependency injection, and application-wide configurations.
 *
 * Features:
 * - LNN-powered real-time species identification
 * - Offline-first architecture with local database
 * - Comprehensive error handling and monitoring
 * - Memory and performance optimization
 */
@HiltAndroidApp
class WildlifeSafariApplication : Application(), DefaultLifecycleObserver {

    @Inject
    lateinit var appDatabase: AppDatabase

    companion object {
        private const val TAG = "WildlifeSafariApp"
        private const val MAX_MEMORY_THRESHOLD = 512L * 1024L * 1024L // 512MB
        private const val ML_THREAD_POOL_SIZE = 4
        private const val DB_CACHE_SIZE_MB = 64
    }

    override fun onCreate() {
        super.onCreate()
        
        // Initialize logging
        if (BuildConfig.DEBUG) {
            Timber.plant(Timber.DebugTree())
        } else {
            Timber.plant(CrashReportingTree())
        }

        try {
            // Initialize core components
            initializeComponents()
            
            // Setup lifecycle monitoring
            ProcessLifecycleOwner.get().lifecycle.addObserver(this)
            
            // Configure strict mode for development
            if (BuildConfig.DEBUG) {
                setupStrictMode()
            }

            // Setup global error handling
            setupGlobalExceptionHandler()

            // Initialize ML components
            initializeMLComponents()

            // Monitor memory usage
            startMemoryMonitoring()

            Timber.i("Application initialized successfully")
        } catch (e: Exception) {
            Timber.e(e, "Failed to initialize application")
            throw RuntimeException("Application initialization failed", e)
        }
    }

    /**
     * Initializes core application components with proper error handling
     */
    private fun initializeComponents() {
        try {
            // Initialize database with proper migration handling
            AppDatabase.getInstance(applicationContext).apply {
                // Configure database cache size
                setMaximumSize(DB_CACHE_SIZE_MB * 1024L * 1024L)
            }

            // Initialize network components
            setupNetworkComponents()

            Timber.d("Core components initialized successfully")
        } catch (e: Exception) {
            Timber.e(e, "Failed to initialize core components")
            throw e
        }
    }

    /**
     * Configures strict mode policies for development debugging
     */
    private fun setupStrictMode() {
        StrictMode.setThreadPolicy(
            StrictMode.ThreadPolicy.Builder()
                .detectDiskReads()
                .detectDiskWrites()
                .detectNetwork()
                .detectCustomSlowCalls()
                .penaltyLog()
                .build()
        )

        StrictMode.setVmPolicy(
            StrictMode.VmPolicy.Builder()
                .detectLeakedSqlLiteObjects()
                .detectLeakedClosableObjects()
                .detectActivityLeaks()
                .detectFileUriExposure()
                .penaltyLog()
                .build()
        )
    }

    /**
     * Sets up global exception handling and crash reporting
     */
    private fun setupGlobalExceptionHandler() {
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            Timber.e(throwable, "Uncaught exception on thread ${thread.name}")
            // Log crash to analytics
            logCrashReport(throwable)
            // Attempt graceful shutdown
            cleanupAndShutdown()
        }
    }

    /**
     * Initializes ML components with optimized configuration
     */
    private fun initializeMLComponents() {
        try {
            // Configure ML thread pool
            val mlExecutor = Executors.newFixedThreadPool(ML_THREAD_POOL_SIZE)

            // Initialize LNN model executor
            AppModule.provideLNNModelExecutor(applicationContext).apply {
                // Configure model parameters based on technical specifications
                configureModel(
                    numThreads = Constants.MLConstants.getOptimalThreadCount(),
                    useHardwareAcceleration = Constants.MLConstants.SUPPORTS_HARDWARE_ACCELERATION,
                    memoryLimitMb = Constants.MLConstants.MODEL_MEMORY_LIMIT_MB
                )
            }

            Timber.d("ML components initialized successfully")
        } catch (e: Exception) {
            Timber.e(e, "Failed to initialize ML components")
            throw e
        }
    }

    /**
     * Monitors application memory usage and handles low memory conditions
     */
    private fun startMemoryMonitoring() {
        val runtime = Runtime.getRuntime()
        val maxMemory = runtime.maxMemory()

        if (maxMemory < MAX_MEMORY_THRESHOLD) {
            Timber.w("Device memory below recommended threshold: ${maxMemory / 1024 / 1024}MB")
        }

        // Register low memory callback
        registerComponentCallbacks(object : android.content.ComponentCallbacks2 {
            override fun onTrimMemory(level: Int) {
                when (level) {
                    android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL,
                    android.content.ComponentCallbacks2.TRIM_MEMORY_COMPLETE -> {
                        Timber.w("Critical memory condition detected, trimming caches")
                        trimMemoryCaches()
                    }
                }
            }

            override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {}
            override fun onLowMemory() {
                Timber.w("Low memory condition detected")
                trimMemoryCaches()
            }
        })
    }

    /**
     * Trims memory caches to free up resources
     */
    private fun trimMemoryCaches() {
        try {
            // Clear image caches
            imageCache.trimToSize(Constants.CacheConstants.CACHE_TRIM_TARGET_BYTES)
            
            // Trim database cache
            appDatabase.clearAllTables()
            
            // Request garbage collection
            System.gc()
        } catch (e: Exception) {
            Timber.e(e, "Error trimming memory caches")
        }
    }

    /**
     * Custom crash reporting tree for production logging
     */
    private class CrashReportingTree : Timber.Tree() {
        override fun log(priority: Int, tag: String?, message: String, t: Throwable?) {
            if (priority == Log.ERROR || priority == Log.WARN) {
                // Send to crash reporting service
                t?.let { throwable ->
                    logCrashReport(throwable)
                }
            }
        }
    }

    /**
     * Logs crash reports to analytics service
     */
    private fun logCrashReport(throwable: Throwable) {
        // TODO: Implement crash reporting integration
        Timber.e(throwable, "Crash detected")
    }

    /**
     * Performs cleanup and graceful shutdown
     */
    private fun cleanupAndShutdown() {
        try {
            // Close database connections
            appDatabase.close()
            
            // Cleanup ML resources
            cleanupMLResources()
            
            // Clear caches
            trimMemoryCaches()
        } catch (e: Exception) {
            Timber.e(e, "Error during cleanup")
        } finally {
            // Force exit
            android.os.Process.killProcess(android.os.Process.myPid())
        }
    }
}