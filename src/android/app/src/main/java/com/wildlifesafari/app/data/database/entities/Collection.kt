/*
 * Room database entity class for Collection
 * Represents a collection of wildlife and fossil discoveries in the local SQLite database
 * 
 * Dependencies:
 * - androidx.room:room-runtime:2.6.0
 * - java.util.UUID
 */

package com.wildlifesafari.app.data.database.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.TypeConverters
import java.util.UUID

/**
 * Room database entity representing a collection of wildlife and fossil discoveries.
 * Supports offline storage and cloud synchronization capabilities.
 *
 * @property id Unique identifier for the collection, consistent across devices
 * @property name Display name of the collection
 * @property description Optional description of the collection's contents
 * @property discoveryIds List of associated discovery UUIDs in this collection
 * @property createdAt Timestamp of collection creation (Unix timestamp)
 * @property updatedAt Timestamp of last modification (Unix timestamp)
 * @property isSynced Flag indicating if collection is synchronized with cloud
 */
@Entity(tableName = "collections")
@TypeConverters(Converters::class)
data class Collection(
    @PrimaryKey
    val id: UUID = UUID.randomUUID(),

    @ColumnInfo(name = "name")
    val name: String,

    @ColumnInfo(name = "description")
    val description: String = "",

    @ColumnInfo(name = "discovery_ids")
    val discoveryIds: List<UUID> = emptyList(),

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "updated_at")
    val updatedAt: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "is_synced")
    val isSynced: Boolean = false
) {
    /**
     * Converts the database entity to a domain model representation.
     * This mapping ensures separation between database and domain layers.
     *
     * @return CollectionModel Domain model instance with mapped properties
     */
    fun toModel(): CollectionModel = CollectionModel(
        id = id,
        name = name,
        description = description,
        discoveryIds = discoveryIds.toList(), // Create defensive copy
        createdAt = createdAt,
        updatedAt = updatedAt,
        isSynced = isSynced
    )

    companion object {
        /**
         * Creates a Collection entity from a domain model.
         * Used when persisting domain model changes to the database.
         *
         * @param model Domain model instance to convert
         * @return Collection Database entity instance
         */
        fun fromModel(model: CollectionModel) = Collection(
            id = model.id,
            name = model.name,
            description = model.description,
            discoveryIds = model.discoveryIds.toList(), // Create defensive copy
            createdAt = model.createdAt,
            updatedAt = model.updatedAt,
            isSynced = model.isSynced
        )
    }

    /**
     * Validates that the collection entity meets database constraints.
     * @throws IllegalArgumentException if validation fails
     */
    fun validate() {
        require(name.isNotBlank()) { "Collection name cannot be blank" }
        require(name.length <= MAX_NAME_LENGTH) { 
            "Collection name cannot exceed $MAX_NAME_LENGTH characters" 
        }
        require(description.length <= MAX_DESCRIPTION_LENGTH) {
            "Collection description cannot exceed $MAX_DESCRIPTION_LENGTH characters"
        }
    }

    companion object {
        const val MAX_NAME_LENGTH = 100
        const val MAX_DESCRIPTION_LENGTH = 500
    }
}