/*
 * Repository implementation for managing wildlife and fossil collections
 * Provides offline-first architecture with enhanced sync capabilities
 *
 * Dependencies:
 * - kotlinx.coroutines:kotlinx-coroutines-core:1.7.0
 * - androidx.work:work-runtime-ktx:2.8.1
 * - androidx.room:room-runtime:2.5.2
 * - javax.inject:javax.inject:1
 */

package com.wildlifesafari.app.data.repository

import com.wildlifesafari.app.data.database.dao.CollectionDao
import com.wildlifesafari.app.data.database.entities.Collection
import com.wildlifesafari.app.data.api.ApiService
import com.wildlifesafari.app.data.models.CollectionModel
import com.wildlifesafari.app.data.models.SyncResult
import com.wildlifesafari.app.utils.NetworkUtils
import com.wildlifesafari.app.utils.Result
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.*
import androidx.work.*
import java.util.UUID
import java.util.concurrent.TimeUnit

/**
 * Repository implementation for managing wildlife and fossil collections with enhanced offline support.
 * Implements offline-first architecture with optimized sync mechanisms and conflict resolution.
 *
 * Key features:
 * - Offline-first data access with background sync
 * - Optimistic locking for conflict resolution
 * - Retry mechanism for failed operations
 * - Batch processing for sync operations
 * - Real-time sync status updates
 */
