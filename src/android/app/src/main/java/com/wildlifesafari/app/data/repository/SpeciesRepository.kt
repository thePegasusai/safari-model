/*
 * Repository Implementation: SpeciesRepository
 * Version: 1.0
 *
 * Dependencies:
 * - javax.inject:javax.inject:1
 * - kotlinx.coroutines:kotlinx-coroutines-core:1.7.3
 * - androidx.work:work-runtime-ktx:2.8.1
 * - javax.cache:cache-api:1.1.1
 */

package com.wildlifesafari.app.data.repository

import com.wildlifesafari.app.data.api.ApiService
import com.wildlifesafari.app.data.api.SyncResponse
import com.wildlifesafari.app.data.database.dao.SpeciesDao
import com.wildlifesafari.app.data.database.entities.Species
import com.wildlifesafari.app.domain.models.SpeciesModel
import javax.inject.Inject
import javax.inject.Singleton
import javax.cache.Cache
import androidx.work.WorkManager
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.workDataOf
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MultipartBody
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.TimeUnit
import kotlin.time.Duration.Companion.minutes

/**
 * Repository implementation that coordinates between local database and remote API
 * for species data management with offline-first capabilities.
 */
@Singleton
class SpeciesRepository @Inject constructor(
    private val speciesDao: SpeciesDao,
    private val apiService: ApiService,
    private val workManager: WorkManager,
    private val cache: Cache<String, SpeciesModel>
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val syncQueue = ConcurrentLinkedQueue<SyncOperation>()
    
    companion object {
        private const val CACHE_EXPIRY_MINUTES = 30L
        private const val MAX_RETRY_ATTEMPTS = 3
        private const val SYNC_WORK_TAG = "species_sync_work"
    }

    init {
        setupBackgroundSync()
    }

    /**
     * Retrieves all species from local database with caching support
     * @return Flow of species list with automatic updates
     */
    fun getAllSpecies(): Flow<List<SpeciesModel>> = flow {
        speciesDao.getAll()
            .map { species -> species.map { it.toModel() } }
            .collect { speciesList ->
                // Update cache
                speciesList.forEach { species ->
                    cache.put(species.id, species)
                }
                emit(speciesList)
            }
    }.flowOn(Dispatchers.IO)

    /**
     * Detects species from image data using LNN with offline support
     * @param imageData Raw image bytes
     * @param latitude Location latitude
     * @param longitude Location longitude
     * @return Detected species information
     */
    suspend fun detectSpecies(
        imageData: ByteArray,
        latitude: Double,
        longitude: Double
    ): SpeciesModel = withContext(Dispatchers.IO) {
        try {
            // Create multipart request
            val imagePart = MultipartBody.Part.createFormData(
                "image",
                "detection.jpg",
                okhttp3.RequestBody.create(
                    okhttp3.MediaType.parse("image/*"),
                    imageData
                )
            )

            // Attempt API call with retry
            val detectedSpecies = withRetry(MAX_RETRY_ATTEMPTS) {
                apiService.detectSpecies(
                    image = imagePart,
                    latitude = latitude,
                    longitude = longitude
                ).blockingGet()
            }

            // Save to local database
            speciesDao.insert(Species.fromModel(detectedSpecies))
            
            // Update cache
            cache.put(detectedSpecies.id, detectedSpecies)
            
            // Schedule sync
            enqueueSyncOperation(SyncOperation.Insert(detectedSpecies))
            
            detectedSpecies
        } catch (e: Exception) {
            // Handle offline scenario
            handleOfflineDetection(imageData, latitude, longitude)
        }
    }

    /**
     * Synchronizes local changes with remote server
     * @return Success status of sync operation
     */
    private suspend fun syncWithRemote(): Boolean = withContext(Dispatchers.IO) {
        try {
            val unsyncedOperations = syncQueue.toList()
            if (unsyncedOperations.isEmpty()) return@withContext true

            val response = apiService.syncCollections(
                unsyncedOperations.map { it.species }
            ).blockingGet()

            handleSyncResponse(response, unsyncedOperations)
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Sets up background synchronization worker
     */
    private fun setupBackgroundSync() {
        val syncWorkRequest = OneTimeWorkRequestBuilder<SpeciesSyncWorker>()
            .addTag(SYNC_WORK_TAG)
            .setConstraints(
                androidx.work.Constraints.Builder()
                    .setRequiredNetworkType(androidx.work.NetworkType.CONNECTED)
                    .build()
            )
            .setBackoffCriteria(
                androidx.work.BackoffPolicy.EXPONENTIAL,
                15,
                TimeUnit.MINUTES
            )
            .build()

        workManager.enqueueUniqueWork(
            SYNC_WORK_TAG,
            androidx.work.ExistingWorkPolicy.REPLACE,
            syncWorkRequest
        )
    }

    /**
     * Handles offline species detection when network is unavailable
     */
    private suspend fun handleOfflineDetection(
        imageData: ByteArray,
        latitude: Double,
        longitude: Double
    ): SpeciesModel {
        // Store detection request for later processing
        val pendingDetection = PendingDetection(
            imageData = imageData,
            latitude = latitude,
            longitude = longitude,
            timestamp = System.currentTimeMillis()
        )
        
        storePendingDetection(pendingDetection)
        
        throw OfflineDetectionPendingException(
            "Detection queued for processing when network is available"
        )
    }

    /**
     * Stores pending detection for later processing
     */
    private suspend fun storePendingDetection(pendingDetection: PendingDetection) {
        // Implementation for storing pending detection
        // This could use Room database or file storage
    }

    /**
     * Handles sync response and updates local state
     */
    private suspend fun handleSyncResponse(
        response: SyncResponse,
        operations: List<SyncOperation>
    ) {
        response.syncedItems.let { syncedCount ->
            operations.take(syncedCount).forEach { operation ->
                syncQueue.remove(operation)
            }
        }

        // Handle failed items
        response.failedItems.forEach { failedId ->
            val failedOperation = operations.find { it.species.id == failedId }
            failedOperation?.let { operation ->
                if (operation.retryCount < MAX_RETRY_ATTEMPTS) {
                    operation.retryCount++
                    syncQueue.offer(operation)
                }
            }
        }
    }

    /**
     * Retries an operation with exponential backoff
     */
    private suspend fun <T> withRetry(
        maxAttempts: Int,
        block: suspend () -> T
    ): T {
        var lastException: Exception? = null
        repeat(maxAttempts) { attempt ->
            try {
                return block()
            } catch (e: Exception) {
                lastException = e
                if (attempt < maxAttempts - 1) {
                    delay((2.0.pow(attempt) * 1000).toLong())
                }
            }
        }
        throw lastException ?: RuntimeException("Operation failed after $maxAttempts attempts")
    }
}

/**
 * Data class representing a sync operation
 */
private data class SyncOperation(
    val species: SpeciesModel,
    val type: OperationType,
    var retryCount: Int = 0
) {
    enum class OperationType {
        Insert, Update, Delete
    }

    companion object {
        fun Insert(species: SpeciesModel) = SyncOperation(species, OperationType.Insert)
        fun Update(species: SpeciesModel) = SyncOperation(species, OperationType.Update)
        fun Delete(species: SpeciesModel) = SyncOperation(species, OperationType.Delete)
    }
}

/**
 * Data class representing a pending detection
 */
private data class PendingDetection(
    val imageData: ByteArray,
    val latitude: Double,
    val longitude: Double,
    val timestamp: Long
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false

        other as PendingDetection
        return timestamp == other.timestamp
    }

    override fun hashCode(): Int {
        return timestamp.hashCode()
    }
}

/**
 * Custom exception for offline detection scenarios
 */
class OfflineDetectionPendingException(message: String) : Exception(message)