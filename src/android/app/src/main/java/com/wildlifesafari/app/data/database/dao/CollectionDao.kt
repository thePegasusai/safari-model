/*
 * Data Access Object (DAO) interface for Collection entity operations
 * Provides optimized database access methods with transaction safety and sync support
 *
 * Dependencies:
 * - androidx.room:room-runtime:2.6.0
 * - kotlinx.coroutines:kotlinx-coroutines-core:1.7.0
 */

package com.wildlifesafari.app.data.database.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import com.wildlifesafari.app.data.database.entities.Collection
import kotlinx.coroutines.flow.Flow
import java.util.UUID

/**
 * Room DAO interface for Collection entity operations with enhanced sync support.
 * Provides reactive data access using Kotlin Flow and ensures transaction safety.
 *
 * Key features:
 * - Reactive queries using Flow for real-time updates
 * - Optimized query performance with proper indexing
 * - Transaction safety for data consistency
 * - Sync status tracking for offline support
 * - Cascading operations for related data
 */
@Dao
interface CollectionDao {

    /**
     * Retrieves all collections ordered by creation date.
     * Uses Flow for reactive updates when data changes.
     *
     * @return Flow emitting list of all collections
     */
    @Query("""
        SELECT * FROM collections 
        ORDER BY created_at DESC
    """)
    fun getAll(): Flow<List<Collection>>

    /**
     * Retrieves a specific collection by its ID.
     * Uses indexed lookup for optimal performance.
     *
     * @param id Unique identifier of the collection
     * @return Flow emitting the requested collection or null if not found
     */
    @Query("""
        SELECT * FROM collections 
        WHERE id = :id
    """)
    fun getById(id: UUID): Flow<Collection?>

    /**
     * Retrieves all collections that haven't been synced with the server.
     * Used by background sync worker for offline support.
     *
     * @return Flow emitting list of unsynced collections
     */
    @Query("""
        SELECT * FROM collections 
        WHERE is_synced = 0 
        ORDER BY updated_at ASC
    """)
    fun getUnsyncedCollections(): Flow<List<Collection>>

    /**
     * Inserts a new collection into the database.
     * Uses REPLACE strategy to handle conflicts with existing IDs.
     *
     * @param collection Collection entity to insert
     * @return Row ID of the inserted collection
     */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(collection: Collection): Long

    /**
     * Updates an existing collection in the database.
     * Maintains updated_at timestamp for sync tracking.
     *
     * @param collection Collection entity to update
     * @return Number of rows updated
     */
    @Update
    suspend fun update(collection: Collection): Int

    /**
     * Deletes a collection from the database.
     * Cascading deletion handled by foreign key constraints.
     *
     * @param collection Collection entity to delete
     * @return Number of rows deleted
     */
    @Delete
    suspend fun delete(collection: Collection): Int

    /**
     * Updates the sync status of a collection.
     * Used during background synchronization process.
     *
     * @param id Collection identifier
     * @param isSynced New sync status
     * @return Number of rows updated
     */
    @Query("""
        UPDATE collections 
        SET is_synced = :isSynced, 
            updated_at = :timestamp 
        WHERE id = :id
    """)
    suspend fun updateSyncStatus(
        id: UUID, 
        isSynced: Boolean,
        timestamp: Long = System.currentTimeMillis()
    ): Int

    /**
     * Adds a discovery to a collection's discovery list.
     * Ensures atomic transaction for data consistency.
     *
     * @param collectionId Collection identifier
     * @param discoveryId Discovery identifier to add
     */
    @Transaction
    suspend fun addDiscoveryToCollection(collectionId: UUID, discoveryId: UUID) {
        val collection = getById(collectionId).value
        collection?.let {
            val updatedCollection = it.copy(
                discoveryIds = it.discoveryIds + discoveryId,
                updatedAt = System.currentTimeMillis(),
                isSynced = false
            )
            update(updatedCollection)
        }
    }

    /**
     * Removes a discovery from a collection's discovery list.
     * Ensures atomic transaction for data consistency.
     *
     * @param collectionId Collection identifier
     * @param discoveryId Discovery identifier to remove
     */
    @Transaction
    suspend fun removeDiscoveryFromCollection(collectionId: UUID, discoveryId: UUID) {
        val collection = getById(collectionId).value
        collection?.let {
            val updatedCollection = it.copy(
                discoveryIds = it.discoveryIds - discoveryId,
                updatedAt = System.currentTimeMillis(),
                isSynced = false
            )
            update(updatedCollection)
        }
    }

    /**
     * Retrieves collections containing a specific discovery.
     * Optimized query using indexed discovery_ids column.
     *
     * @param discoveryId Discovery identifier to search for
     * @return Flow emitting list of collections containing the discovery
     */
    @Query("""
        SELECT * FROM collections 
        WHERE :discoveryId IN (
            SELECT value FROM json_each(discovery_ids)
        )
    """)
    fun getCollectionsContainingDiscovery(discoveryId: UUID): Flow<List<Collection>>

    /**
     * Retrieves collections modified after a specific timestamp.
     * Used for incremental sync and conflict resolution.
     *
     * @param timestamp Unix timestamp threshold
     * @return Flow emitting list of recently modified collections
     */
    @Query("""
        SELECT * FROM collections 
        WHERE updated_at > :timestamp 
        ORDER BY updated_at ASC
    """)
    fun getCollectionsModifiedAfter(timestamp: Long): Flow<List<Collection>>
}