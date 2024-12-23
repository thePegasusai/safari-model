package com.wildlifesafari.app.ui.camera

import android.graphics.Bitmap
import androidx.lifecycle.viewModelScope
import com.wildlifesafari.app.domain.usecases.IdentifySpeciesUseCase
import com.wildlifesafari.app.ui.common.BaseViewModel
import com.wildlifesafari.app.utils.Constants
import com.wildlifesafari.app.utils.ImageUtils
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject
import timber.log.Timber // version: 5.0.1
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.time.Duration.Companion.milliseconds

/**
 * ViewModel responsible for managing camera-based species detection and fossil scanning using LNN.
 * Implements real-time processing with optimized memory management and dual-mode support.
 *
 * Features:
 * - Real-time LNN-based species detection
 * - Memory-optimized image processing
 * - Dual mode support (wildlife/fossil)
 * - Performance monitoring and optimization
 * - Error handling and recovery
 */
class CameraViewModel @Inject constructor(
    private val identifySpeciesUseCase: IdentifySpeciesUseCase
) : BaseViewModel() {

    companion object {
        private const val TAG = "CameraViewModel"
        private const val BITMAP_POOL_SIZE = 3
        private const val MAX_DETECTION_QUEUE_SIZE = 2
        private const val MIN_DETECTION_INTERVAL_MS = 100L
    }

    // Detection states
    sealed class DetectionState {
        object Idle : DetectionState()
        object Processing : DetectionState()
        data class Success(val species: SpeciesModel) : DetectionState()
        data class Error(val message: String) : DetectionState()
    }

    // Camera modes
    enum class CameraMode {
        WILDLIFE, FOSSIL
    }

    // State flows
    private val _detectionState = MutableStateFlow<DetectionState>(DetectionState.Idle)
    val detectionState: StateFlow<DetectionState> = _detectionState.asStateFlow()

    private val _flashEnabled = MutableStateFlow(false)
    val flashEnabled: StateFlow<Boolean> = _flashEnabled.asStateFlow()

    private val _cameraMode = MutableStateFlow(CameraMode.WILDLIFE)
    val cameraMode: StateFlow<CameraMode> = _cameraMode.asStateFlow()

    // Memory management
    private val bitmapPool = ConcurrentLinkedQueue<Bitmap>()
    private var lastDetectionTime = 0L
    private var processingCount = 0

    init {
        initializeBitmapPool()
    }

    /**
     * Processes camera frame for species detection with memory optimization.
     *
     * @param image Input bitmap from camera
     * @param latitude Current location latitude
     * @param longitude Current location longitude
     */
    suspend fun processImage(image: Bitmap, latitude: Double, longitude: Double) {
        // Throttle detection rate
        val currentTime = System.currentTimeMillis()
        if (currentTime - lastDetectionTime < MIN_DETECTION_INTERVAL_MS || processingCount >= MAX_DETECTION_QUEUE_SIZE) {
            return
        }
        lastDetectionTime = currentTime

        try {
            processingCount++
            _detectionState.value = DetectionState.Processing

            // Get bitmap from pool
            val processedBitmap = acquireProcessedBitmap(image)

            // Launch detection
            launchDataLoad {
                identifySpeciesUseCase.invoke(
                    image = processedBitmap,
                    latitude = latitude,
                    longitude = longitude
                ).collect { species ->
                    if (species.detectionConfidence >= Constants.MLConstants.DETECTION_THRESHOLD) {
                        _detectionState.value = DetectionState.Success(species)
                    } else {
                        _detectionState.value = DetectionState.Error(
                            "Low confidence detection: ${species.detectionConfidence}"
                        )
                    }
                }
            }

            // Release bitmap back to pool
            releaseBitmap(processedBitmap)

        } catch (e: Exception) {
            Timber.e(e, "Error processing image")
            _detectionState.value = DetectionState.Error(e.message ?: "Unknown error occurred")
        } finally {
            processingCount--
        }
    }

    /**
     * Toggles camera flash state.
     */
    fun toggleFlash() {
        viewModelScope.launch {
            _flashEnabled.value = !_flashEnabled.value
        }
    }

    /**
     * Switches between wildlife and fossil detection modes.
     *
     * @param mode Target camera mode
     */
    fun switchCameraMode(mode: CameraMode) {
        viewModelScope.launch {
            if (_cameraMode.value != mode) {
                // Clear current detection state
                _detectionState.value = DetectionState.Idle
                
                // Update mode
                _cameraMode.value = mode
                
                // Reset detection parameters
                lastDetectionTime = 0L
                processingCount = 0
                
                Timber.d("Switched to ${mode.name} mode")
            }
        }
    }

    /**
     * Initializes bitmap pool for memory optimization.
     */
    private fun initializeBitmapPool() {
        repeat(BITMAP_POOL_SIZE) {
            val bitmap = Bitmap.createBitmap(
                Constants.MLConstants.ML_MODEL_INPUT_SIZE,
                Constants.MLConstants.ML_MODEL_INPUT_SIZE,
                Bitmap.Config.ARGB_8888
            )
            bitmapPool.offer(bitmap)
        }
    }

    /**
     * Acquires and processes a bitmap from the pool.
     *
     * @param sourceBitmap Source bitmap to process
     * @return Processed bitmap from pool
     */
    private suspend fun acquireProcessedBitmap(sourceBitmap: Bitmap): Bitmap {
        val pooledBitmap = bitmapPool.poll() ?: createNewPoolBitmap()
        
        return ImageUtils.prepareBitmapForML(
            inputBitmap = sourceBitmap,
            targetSize = Constants.MLConstants.ML_MODEL_INPUT_SIZE,
            useHardwareAcceleration = Constants.MLConstants.SUPPORTS_HARDWARE_ACCELERATION
        ).also { processed ->
            // Copy processed bitmap to pooled bitmap
            val canvas = android.graphics.Canvas(pooledBitmap)
            canvas.drawBitmap(processed, 0f, 0f, null)
            
            // Recycle intermediate bitmap if different
            if (processed != sourceBitmap && processed != pooledBitmap) {
                processed.recycle()
            }
        }
        
        return pooledBitmap
    }

    /**
     * Creates a new bitmap for the pool.
     */
    private fun createNewPoolBitmap(): Bitmap {
        return Bitmap.createBitmap(
            Constants.MLConstants.ML_MODEL_INPUT_SIZE,
            Constants.MLConstants.ML_MODEL_INPUT_SIZE,
            Bitmap.Config.ARGB_8888
        )
    }

    /**
     * Releases a bitmap back to the pool.
     *
     * @param bitmap Bitmap to release
     */
    private fun releaseBitmap(bitmap: Bitmap) {
        if (!bitmap.isRecycled && bitmapPool.size < BITMAP_POOL_SIZE) {
            bitmap.eraseColor(android.graphics.Color.TRANSPARENT)
            bitmapPool.offer(bitmap)
        } else {
            bitmap.recycle()
        }
    }

    /**
     * Cleans up resources when ViewModel is cleared.
     */
    override fun onCleared() {
        super.onCleared()
        // Recycle all bitmaps in pool
        bitmapPool.forEach { it.recycle() }
        bitmapPool.clear()
    }
}