@Singleton
class CollectionRepository @Inject constructor(
    private val collectionDao: CollectionDao,
    private val apiService: ApiService,
    private val workManager: WorkManager,
    private val networkUtils: NetworkUtils
) {
    // Sync status monitoring
    private val _syncStatus = MutableStateFlow<SyncStatus>(SyncStatus.Idle)
    val syncStatus: StateFlow<SyncStatus> = _syncStatus.asStateFlow()

    // Background work constraints
    private val syncConstraints = Constraints.Builder()
        .setRequiredNetworkType(NetworkType.CONNECTED)
        .setRequiresBatteryNotLow(true)
        .build()

    init {
        setupPeriodicSync()
    }

    /**
     * Retrieves all collections with offline support and background sync.
     * Implements caching strategy for optimal performance.
     *
     * @return Flow of collection list with real-time updates
     */
    fun getAllCollections(): Flow<List<CollectionModel>> = collectionDao.getAll()
        .map { collections -> collections.map { it.toModel() } }
        .onEach { collections ->
            if (shouldTriggerSync()) {
                scheduleSyncWork()
            }
        }
        .catch { error ->
            emit(emptyList())
            _syncStatus.value = SyncStatus.Error(error)
        }

    /**
     * Retrieves a specific collection by ID with offline support.
     *
     * @param id Collection identifier
     * @return Flow emitting the requested collection or null
     */
    fun getCollectionById(id: UUID): Flow<CollectionModel?> = collectionDao.getById(id)
        .map { collection -> collection?.toModel() }
        .catch { error ->
            emit(null)
            _syncStatus.value = SyncStatus.Error(error)
        }

    /**
     * Creates a new collection with offline support.
     *
     * @param collection Collection to create
     * @return Result indicating success or failure
     */
    suspend fun createCollection(collection: CollectionModel): Result<UUID> {
        return try {
            val entity = Collection.fromModel(collection)
            entity.validate()
            val id = collectionDao.insert(entity)
            scheduleSyncWork()
            Result.Success(entity.id)
        } catch (e: Exception) {
            Result.Error(e)
        }
    }

    /**
     * Updates an existing collection with offline support and conflict resolution.
     *
     * @param collection Collection to update
     * @return Result indicating success or failure
     */
    suspend fun updateCollection(collection: CollectionModel): Result<Unit> {
        return try {
            val entity = Collection.fromModel(collection)
            entity.validate()
            collectionDao.update(entity)
            scheduleSyncWork()
            Result.Success(Unit)
        } catch (e: Exception) {
            Result.Error(e)
        }
    }

    /**
     * Deletes a collection with offline support.
     *
     * @param collection Collection to delete
     * @return Result indicating success or failure
     */
    suspend fun deleteCollection(collection: CollectionModel): Result<Unit> {
        return try {
            val entity = Collection.fromModel(collection)
            collectionDao.delete(entity)
            scheduleSyncWork()
            Result.Success(Unit)
        } catch (e: Exception) {
            Result.Error(e)
        }
    }

    /**
     * Initiates manual synchronization of collections.
     * Implements optimistic locking and conflict resolution.
     *
     * @return Result containing sync status
     */
    suspend fun syncCollections(): Result<SyncResult> {
        if (!networkUtils.isNetworkAvailable()) {
            return Result.Error(Exception("No network connection available"))
        }

        _syncStatus.value = SyncStatus.Syncing

        return try {
            val unsyncedCollections = collectionDao.getUnsyncedCollections()
                .first()
                .map { it.toModel() }

            val syncResult = performSync(unsyncedCollections)
            _syncStatus.value = SyncStatus.Success(syncResult)
            Result.Success(syncResult)
        } catch (e: Exception) {
            _syncStatus.value = SyncStatus.Error(e)
            Result.Error(e)
        }
    }

    /**
     * Performs the actual sync operation with conflict resolution.
     *
     * @param collections Collections to sync
     * @return SyncResult containing sync statistics
     */
    private suspend fun performSync(collections: List<CollectionModel>): SyncResult {
        var succeeded = 0
        var failed = 0
        var conflicts = 0

        collections.forEach { collection ->
            try {
                val serverVersion = apiService.getCollectionVersion(collection.id)
                when {
                    serverVersion > collection.version -> {
                        // Server has newer version, fetch and merge
                        val serverCollection = apiService.getCollection(collection.id)
                        resolveConflict(collection, serverCollection)
                        conflicts++
                    }
                    serverVersion < collection.version -> {
                        // Local version is newer, push to server
                        apiService.updateCollection(collection)
                        collectionDao.updateSyncStatus(collection.id, true)
                        succeeded++
                    }
                    else -> {
                        // Versions match, no action needed
                        collectionDao.updateSyncStatus(collection.id, true)
                        succeeded++
                    }
                }
            } catch (e: Exception) {
                failed++
            }
        }

        return SyncResult(succeeded, failed, conflicts)
    }

    /**
     * Resolves conflicts between local and server versions of a collection.
     *
     * @param local Local version of the collection
     * @param server Server version of the collection
     */
    private suspend fun resolveConflict(local: CollectionModel, server: CollectionModel) {
        val merged = mergeCollections(local, server)
        collectionDao.update(Collection.fromModel(merged))
        apiService.updateCollection(merged)
    }

    /**
     * Merges local and server versions of a collection using a last-write-wins strategy.
     *
     * @param local Local version of the collection
     * @param server Server version of the collection
     * @return Merged collection
     */
    private fun mergeCollections(local: CollectionModel, server: CollectionModel): CollectionModel {
        return if (local.updatedAt > server.updatedAt) {
            local.copy(version = server.version + 1)
        } else {
            server.copy(version = server.version + 1)
        }
    }

    /**
     * Sets up periodic background sync using WorkManager.
     */
    private fun setupPeriodicSync() {
        val syncRequest = PeriodicWorkRequestBuilder<SyncWorker>(
            15, TimeUnit.MINUTES,
            5, TimeUnit.MINUTES
        )
        .setConstraints(syncConstraints)
        .setBackoffCriteria(
            BackoffPolicy.EXPONENTIAL,
            WorkRequest.MIN_BACKOFF_MILLIS,
            TimeUnit.MILLISECONDS
        )
        .build()

        workManager.enqueueUniquePeriodicWork(
            SYNC_WORK_NAME,
            ExistingPeriodicWorkPolicy.KEEP,
            syncRequest
        )
    }

    /**
     * Schedules immediate sync work.
     */
    private fun scheduleSyncWork() {
        val syncRequest = OneTimeWorkRequestBuilder<SyncWorker>()
            .setConstraints(syncConstraints)
            .setBackoffCriteria(
                BackoffPolicy.EXPONENTIAL,
                WorkRequest.MIN_BACKOFF_MILLIS,
                TimeUnit.MILLISECONDS
            )
            .build()

        workManager.enqueueUniqueWork(
            SYNC_WORK_NAME,
            ExistingWorkPolicy.REPLACE,
            syncRequest
        )
    }

    /**
     * Determines if sync should be triggered based on various conditions.
     */
    private fun shouldTriggerSync(): Boolean {
        return networkUtils.isNetworkAvailable() &&
                _syncStatus.value !is SyncStatus.Syncing
    }

    companion object {
        private const val SYNC_WORK_NAME = "collection_sync_work"
    }
}

/**
 * Sealed class representing possible sync states.
 */
sealed class SyncStatus {
    object Idle : SyncStatus()
    object Syncing : SyncStatus()
    data class Success(val result: SyncResult) : SyncStatus()
    data class Error(val error: Throwable) : SyncStatus()
}