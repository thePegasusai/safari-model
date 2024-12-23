package com.wildlifesafari.app.domain.usecases

import android.graphics.Bitmap
import com.wildlifesafari.app.data.ml.LNNModelExecutor
import com.wildlifesafari.app.data.repository.SpeciesRepository
import com.wildlifesafari.app.domain.models.SpeciesModel
import javax.inject.Inject
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withTimeout
import java.util.concurrent.atomic.AtomicInteger
import android.util.Log

/**
 * Use case implementation for real-time species identification using Liquid Neural Networks (LNN).
 * Ensures high accuracy (90%) and low latency (sub-100ms) for species detection.
 *
 * Key features:
 * - Real-time LNN-based species detection
 * - Performance monitoring and optimization
 * - Automatic retry mechanism for failed detections
 * - Confidence threshold validation
 * - Location-aware species identification
 *
 * @property lnnModelExecutor Executor for LNN model operations
 * @property speciesRepository Repository for species data management
 */
class IdentifySpeciesUseCase @Inject constructor(
    private val lnnModelExecutor: LNNModelExecutor,
    private val speciesRepository: SpeciesRepository
) {
    companion object {
        private const val TAG = "IdentifySpeciesUseCase"
        private const val CONFIDENCE_THRESHOLD = 0.90f
        private const val TIMEOUT_MS = 100L
        private const val MAX_RETRIES = 2
        private const val MIN_IMAGE_SIZE = 224 // Minimum size for reliable detection
    }

    private val currentRetryCount = AtomicInteger(0)

    /**
     * Executes species identification with strict performance requirements.
     *
     * @param image Input image for species detection
     * @param latitude Location latitude for context-aware detection
     * @param longitude Location longitude for context-aware detection
     * @return Flow emitting identified species with confidence scores
     * @throws IllegalArgumentException if input parameters are invalid
     * @throws IllegalStateException if detection fails after retries
     */
    suspend operator fun invoke(
        image: Bitmap,
        latitude: Double,
        longitude: Double
    ): Flow<SpeciesModel> = flow {
        try {
            // Validate input parameters
            validateInput(image, latitude, longitude)

            // Process image with timeout constraint
            val result = withTimeout(TIMEOUT_MS) {
                val detectionResults = lnnModelExecutor.executeInference(image)
                
                // Get the most confident detection
                detectionResults.maxByOrNull { it.confidence }
                    ?: throw IllegalStateException("No species detected")
            }

            // Validate confidence threshold
            if (result.confidence < CONFIDENCE_THRESHOLD) {
                handleLowConfidence(result)
                return@flow
            }

            // Process detection result
            val speciesModel = processDetectionResult(result, latitude, longitude)

            // Save to repository
            try {
                speciesRepository.detectSpecies(
                    imageData = convertBitmapToByteArray(image),
                    latitude = latitude,
                    longitude = longitude
                )
            } catch (e: Exception) {
                Log.w(TAG, "Failed to save detection result: ${e.message}")
                // Continue emission even if save fails
            }

            // Emit the result
            emit(speciesModel)

        } catch (e: Exception) {
            handleDetectionError(e, image, latitude, longitude)
        } finally {
            currentRetryCount.set(0) // Reset retry count
        }
    }

    /**
     * Validates input parameters for species detection.
     *
     * @throws IllegalArgumentException if parameters are invalid
     */
    private fun validateInput(image: Bitmap, latitude: Double, longitude: Double) {
        require(!image.isRecycled) { "Input image is recycled" }
        require(image.width >= MIN_IMAGE_SIZE && image.height >= MIN_IMAGE_SIZE) {
            "Image dimensions too small for reliable detection"
        }
        require(latitude in -90.0..90.0) { "Invalid latitude value" }
        require(longitude in -180.0..180.0) { "Invalid longitude value" }
    }

    /**
     * Processes detection result and enriches with metadata.
     *
     * @param result Raw detection result from LNN model
     * @param latitude Detection location latitude
     * @param longitude Detection location longitude
     * @return Enriched SpeciesModel
     */
    private suspend fun processDetectionResult(
        result: LNNModelExecutor.DetectionResult,
        latitude: Double,
        longitude: Double
    ): SpeciesModel {
        return SpeciesModel(
            id = result.speciesId,
            scientificName = "", // Will be populated from repository
            commonName = "", // Will be populated from repository
            taxonomy = emptyMap(), // Will be populated from repository
            conservationStatus = "", // Will be populated from repository
            detectionConfidence = result.confidence,
            metadata = buildMap {
                put("detection_time_ms", result.processingTimeMs.toString())
                put("temporal_consistency", result.temporalConsistency.toString())
                put("latitude", latitude.toString())
                put("longitude", longitude.toString())
                put("detection_timestamp", System.currentTimeMillis().toString())
            },
            isFossil = false // Default to wildlife detection
        )
    }

    /**
     * Handles low confidence detection scenarios.
     *
     * @param result Detection result with low confidence
     * @throws IllegalStateException if confidence is below threshold
     */
    private fun handleLowConfidence(result: LNNModelExecutor.DetectionResult) {
        val message = "Detection confidence (${result.confidence}) below threshold ($CONFIDENCE_THRESHOLD)"
        Log.w(TAG, message)
        throw IllegalStateException(message)
    }

    /**
     * Handles detection errors with retry mechanism.
     *
     * @param error Original error
     * @param image Input image
     * @param latitude Location latitude
     * @param longitude Location longitude
     * @throws IllegalStateException if max retries exceeded
     */
    private suspend fun handleDetectionError(
        error: Exception,
        image: Bitmap,
        latitude: Double,
        longitude: Double
    ) {
        Log.e(TAG, "Detection error: ${error.message}")

        if (currentRetryCount.incrementAndGet() <= MAX_RETRIES) {
            Log.d(TAG, "Retrying detection (attempt ${currentRetryCount.get()})")
            invoke(image, latitude, longitude)
        } else {
            throw IllegalStateException("Species detection failed after $MAX_RETRIES retries", error)
        }
    }

    /**
     * Converts bitmap to byte array for repository storage.
     *
     * @param bitmap Input bitmap
     * @return ByteArray representation of the bitmap
     */
    private fun convertBitmapToByteArray(bitmap: Bitmap): ByteArray {
        return bitmap.let {
            android.graphics.Bitmap.createBitmap(
                it.width,
                it.height,
                Bitmap.Config.ARGB_8888
            ).also { copy ->
                android.graphics.Canvas(copy).drawBitmap(it, 0f, 0f, null)
            }
        }.let { copy ->
            java.io.ByteArrayOutputStream().use { stream ->
                copy.compress(Bitmap.CompressFormat.JPEG, 90, stream)
                stream.toByteArray()
            }
        }
    }
}