/*
 * Use case for retrieving wildlife and fossil collections
 * Implements clean architecture principles with offline support
 *
 * Dependencies:
 * - kotlinx.coroutines:kotlinx-coroutines-core:1.7.0
 * - javax.inject:javax.inject:1
 * - com.jakewharton.timber:timber:5.0.1
 */

package com.wildlifesafari.app.domain.usecases

import com.wildlifesafari.app.data.repository.CollectionRepository
import com.wildlifesafari.app.domain.models.CollectionModel
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import timber.log.Timber

/**
 * Use case class that encapsulates the business logic for retrieving collections
 * with offline support and sync status filtering.
 *
 * Features:
 * - Clean architecture compliant collection retrieval
 * - Offline-first data access
 * - Sync status filtering
 * - Error handling and logging
 */
@Singleton
class GetCollectionsUseCase @Inject constructor(
    private val collectionRepository: CollectionRepository
) {

    init {
        Timber.d("Initializing GetCollectionsUseCase")
    }

    /**
     * Executes the use case to retrieve all collections with error handling.
     * Provides a clean interface for accessing collection data from the presentation layer.
     *
     * @return Flow emitting list of collections as domain models
     */
    fun execute(): Flow<List<CollectionModel>> {
        Timber.d("Executing GetCollectionsUseCase")
        return collectionRepository.getAllCollections()
            .catch { error ->
                Timber.e(error, "Error retrieving collections")
                emit(emptyList())
            }
            .map { collections ->
                Timber.d("Retrieved ${collections.size} collections")
                collections
            }
    }

    /**
     * Executes the use case with sync status filtering.
     * Allows filtering collections based on their synchronization status.
     *
     * @param syncedOnly When true, returns only synced collections; when false, returns all collections
     * @return Flow emitting filtered list of collections
     */
    fun executeWithFilter(syncedOnly: Boolean): Flow<List<CollectionModel>> {
        Timber.d("Executing GetCollectionsUseCase with syncedOnly: $syncedOnly")
        return collectionRepository.getAllCollections()
            .map { collections ->
                when (syncedOnly) {
                    true -> collections.filter { it.isSynced }
                    false -> collections
                }
            }
            .catch { error ->
                Timber.e(error, "Error retrieving filtered collections")
                emit(emptyList())
            }
            .map { collections ->
                Timber.d("Retrieved ${collections.size} filtered collections")
                collections
            }
    }

    companion object {
        private const val TAG = "GetCollectionsUseCase"
    }
}