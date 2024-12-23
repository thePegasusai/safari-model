package com.wildlifesafari.app.data.database.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import androidx.room.TypeConverters
import java.util.UUID

/**
 * Room database entity representing a wildlife or fossil discovery.
 * Supports comprehensive metadata storage, offline capabilities, and cloud synchronization.
 *
 * @property id Unique identifier for the discovery, compatible with cloud storage
 * @property collectionId Reference to the parent collection containing this discovery
 * @property speciesName Common name of the discovered species
 * @property scientificName Scientific name of the discovered species
 * @property latitude Geographic latitude of the discovery location
 * @property longitude Geographic longitude of the discovery location
 * @property accuracy Accuracy of the location measurement in meters
 * @property confidence ML model confidence score for the species identification
 * @property imageUrl Local or remote URL of the discovery image
 * @property isFossil Flag indicating if this is a fossil discovery
 * @property timestamp Unix timestamp of when the discovery was made
 * @property isSynced Flag indicating if the discovery has been synced to cloud
 * @property metadata Additional structured metadata about the discovery
 */
@Entity(
    tableName = "discoveries",
    foreignKeys = [
        ForeignKey(
            entity = Collection::class,
            parentColumns = ["id"],
            childColumns = ["collection_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index(value = ["collection_id"]),
        Index(value = ["species_name"]),
        Index(value = ["timestamp"])
    ]
)
@TypeConverters(Converters::class)
data class Discovery(
    @PrimaryKey
    val id: UUID,

    @ColumnInfo(name = "collection_id", index = true)
    val collectionId: UUID,

    @ColumnInfo(name = "species_name", index = true)
    val speciesName: String,

    @ColumnInfo(name = "scientific_name")
    val scientificName: String,

    @ColumnInfo(name = "latitude")
    val latitude: Double,

    @ColumnInfo(name = "longitude")
    val longitude: Double,

    @ColumnInfo(name = "accuracy")
    val accuracy: Float,

    @ColumnInfo(name = "confidence")
    val confidence: Float,

    @ColumnInfo(name = "image_url")
    val imageUrl: String,

    @ColumnInfo(name = "is_fossil")
    val isFossil: Boolean,

    @ColumnInfo(name = "timestamp", index = true)
    val timestamp: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "is_synced")
    val isSynced: Boolean = false,

    @ColumnInfo(name = "metadata")
    val metadata: Map<String, Any>? = null
) {
    /**
     * Secondary constructor with validation for creating new discoveries
     */
    constructor(
        id: UUID = UUID.randomUUID(),
        collectionId: UUID,
        speciesName: String,
        scientificName: String,
        latitude: Double,
        longitude: Double,
        accuracy: Float,
        confidence: Float,
        imageUrl: String,
        isFossil: Boolean,
        timestamp: Long = System.currentTimeMillis(),
        isSynced: Boolean = false,
        metadata: Map<String, Any>? = null
    ) : this(
        id = id,
        collectionId = collectionId,
        speciesName = speciesName.trim(),
        scientificName = scientificName.trim(),
        latitude = latitude.coerceIn(-90.0, 90.0),
        longitude = longitude.coerceIn(-180.0, 180.0),
        accuracy = accuracy.coerceAtLeast(0f),
        confidence = confidence.coerceIn(0f, 1f),
        imageUrl = imageUrl.trim(),
        isFossil = isFossil,
        timestamp = timestamp,
        isSynced = isSynced,
        metadata = metadata ?: emptyMap()
    )

    init {
        require(latitude in -90.0..90.0) { "Latitude must be between -90 and 90 degrees" }
        require(longitude in -180.0..180.0) { "Longitude must be between -180 and 180 degrees" }
        require(confidence in 0f..1f) { "Confidence must be between 0 and 1" }
        require(accuracy >= 0) { "Accuracy must be non-negative" }
        require(speciesName.isNotBlank()) { "Species name cannot be blank" }
        require(scientificName.isNotBlank()) { "Scientific name cannot be blank" }
        require(imageUrl.isNotBlank()) { "Image URL cannot be blank" }
    }

    companion object {
        /**
         * Minimum confidence threshold for valid species identification
         */
        const val MIN_CONFIDENCE_THRESHOLD = 0.5f

        /**
         * Maximum acceptable location accuracy in meters
         */
        const val MAX_ACCURACY_THRESHOLD = 100f
    }
}