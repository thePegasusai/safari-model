/*
 * Room Database DAO: SpeciesDao
 * Version: 1.0
 *
 * Dependencies:
 * - androidx.room:room-runtime:2.6.0
 * - androidx.room:room-ktx:2.6.0
 * - kotlinx.coroutines:kotlinx-coroutines-core:1.7.3
 */

package com.wildlifesafari.app.data.database.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.wildlifesafari.app.data.database.entities.Species
import kotlinx.coroutines.flow.Flow

/**
 * Data Access Object (DAO) interface for Species entity operations in Room database.
 * Provides optimized and reactive database operations with sync support.
 *
 * Key features:
 * - Reactive queries using Kotlin Flow
 * - Optimized batch operations
 * - Conflict resolution for sync scenarios
 * - Index-based lookups for performance
 * - Referential integrity maintenance
 */
@Dao
interface SpeciesDao {

    /**
     * Retrieves all species from the database with reactive updates.
     * Uses Room's query optimization and Flow for reactive streams.
     *
     * @return Flow emitting List of all Species, automatically updated on changes
     */
    @Query("SELECT * FROM species ORDER BY scientific_name ASC")
    fun getAll(): Flow<List<Species>>

    /**
     * Retrieves a specific species by its ID using indexed lookup.
     * Leverages Room's query optimization for primary key lookups.
     *
     * @param id Unique identifier of the species
     * @return Flow emitting the Species if found, null otherwise
     */
    @Query("SELECT * FROM species WHERE id = :id")
    fun getById(id: String): Flow<Species?>

    /**
     * Retrieves a species by its scientific name using indexed search.
     * Optimized for case-sensitive exact matches on the scientific_name column.
     *
     * @param name Scientific name to search for
     * @return Flow emitting the Species if found, null otherwise
     */
    @Query("SELECT * FROM species WHERE scientific_name = :name")
    fun getByScientificName(name: String): Flow<Species?>

    /**
     * Retrieves all fossil species with optimized query.
     * Filtered query for fossil specimens with index usage.
     *
     * @return Flow emitting List of fossil Species
     */
    @Query("SELECT * FROM species WHERE is_fossil = 1 ORDER BY scientific_name ASC")
    fun getFossils(): Flow<List<Species>>

    /**
     * Retrieves species by conservation status with pagination support.
     * Optimized for filtered queries with ordering.
     *
     * @param status Conservation status to filter by
     * @return Flow emitting List of Species with specified conservation status
     */
    @Query("SELECT * FROM species WHERE conservation_status = :status ORDER BY scientific_name ASC")
    fun getByConservationStatus(status: String): Flow<List<Species>>

    /**
     * Retrieves species updated after specified timestamp.
     * Supports incremental sync operations.
     *
     * @param timestamp Milliseconds since epoch
     * @return Flow emitting List of recently updated Species
     */
    @Query("SELECT * FROM species WHERE last_updated > :timestamp ORDER BY last_updated DESC")
    fun getUpdatedAfter(timestamp: Long): Flow<List<Species>>

    /**
     * Inserts a new species with conflict resolution.
     * Uses REPLACE strategy for sync scenarios.
     *
     * @param species Species entity to insert
     * @return ID of inserted species
     */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(species: Species): Long

    /**
     * Batch inserts multiple species with conflict handling.
     * Optimized for bulk operations during sync.
     *
     * @param species List of Species entities to insert
     * @return List of inserted species IDs
     */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(species: List<Species>): List<Long>

    /**
     * Updates existing species with optimistic locking.
     * Verifies lastUpdated timestamp before update.
     *
     * @param species Species entity to update
     * @return Number of rows updated
     */
    @Update
    suspend fun update(species: Species): Int

    /**
     * Deletes species with referential integrity check.
     * Ensures clean removal of species data.
     *
     * @param species Species entity to delete
     * @return Number of rows deleted
     */
    @Delete
    suspend fun delete(species: Species): Int

    /**
     * Batch deletes species by IDs.
     * Optimized for bulk cleanup operations.
     *
     * @param ids List of species IDs to delete
     * @return Number of rows deleted
     */
    @Query("DELETE FROM species WHERE id IN (:ids)")
    suspend fun deleteByIds(ids: List<String>): Int

    /**
     * Searches species by partial name match.
     * Optimized for search functionality with index usage.
     *
     * @param query Search query string
     * @return Flow emitting List of matching Species
     */
    @Query("""
        SELECT * FROM species 
        WHERE scientific_name LIKE '%' || :query || '%' 
        OR common_name LIKE '%' || :query || '%' 
        ORDER BY scientific_name ASC
    """)
    fun searchByName(query: String): Flow<List<Species>>
}