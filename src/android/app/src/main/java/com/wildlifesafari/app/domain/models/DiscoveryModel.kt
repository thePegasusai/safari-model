package com.wildlifesafari.app.domain.models

import android.os.Parcelable // version: latest
import kotlinx.parcelize.Parcelize // version: 1.9.0
import java.util.UUID // version: latest
import kotlin.math.abs

/**
 * Domain model representing a wildlife or fossil discovery in the Wildlife Detection Safari application.
 * This model supports both real-time wildlife detection and fossil identification with enhanced
 * validation for research-grade contributions.
 *
 * @property id Unique identifier for the discovery
 * @property collectionId Identifier of the collection this discovery belongs to
 * @property speciesName Common name of the discovered species
 * @property scientificName Scientific name of the discovered species
 * @property latitude Geographic latitude of the discovery location
 * @property longitude Geographic longitude of the discovery location
 * @property accuracy GPS accuracy in meters
 * @property confidence Detection confidence score (0.0 to 1.0)
 * @property imageUrl URL to the discovery image
 * @property isFossil Flag indicating if the discovery is a fossil
 * @property timestamp Discovery timestamp in milliseconds
 * @property isSynced Flag indicating if the discovery has been synced to the cloud
 * @property metadata Additional discovery metadata
 */
@Parcelize
data class DiscoveryModel(
    val id: UUID,
    val collectionId: UUID,
    val speciesName: String,
    val scientificName: String,
    val latitude: Double,
    val longitude: Double,
    val accuracy: Float,
    val confidence: Float,
    val imageUrl: String,
    val isFossil: Boolean,
    val timestamp: Long = System.currentTimeMillis(),
    val isSynced: Boolean = false,
    val metadata: Map<String, Any>? = null
) : Parcelable {

    companion object {
        private const val MAX_LATITUDE = 90.0
        private const val MAX_LONGITUDE = 180.0
        private const val RESEARCH_GRADE_CONFIDENCE = 0.9f
        private const val RESEARCH_GRADE_ACCURACY = 10.0f // meters
        private const val URL_REGEX = "^(https?://)?([\\da-z.-]+)\\.([a-z.]{2,6})[/\\w .-]*/?$"
    }

    init {
        require(abs(latitude) <= MAX_LATITUDE) { 
            "Latitude must be between -$MAX_LATITUDE and $MAX_LATITUDE degrees" 
        }
        require(abs(longitude) <= MAX_LONGITUDE) { 
            "Longitude must be between -$MAX_LONGITUDE and $MAX_LONGITUDE degrees" 
        }
        require(confidence in 0.0..1.0) { 
            "Confidence must be between 0.0 and 1.0" 
        }
        require(accuracy > 0) { 
            "Accuracy must be positive" 
        }
        require(speciesName.isNotBlank()) { 
            "Species name cannot be blank" 
        }
        require(scientificName.isNotBlank()) { 
            "Scientific name cannot be blank" 
        }
        require(imageUrl.matches(Regex(URL_REGEX))) { 
            "Invalid image URL format" 
        }
    }

    /**
     * Converts the discovery model to a map representation for database operations
     * and data transfer.
     *
     * @return Map containing all discovery properties
     */
    fun toMap(): Map<String, Any> = buildMap {
        put("id", id.toString())
        put("collectionId", collectionId.toString())
        put("speciesName", speciesName)
        put("scientificName", scientificName)
        put("latitude", latitude)
        put("longitude", longitude)
        put("accuracy", accuracy)
        put("confidence", confidence)
        put("imageUrl", imageUrl)
        put("isFossil", isFossil)
        put("timestamp", timestamp)
        put("isSynced", isSynced)
        metadata?.let { put("metadata", it) }
    }

    /**
     * Validates the discovery's GPS coordinates and accuracy.
     *
     * @return true if location data is valid, false otherwise
     */
    fun isValidLocation(): Boolean {
        return abs(latitude) <= MAX_LATITUDE &&
                abs(longitude) <= MAX_LONGITUDE &&
                accuracy > 0 &&
                accuracy <= 100 // Reasonable maximum accuracy threshold
    }

    /**
     * Determines if the discovery meets enhanced research-grade criteria.
     * Research-grade discoveries require high confidence, accurate location,
     * and complete metadata.
     *
     * @return true if discovery meets research criteria, false otherwise
     */
    fun isResearchGrade(): Boolean {
        // Check basic criteria
        if (!isValidLocation() || confidence < RESEARCH_GRADE_CONFIDENCE) {
            return false
        }

        // Verify location accuracy
        if (accuracy > RESEARCH_GRADE_ACCURACY) {
            return false
        }

        // Validate image URL
        if (!imageUrl.matches(Regex(URL_REGEX))) {
            return false
        }

        // Verify required metadata for research-grade status
        val requiredMetadataKeys = setOf(
            "habitat",
            "weather_conditions",
            "observer_notes"
        )
        
        return metadata?.keys?.containsAll(requiredMetadataKeys) == true
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is DiscoveryModel) return false

        return id == other.id &&
                collectionId == other.collectionId &&
                speciesName == other.speciesName &&
                scientificName == other.scientificName &&
                latitude == other.latitude &&
                longitude == other.longitude &&
                accuracy == other.accuracy &&
                confidence == other.confidence &&
                imageUrl == other.imageUrl &&
                isFossil == other.isFossil &&
                timestamp == other.timestamp &&
                isSynced == other.isSynced &&
                metadata == other.metadata
    }

    override fun hashCode(): Int {
        var result = id.hashCode()
        result = 31 * result + collectionId.hashCode()
        result = 31 * result + speciesName.hashCode()
        result = 31 * result + scientificName.hashCode()
        result = 31 * result + latitude.hashCode()
        result = 31 * result + longitude.hashCode()
        result = 31 * result + accuracy.hashCode()
        result = 31 * result + confidence.hashCode()
        result = 31 * result + imageUrl.hashCode()
        result = 31 * result + isFossil.hashCode()
        result = 31 * result + timestamp.hashCode()
        result = 31 * result + isSynced.hashCode()
        result = 31 * result + (metadata?.hashCode() ?: 0)
        return result
    }
}