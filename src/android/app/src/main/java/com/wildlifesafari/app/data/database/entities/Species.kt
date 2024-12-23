/*
 * Room Database Entity: Species
 * Version: 1.0
 * 
 * Room Dependencies:
 * - androidx.room:room-runtime:2.6.0
 * - androidx.room:room-ktx:2.6.0
 */

package com.wildlifesafari.app.data.database.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.TypeConverters

/**
 * Room database entity representing a wildlife species or fossil in the local SQLite database.
 * Provides comprehensive storage capabilities for both wildlife and fossil data types with
 * extensive metadata support.
 *
 * @property id Unique identifier for the species
 * @property scientificName Scientific binomial nomenclature
 * @property commonName Common/vernacular name
 * @property taxonomy Hierarchical taxonomic classification
 * @property conservationStatus IUCN conservation status
 * @property detectionConfidence ML model detection confidence score (0.0 to 1.0)
 * @property imageUrl Optional URL to species reference image
 * @property description Optional detailed description
 * @property metadata Optional additional metadata key-value pairs
 * @property isFossil Flag indicating if the species is a fossil specimen
 * @property lastUpdated Timestamp of last update in milliseconds
 */
@Entity(tableName = "species")
@TypeConverters(Converters::class)
data class Species(
    @PrimaryKey
    val id: String,

    @ColumnInfo(name = "scientific_name")
    val scientificName: String,

    @ColumnInfo(name = "common_name")
    val commonName: String,

    @ColumnInfo(name = "taxonomy")
    val taxonomy: Map<String, String>,

    @ColumnInfo(name = "conservation_status")
    val conservationStatus: String,

    @ColumnInfo(name = "detection_confidence")
    val detectionConfidence: Float,

    @ColumnInfo(name = "image_url")
    val imageUrl: String? = null,

    @ColumnInfo(name = "description")
    val description: String? = null,

    @ColumnInfo(name = "metadata")
    val metadata: Map<String, String>? = null,

    @ColumnInfo(name = "is_fossil")
    val isFossil: Boolean,

    @ColumnInfo(name = "last_updated")
    val lastUpdated: Long = System.currentTimeMillis()
) {
    /**
     * Secondary constructor with validation
     */
    constructor(
        id: String,
        scientificName: String,
        commonName: String,
        taxonomy: Map<String, String>,
        conservationStatus: String,
        detectionConfidence: Float,
        imageUrl: String? = null,
        description: String? = null,
        metadata: Map<String, String>? = null,
        isFossil: Boolean
    ) : this(
        id = id.trim(),
        scientificName = scientificName.trim(),
        commonName = commonName.trim(),
        taxonomy = taxonomy,
        conservationStatus = conservationStatus.trim(),
        detectionConfidence = detectionConfidence.coerceIn(0f, 1f),
        imageUrl = imageUrl?.trim(),
        description = description?.trim(),
        metadata = metadata,
        isFossil = isFossil,
        lastUpdated = System.currentTimeMillis()
    ) {
        require(id.isNotBlank()) { "Species ID cannot be blank" }
        require(scientificName.isNotBlank()) { "Scientific name cannot be blank" }
        require(commonName.isNotBlank()) { "Common name cannot be blank" }
        require(taxonomy.isNotEmpty()) { "Taxonomy map cannot be empty" }
        require(conservationStatus.isNotBlank()) { "Conservation status cannot be blank" }
        validateTaxonomy(taxonomy)
    }

    /**
     * Validates the taxonomy map structure
     * @throws IllegalArgumentException if taxonomy structure is invalid
     */
    private fun validateTaxonomy(taxonomy: Map<String, String>) {
        val requiredRanks = setOf("kingdom", "phylum", "class", "order", "family", "genus")
        require(requiredRanks.all { taxonomy.containsKey(it) }) {
            "Taxonomy must contain all required ranks: $requiredRanks"
        }
    }

    /**
     * Converts the database entity to a domain model
     * @return SpeciesModel Domain model representation of the species
     */
    fun toModel(): SpeciesModel {
        return SpeciesModel(
            id = id,
            scientificName = scientificName,
            commonName = commonName,
            taxonomy = taxonomy.toMutableMap(),
            conservationStatus = conservationStatus,
            detectionConfidence = detectionConfidence,
            imageUrl = imageUrl,
            description = description,
            metadata = metadata?.toMutableMap(),
            isFossil = isFossil,
            lastUpdated = lastUpdated
        )
    }

    companion object {
        /**
         * Conservation status constants based on IUCN categories
         */
        object ConservationStatus {
            const val EXTINCT = "EX"
            const val EXTINCT_IN_WILD = "EW"
            const val CRITICALLY_ENDANGERED = "CR"
            const val ENDANGERED = "EN"
            const val VULNERABLE = "VU"
            const val NEAR_THREATENED = "NT"
            const val LEAST_CONCERN = "LC"
            const val DATA_DEFICIENT = "DD"
            const val NOT_EVALUATED = "NE"
        }

        /**
         * Taxonomy rank constants
         */
        object TaxonomyRanks {
            const val KINGDOM = "kingdom"
            const val PHYLUM = "phylum"
            const val CLASS = "class"
            const val ORDER = "order"
            const val FAMILY = "family"
            const val GENUS = "genus"
            const val SPECIES = "species"
        }
    }
}