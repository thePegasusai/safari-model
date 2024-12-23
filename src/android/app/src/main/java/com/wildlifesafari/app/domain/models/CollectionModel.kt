package com.wildlifesafari.app.domain.models

import android.os.Parcelable
import kotlinx.parcelize.Parcelize // version: 1.9.0
import java.util.UUID

/**
 * Immutable domain model representing a collection of wildlife and fossil discoveries.
 * Supports offline storage and cloud synchronization capabilities.
 *
 * @property id Unique identifier for the collection
 * @property name Display name of the collection
 * @property description Detailed description of the collection's purpose or contents
 * @property discoveryIds List of UUIDs referencing the discoveries in this collection
 * @property createdAt Timestamp of collection creation (milliseconds since epoch)
 * @property updatedAt Timestamp of last modification (milliseconds since epoch)
 * @property isSynced Flag indicating if the collection is synchronized with cloud storage
 */
@Parcelize
data class CollectionModel(
    val id: UUID,
    val name: String,
    val description: String,
    val discoveryIds: List<UUID>,
    val createdAt: Long,
    val updatedAt: Long,
    val isSynced: Boolean
) : Parcelable {

    /**
     * Converts the collection model to an immutable map for thread-safe database operations.
     *
     * @return An immutable map containing the collection's properties with standardized key names
     */
    fun toMap(): Map<String, Any> = buildMap {
        put("id", id.toString())
        put("name", name)
        put("description", description)
        put("discovery_ids", discoveryIds.map { it.toString() })
        put("created_at", createdAt)
        put("updated_at", updatedAt)
        put("is_synced", isSynced)
    }

    /**
     * Creates a new collection instance with an additional discovery ID.
     * Maintains immutability by returning a new instance with updated properties.
     *
     * @param discoveryId UUID of the discovery to add to the collection
     * @return New CollectionModel instance with updated discovery list and timestamp
     * @throws IllegalArgumentException if discoveryId is already in the collection
     */
    fun addDiscovery(discoveryId: UUID): CollectionModel {
        require(!discoveryIds.contains(discoveryId)) { 
            "Discovery with ID $discoveryId is already in the collection" 
        }
        
        return copy(
            discoveryIds = discoveryIds + discoveryId,
            updatedAt = System.currentTimeMillis(),
            isSynced = false
        )
    }

    /**
     * Creates a new collection instance with the specified discovery ID removed.
     * Maintains immutability by returning a new instance with updated properties.
     *
     * @param discoveryId UUID of the discovery to remove from the collection
     * @return New CollectionModel instance with updated discovery list and timestamp
     * @throws IllegalArgumentException if discoveryId is not in the collection
     */
    fun removeDiscovery(discoveryId: UUID): CollectionModel {
        require(discoveryIds.contains(discoveryId)) { 
            "Discovery with ID $discoveryId is not in the collection" 
        }
        
        return copy(
            discoveryIds = discoveryIds.filter { it != discoveryId },
            updatedAt = System.currentTimeMillis(),
            isSynced = false
        )
    }

    companion object {
        /**
         * Creates a new empty collection with the specified name and description.
         *
         * @param name Display name for the new collection
         * @param description Detailed description of the collection
         * @return New CollectionModel instance with initialized properties
         */
        fun create(name: String, description: String): CollectionModel {
            val timestamp = System.currentTimeMillis()
            return CollectionModel(
                id = UUID.randomUUID(),
                name = name,
                description = description,
                discoveryIds = emptyList(),
                createdAt = timestamp,
                updatedAt = timestamp,
                isSynced = false
            )
        }
    }
}