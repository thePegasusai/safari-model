package com.wildlifesafari.app.data.repository

import android.net.NetworkInfo
import androidx.work.WorkManager
import com.wildlifesafari.app.data.api.ApiService
import com.wildlifesafari.app.data.database.dao.DiscoveryDao
import com.wildlifesafari.app.data.database.entities.Discovery
import com.wildlifesafari.app.domain.models.NetworkResult
import com.wildlifesafari.app.domain.models.DiscoveryModel
import com.wildlifesafari.app.util.NetworkMonitor
import com.wildlifesafari.app.util.SyncManager
import com.wildlifesafari.app.util.DiscoveryCache
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Repository implementing single source of truth pattern for discovery data management.
 * Provides offline-first capabilities, batch synchronization, and research-grade validation.
 *
 * Key features:
 * - Offline-first architecture with local caching
 * - Batch synchronization with conflict resolution
 * - Research-grade data validation
 * - Efficient memory cache management
 * - Robust error handling and retry mechanisms
 *
 * @property discoveryDao Local database access object
 * @property apiService Remote API service interface
 * @property networkMonitor Network connectivity monitor
 * @property syncManager Background sync orchestrator
 * @property cache In-memory cache for frequently accessed data
 */
@Singleton
class DiscoveryRepository @Inject constructor(
    private val discoveryDao: DiscoveryDao,
    private val apiService: ApiService,
    private val networkMonitor: NetworkMonitor,
    private val syncManager: SyncManager,
    private val workManager: WorkManager
) {
    private val cache = DiscoveryCache()
    private val syncBatchSize = 50
    private val syncTimeoutMs = 30_000L

    /**
     * Retrieves a discovery by its ID with caching support.
     * Implements offline-first pattern with cache -> local -> remote fallback.
     *
     * @param id Unique identifier of the discovery
     * @return Flow emitting the discovery or null if not found
     */
    fun getDiscoveryById(id: UUID): Flow<DiscoveryModel?> = discoveryDao
        .getDiscoveryById(id)
        .map { discovery ->
            discovery?.let {
                cache.get(id) ?: discovery.toModel().also { model ->
                    cache.put(id, model)
                }
            }
        }
        .catch { e ->
            emit(cache.get(id))
            throw e
        }
        .flowOn(Dispatchers.IO)

    /**
     * Retrieves discoveries for a specific collection with pagination.
     *
     * @param collectionId Collection identifier
     * @param page Page number (0-based)
     * @param pageSize Items per page
     * @return Flow emitting list of discoveries
     */
    fun getDiscoveriesByCollection(
        collectionId: UUID,
        page: Int,
        pageSize: Int
    ): Flow<List<DiscoveryModel>> = discoveryDao
        .getDiscoveriesByCollectionId(collectionId)
        .map { discoveries ->
            discoveries.map { it.toModel() }
        }
        .flowOn(Dispatchers.IO)

    /**
     * Adds a new discovery with validation and synchronization.
     *
     * @param discovery Discovery to be added
     * @return Result indicating success or failure with details
     */
    suspend fun addDiscovery(discovery: DiscoveryModel): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            // Validate research-grade requirements
            validateResearchGrade(discovery)

            // Store locally first (offline-first approach)
            val entity = Discovery(
                id = discovery.id,
                collectionId = discovery.collectionId,
                speciesName = discovery.speciesName,
                scientificName = discovery.scientificName,
                latitude = discovery.latitude,
                longitude = discovery.longitude,
                accuracy = discovery.accuracy,
                confidence = discovery.confidence,
                imageUrl = discovery.imageUrl,
                isFossil = discovery.isFossil,
                metadata = discovery.metadata
            )
            
            discoveryDao.insertDiscovery(entity)
            cache.put(discovery.id, discovery)

            // Attempt immediate sync if network available
            if (networkMonitor.isNetworkAvailable()) {
                syncDiscovery(discovery)
            } else {
                scheduleSyncWork()
            }

            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Synchronizes unsynced discoveries with the backend.
     * Implements batch processing with retry mechanism.
     *
     * @return Result indicating sync success or failure
     */
    suspend fun syncDiscoveries(): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            if (!networkMonitor.isNetworkAvailable()) {
                return@withContext Result.failure(Exception("No network connection"))
            }

            val unsyncedDiscoveries = discoveryDao.getUnsyncedDiscoveries()
                .map { discoveries -> discoveries.map { it.toModel() } }
                .first()

            // Process in batches for efficiency
            unsyncedDiscoveries.chunked(syncBatchSize).forEach { batch ->
                withTimeout(syncTimeoutMs) {
                    val syncResult = apiService.batchSync(batch)
                    
                    // Update sync status for successful items
                    val successfulIds = syncResult.syncedItems.map { it.id }
                    discoveryDao.markAsSynced(successfulIds)

                    // Handle failed items
                    syncResult.failedItems.forEach { failedItem ->
                        handleSyncFailure(failedItem)
                    }
                }
            }

            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Validates if a discovery meets research-grade requirements.
     *
     * @param discovery Discovery to validate
     * @throws IllegalArgumentException if requirements not met
     */
    private fun validateResearchGrade(discovery: DiscoveryModel) {
        require(discovery.confidence >= Discovery.MIN_CONFIDENCE_THRESHOLD) {
            "Confidence score below research-grade threshold"
        }
        require(discovery.accuracy <= Discovery.MAX_ACCURACY_THRESHOLD) {
            "Location accuracy exceeds research-grade threshold"
        }
        require(discovery.imageUrl.isNotBlank()) {
            "Research-grade discoveries require image documentation"
        }
    }

    /**
     * Handles sync failures with appropriate retry strategy.
     *
     * @param failedItem Failed sync item details
     */
    private suspend fun handleSyncFailure(failedItem: SyncFailure) {
        when (failedItem.reason) {
            SyncFailureReason.NETWORK_ERROR -> scheduleSyncRetry(failedItem.id)
            SyncFailureReason.VALIDATION_ERROR -> handleValidationError(failedItem)
            SyncFailureReason.CONFLICT -> resolveConflict(failedItem)
            else -> logSyncError(failedItem)
        }
    }

    /**
     * Schedules a background sync work request.
     */
    private fun scheduleSyncWork() {
        syncManager.scheduleSync(workManager)
    }

    /**
     * Cleans up resources when repository is no longer needed.
     */
    fun cleanup() {
        cache.clear()
    }

    companion object {
        private const val TAG = "DiscoveryRepository"
        private const val SYNC_RETRY_DELAY_MS = 5_000L
    }
}