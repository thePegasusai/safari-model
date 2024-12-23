package com.wildlifesafari.app.data.database.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import com.wildlifesafari.app.data.database.entities.Discovery
import kotlinx.coroutines.flow.Flow
import java.util.UUID

/**
 * Data Access Object (DAO) interface for managing Discovery entities in the Room database.
 * Provides optimized and transaction-safe operations for CRUD operations on discoveries
 * with comprehensive sync support and reactive data streams using Kotlin Flow.
 *
 * Key features:
 * - Reactive data streams using Kotlin Flow
 * - Transaction safety for all write operations
 * - Optimized queries with proper indexing
 * - Comprehensive sync status management
 * - Batch operation support
 *
 * @see Discovery for the entity structure
 * @version 1.0
 */
@Dao
interface DiscoveryDao {

    /**
     * Retrieves a specific discovery by its unique identifier.
     * Uses indexed lookup for optimal performance.
     *
     * @param id The UUID of the discovery to retrieve
     * @return Flow emitting the discovery or null if not found
     */
    @Query("""
        SELECT * FROM discoveries 
        WHERE id = :id
    """)
    fun getDiscoveryById(id: UUID): Flow<Discovery?>

    /**
     * Retrieves all discoveries belonging to a specific collection.
     * Results are ordered by timestamp descending (newest first).
     *
     * @param collectionId The UUID of the parent collection
     * @return Flow emitting list of discoveries in the collection
     */
    @Query("""
        SELECT * FROM discoveries 
        WHERE collection_id = :collectionId 
        ORDER BY timestamp DESC
    """)
    fun getDiscoveriesByCollectionId(collectionId: UUID): Flow<List<Discovery>>

    /**
     * Retrieves all discoveries that haven't been synced to the cloud yet.
     * Used by the sync service for background synchronization.
     *
     * @return Flow emitting list of unsynced discoveries
     */
    @Query("""
        SELECT * FROM discoveries 
        WHERE is_synced = 0 
        ORDER BY timestamp ASC
    """)
    fun getUnsyncedDiscoveries(): Flow<List<Discovery>>

    /**
     * Retrieves discoveries within a specific time range.
     * Useful for filtering and reporting purposes.
     *
     * @param startTime Start of the time range in milliseconds
     * @param endTime End of the time range in milliseconds
     * @return Flow emitting list of discoveries within the time range
     */
    @Query("""
        SELECT * FROM discoveries 
        WHERE timestamp BETWEEN :startTime AND :endTime 
        ORDER BY timestamp DESC
    """)
    fun getDiscoveriesByTimeRange(startTime: Long, endTime: Long): Flow<List<Discovery>>

    /**
     * Inserts a new discovery into the database.
     * Uses REPLACE strategy to handle potential conflicts.
     *
     * @param discovery The Discovery entity to insert
     * @return Row ID of the inserted discovery
     */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    @Transaction
    suspend fun insertDiscovery(discovery: Discovery): Long

    /**
     * Inserts multiple discoveries in a single transaction.
     * Optimized for batch operations during sync.
     *
     * @param discoveries List of Discovery entities to insert
     * @return List of inserted row IDs
     */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    @Transaction
    suspend fun insertDiscoveries(discoveries: List<Discovery>): List<Long>

    /**
     * Updates an existing discovery in the database.
     * Maintains transaction safety for data integrity.
     *
     * @param discovery The Discovery entity to update
     * @return Number of rows updated (should be 1)
     */
    @Update
    @Transaction
    suspend fun updateDiscovery(discovery: Discovery): Int

    /**
     * Updates multiple discoveries in a single transaction.
     * Optimized for batch updates during sync.
     *
     * @param discoveries List of Discovery entities to update
     * @return Number of rows updated
     */
    @Update
    @Transaction
    suspend fun updateDiscoveries(discoveries: List<Discovery>): Int

    /**
     * Deletes a discovery from the database.
     * Cascading delete will handle related records.
     *
     * @param discovery The Discovery entity to delete
     * @return Number of rows deleted (should be 1)
     */
    @Delete
    @Transaction
    suspend fun deleteDiscovery(discovery: Discovery): Int

    /**
     * Marks a discovery as synced to the cloud.
     * Used by the sync service after successful synchronization.
     *
     * @param id The UUID of the discovery to mark as synced
     * @return Number of rows updated (should be 1)
     */
    @Query("""
        UPDATE discoveries 
        SET is_synced = 1 
        WHERE id = :id
    """)
    @Transaction
    suspend fun markAsSynced(id: UUID): Int

    /**
     * Marks multiple discoveries as synced in a single transaction.
     * Optimized for batch operations during sync.
     *
     * @param ids List of UUIDs to mark as synced
     * @return Number of rows updated
     */
    @Query("""
        UPDATE discoveries 
        SET is_synced = 1 
        WHERE id IN (:ids)
    """)
    @Transaction
    suspend fun markAsSynced(ids: List<UUID>): Int

    /**
     * Retrieves the count of unsynced discoveries.
     * Used for sync status monitoring and UI indicators.
     *
     * @return Flow emitting the count of unsynced discoveries
     */
    @Query("""
        SELECT COUNT(*) 
        FROM discoveries 
        WHERE is_synced = 0
    """)
    fun getUnsyncedCount(): Flow<Int>

    /**
     * Retrieves discoveries by species name.
     * Uses indexed lookup for optimal performance.
     *
     * @param speciesName The name of the species to search for
     * @return Flow emitting list of matching discoveries
     */
    @Query("""
        SELECT * FROM discoveries 
        WHERE species_name LIKE '%' || :speciesName || '%' 
        ORDER BY timestamp DESC
    """)
    fun searchBySpeciesName(speciesName: String): Flow<List<Discovery>>
}