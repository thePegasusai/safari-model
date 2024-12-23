/*
 * Dagger Hilt Module: AppModule
 * Version: 1.0
 *
 * Dependencies:
 * - dagger.hilt:hilt-android:2.48
 * - kotlinx.coroutines:kotlinx-coroutines-core:1.7.3
 */

package com.wildlifesafari.app.di

import android.content.Context
import com.wildlifesafari.app.data.ml.LNNModelExecutor
import com.wildlifesafari.app.utils.Constants.MLConstants
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import javax.inject.Singleton

/**
 * Main Dagger Hilt module providing application-wide dependencies with comprehensive
 * resource management and error handling.
 *
 * Features:
 * - LNN model executor configuration for species detection
 * - Coroutine scope management for async operations
 * - Memory-optimized resource allocation
 * - Error isolation through SupervisorJob
 */
@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    /**
     * Provides singleton instance of LNN model executor optimized for species detection.
     * Configures the model with:
     * - 1024 neuron layer size for LNN
     * - 10-100ms time constants for neural dynamics
     * - INT8 quantization for mobile optimization
     * - Optimal thread count based on device capabilities
     *
     * @param context Application context for resource access
     * @return Singleton LNNModelExecutor instance
     */
    @Provides
    @Singleton
    fun provideLNNModelExecutor(
        @ApplicationContext context: Context
    ): LNNModelExecutor {
        return LNNModelExecutor(
            context = context,
            modelPath = MLConstants.ML_MODEL_FILE_NAME
        ).apply {
            // Configure model parameters based on technical specifications
            configureModel(
                numThreads = MLConstants.getOptimalThreadCount(),
                useHardwareAcceleration = MLConstants.SUPPORTS_HARDWARE_ACCELERATION,
                memoryLimitMb = MLConstants.MODEL_MEMORY_LIMIT_MB
            )
        }
    }

    /**
     * Provides application-scoped coroutine scope for structured concurrency.
     * Uses SupervisorJob for error isolation and Dispatchers.Default for CPU-intensive work.
     *
     * Features:
     * - Error isolation through SupervisorJob
     * - Cancellation propagation control
     * - Resource cleanup on scope cancellation
     *
     * @return Application-scoped CoroutineScope
     */
    @Provides
    @Singleton
    fun provideCoroutineScope(): CoroutineScope {
        return CoroutineScope(SupervisorJob() + Dispatchers.Default)
    }

    /**
     * Provides database transaction manager for offline-first operations.
     * Ensures data consistency and proper resource management.
     *
     * @return DatabaseTransactionManager instance
     */
    @Provides
    @Singleton
    fun provideDatabaseTransactionManager(): DatabaseTransactionManager {
        return DatabaseModule.provideDatabaseTransactionManager()
    }

    /**
     * Provides offline sync manager for background synchronization.
     * Handles data synchronization with cloud when network is available.
     *
     * @return OfflineSyncManager instance
     */
    @Provides
    @Singleton
    fun provideOfflineSyncManager(): OfflineSyncManager {
        return NetworkModule.provideOfflineSyncManager()
    }
}

/**
 * Interface for database transaction management
 */
interface DatabaseTransactionManager {
    suspend fun <T> withTransaction(block: suspend () -> T): T
}

/**
 * Interface for offline sync management
 */
interface OfflineSyncManager {
    suspend fun syncPendingData()
    suspend fun scheduleSync()
    fun isNetworkAvailable(): Boolean
}