package com.wildlifesafari.app.domain.usecases

import com.wildlifesafari.app.domain.models.DiscoveryModel
import com.wildlifesafari.app.data.repository.DiscoveryRepository
import java.util.UUID
import javax.inject.Inject
import kotlin.Result

/**
 * Use case that implements the business logic for adding new wildlife or fossil discoveries
 * to the user's collection. Provides comprehensive validation, offline-first persistence,
 * and research-grade data contribution capabilities.
 *
 * Key features:
 * - Comprehensive discovery validation
 * - Research-grade quality assessment
 * - Offline-first data persistence
 * - Automatic cloud synchronization
 * - Error handling and validation feedback
 *
 * @property repository Repository for managing discovery data
 */
class AddDiscoveryUseCase @Inject constructor(
    private val repository: DiscoveryRepository
) {
    companion object {
        private const val MIN_CONFIDENCE_THRESHOLD = 0.85f
        private const val RESEARCH_GRADE_THRESHOLD = 0.95f
        private const val MAX_LOCATION_ACCURACY = 50f // meters
        private const val MIN_IMAGE_QUALITY_SCORE = 0.8f
    }

    /**
     * Executes the use case to add a new discovery with comprehensive validation.
     *
     * @param discovery The discovery to be added
     * @return Result containing UUID of added discovery or error details
     */
    suspend operator fun invoke(discovery: DiscoveryModel): Result<UUID> {
        return try {
            // Validate discovery data
            validateDiscovery(discovery).getOrThrow()

            // Attempt to add discovery through repository
            repository.addDiscovery(discovery).map {
                discovery.id
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Performs comprehensive validation of discovery data including location accuracy,
     * species confidence, and research-grade requirements.
     *
     * @param discovery Discovery to validate
     * @return Result indicating validation success or detailed failure
     */
    private fun validateDiscovery(discovery: DiscoveryModel): Result<Unit> {
        return try {
            // Validate location data
            require(discovery.isValidLocation()) {
                "Invalid location data: Latitude and longitude must be within valid ranges"
            }
            require(discovery.accuracy <= MAX_LOCATION_ACCURACY) {
                "Location accuracy (${discovery.accuracy}m) exceeds maximum threshold ($MAX_LOCATION_ACCURACY m)"
            }

            // Validate species identification confidence
            require(discovery.confidence >= MIN_CONFIDENCE_THRESHOLD) {
                "Species identification confidence (${discovery.confidence}) below minimum threshold ($MIN_CONFIDENCE_THRESHOLD)"
            }

            // Validate basic required fields
            require(discovery.speciesName.isNotBlank()) {
                "Species name cannot be blank"
            }
            require(discovery.scientificName.isNotBlank()) {
                "Scientific name cannot be blank"
            }
            require(discovery.imageUrl.isNotBlank()) {
                "Image URL cannot be blank"
            }

            // Additional validation for research-grade submissions
            if (discovery.confidence >= RESEARCH_GRADE_THRESHOLD) {
                validateResearchGradeRequirements(discovery)
            }

            Result.success(Unit)
        } catch (e: IllegalArgumentException) {
            Result.failure(e)
        }
    }

    /**
     * Validates additional requirements for research-grade discoveries.
     *
     * @param discovery Discovery to validate
     * @throws IllegalArgumentException if research-grade requirements not met
     */
    private fun validateResearchGradeRequirements(discovery: DiscoveryModel) {
        // Verify required metadata for research-grade status
        val requiredMetadataKeys = setOf(
            "habitat",
            "weather_conditions",
            "observer_notes"
        )

        require(discovery.metadata?.keys?.containsAll(requiredMetadataKeys) == true) {
            "Research-grade submissions require complete metadata (habitat, weather conditions, and observer notes)"
        }

        // Validate location accuracy for research-grade
        require(discovery.accuracy <= MAX_LOCATION_ACCURACY / 2) {
            "Research-grade submissions require higher location accuracy (${MAX_LOCATION_ACCURACY/2}m)"
        }

        // Ensure high confidence score
        require(discovery.confidence >= RESEARCH_GRADE_THRESHOLD) {
            "Research-grade submissions require confidence score of $RESEARCH_GRADE_THRESHOLD or higher"
        }
    }
}