package com.wildlifesafari.app.domain.models

import android.os.Parcelable
import kotlinx.parcelize.Parcelize // version: 1.9.0

/**
 * Domain model representing a wildlife species or fossil with comprehensive metadata support.
 * This model provides a clean data representation for the presentation layer while supporting
 * both real-time species detection and fossil data management.
 *
 * @property id Unique identifier for the species
 * @property scientificName Scientific binomial nomenclature
 * @property commonName Common/vernacular name
 * @property taxonomy Hierarchical taxonomic classification
 * @property conservationStatus Conservation status according to IUCN standards
 * @property detectionConfidence ML detection confidence score (0.0 to 1.0)
 * @property imageUrl Optional URL to species reference image
 * @property description Optional detailed description
 * @property metadata Optional additional metadata key-value pairs
 * @property isFossil Flag indicating if the species is a fossil specimen
 * @property lastUpdated Timestamp of last update in milliseconds
 */
@Parcelize
data class SpeciesModel(
    val id: String,
    val scientificName: String,
    val commonName: String,
    val taxonomy: Map<String, String>,
    val conservationStatus: String,
    val detectionConfidence: Float,
    val imageUrl: String? = null,
    val description: String? = null,
    val metadata: Map<String, String>? = null,
    val isFossil: Boolean = false,
    val lastUpdated: Long = System.currentTimeMillis()
) : Parcelable {

    init {
        require(id.isNotBlank()) { "Species ID cannot be blank" }
        require(scientificName.isNotBlank()) { "Scientific name cannot be blank" }
        require(commonName.isNotBlank()) { "Common name cannot be blank" }
        require(taxonomy.isNotEmpty()) { "Taxonomy map cannot be empty" }
        require(conservationStatus.isNotBlank()) { "Conservation status cannot be blank" }
        require(detectionConfidence in 0.0..1.0) { "Detection confidence must be between 0.0 and 1.0" }
    }

    companion object {
        /**
         * Minimum confidence threshold for reliable species detection
         */
        const val CONFIDENCE_THRESHOLD = 0.9f
    }

    /**
     * Validates if the species detection confidence meets the required threshold
     * for reliable identification.
     *
     * @return true if detection confidence is >= 90%, false otherwise
     */
    fun isConfident(): Boolean = detectionConfidence >= CONFIDENCE_THRESHOLD

    /**
     * Converts the model instance to a map representation for serialization
     * and data transfer purposes.
     *
     * @return Map containing all model properties with their current values
     */
    fun toMap(): Map<String, Any?> = buildMap {
        put("id", id)
        put("scientificName", scientificName)
        put("commonName", commonName)
        put("taxonomy", taxonomy.toMap())
        put("conservationStatus", conservationStatus)
        put("detectionConfidence", detectionConfidence)
        put("imageUrl", imageUrl)
        put("description", description)
        put("metadata", metadata?.toMap())
        put("isFossil", isFossil)
        put("lastUpdated", lastUpdated)
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is SpeciesModel) return false

        return id == other.id &&
                scientificName == other.scientificName &&
                commonName == other.commonName &&
                taxonomy == other.taxonomy &&
                conservationStatus == other.conservationStatus &&
                detectionConfidence == other.detectionConfidence &&
                imageUrl == other.imageUrl &&
                description == other.description &&
                metadata == other.metadata &&
                isFossil == other.isFossil &&
                lastUpdated == other.lastUpdated
    }

    override fun hashCode(): Int {
        var result = id.hashCode()
        result = 31 * result + scientificName.hashCode()
        result = 31 * result + commonName.hashCode()
        result = 31 * result + taxonomy.hashCode()
        result = 31 * result + conservationStatus.hashCode()
        result = 31 * result + detectionConfidence.hashCode()
        result = 31 * result + (imageUrl?.hashCode() ?: 0)
        result = 31 * result + (description?.hashCode() ?: 0)
        result = 31 * result + (metadata?.hashCode() ?: 0)
        result = 31 * result + isFossil.hashCode()
        result = 31 * result + lastUpdated.hashCode()
        return result
    }
}