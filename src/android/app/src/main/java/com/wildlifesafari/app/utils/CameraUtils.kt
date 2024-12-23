package com.wildlifesafari.app.utils

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.util.Size
import androidx.annotation.RequiresPermission
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.wildlifesafari.app.utils.ImageUtils
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.util.concurrent.Executors
import kotlin.math.abs

/**
 * Utility class providing optimized camera functionality for wildlife detection.
 * Implements hardware-accelerated camera operations with memory optimization.
 *
 * @version 1.0
 * @since 2023-10-01
 */
object CameraUtils {
    // External library versions:
    // androidx.camera.core:1.2.0
    // androidx.camera.lifecycle:1.2.0
    // kotlinx.coroutines:1.7.0

    private const val TARGET_PREVIEW_WIDTH = 1920
    private const val TARGET_PREVIEW_HEIGHT = 1080
    private const val TARGET_ANALYSIS_SIZE = 640
    private const val ASPECT_RATIO_TOLERANCE = 0.1
    private const val MIN_SURFACE_SIZE = 480

    private val cameraExecutor = Executors.newSingleThreadExecutor()
    private val _cameraState = MutableStateFlow<CameraState>(CameraState.Inactive)
    val cameraState: StateFlow<CameraState> = _cameraState

    /**
     * Represents different states of camera operation
     */
    sealed class CameraState {
        object Inactive : CameraState()
        object Starting : CameraState()
        object Active : CameraState()
        data class Error(val exception: Exception) : CameraState()
    }

    /**
     * Camera configuration data class for customized setup
     */
    data class CameraConfig(
        val lensFacing: Int = CameraSelector.LENS_FACING_BACK,
        val enableHardwareAcceleration: Boolean = true,
        val analysisTargetSize: Int = TARGET_ANALYSIS_SIZE,
        val imageFormat: Int = ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888
    )

    /**
     * Sets up the camera with optimal configuration for wildlife detection.
     *
     * @param context Application context
     * @param previewView Camera preview surface
     * @param analyzer Image analysis implementation
     * @param config Camera configuration options
     * @return Configured ProcessCameraProvider instance
     * @throws SecurityException if camera permission is not granted
     */
    @SuppressLint("UnsafeOptInUsageError")
    @RequiresPermission(Manifest.permission.CAMERA)
    suspend fun setupCamera(
        context: Context,
        previewView: PreviewView,
        analyzer: ImageAnalysis.Analyzer,
        config: CameraConfig = CameraConfig()
    ): ProcessCameraProvider {
        try {
            _cameraState.value = CameraState.Starting

            val cameraProvider = ProcessCameraProvider.getInstance(context).await()
            cameraProvider.unbindAll()

            // Configure camera selector
            val cameraSelector = CameraSelector.Builder()
                .requireLensFacing(config.lensFacing)
                .build()

            // Configure preview use case
            val preview = Preview.Builder()
                .setTargetResolution(getOptimalPreviewSize(
                    context,
                    TARGET_PREVIEW_WIDTH,
                    TARGET_PREVIEW_HEIGHT
                ))
                .build()
                .also { it.setSurfaceProvider(previewView.surfaceProvider) }

            // Configure image analysis use case
            val imageAnalysis = ImageAnalysis.Builder()
                .setTargetResolution(Size(config.analysisTargetSize, config.analysisTargetSize))
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setOutputImageFormat(config.imageFormat)
                .setOutputImageRotationEnabled(true)
                .apply {
                    if (config.enableHardwareAcceleration) {
                        setBackgroundExecutor(cameraExecutor)
                    }
                }
                .build()
                .also { it.setAnalyzer(cameraExecutor, analyzer) }

            // Bind use cases to lifecycle
            val owner = context as LifecycleOwner
            cameraProvider.bindToLifecycle(
                owner,
                cameraSelector,
                preview,
                imageAnalysis
            )

            _cameraState.value = CameraState.Active
            return cameraProvider

        } catch (e: Exception) {
            _cameraState.value = CameraState.Error(e)
            throw IllegalStateException("Failed to setup camera", e)
        }
    }

    /**
     * Determines the optimal preview size based on device capabilities and target dimensions.
     *
     * @param context Application context
     * @param targetWidth Desired preview width
     * @param targetHeight Desired preview height
     * @return Optimal Size for preview
     */
    private fun getOptimalPreviewSize(
        context: Context,
        targetWidth: Int,
        targetHeight: Int
    ): Size {
        val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val targetRatio = targetWidth.toFloat() / targetHeight

        return cameraManager.cameraIdList.firstOrNull()?.let { cameraId ->
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            val streamConfigMap = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            
            streamConfigMap?.getOutputSizes(SurfaceTexture::class.java)
                ?.filter { it.width >= MIN_SURFACE_SIZE && it.height >= MIN_SURFACE_SIZE }
                ?.minByOrNull { size ->
                    val ratio = size.width.toFloat() / size.height
                    val ratioDiff = abs(ratio - targetRatio)
                    val resolutionDiff = abs(size.width * size.height - targetWidth * targetHeight)
                    ratioDiff * resolutionDiff
                }
        } ?: Size(targetWidth, targetHeight)
    }

    /**
     * Detects hardware acceleration capabilities of the device.
     *
     * @param context Application context
     * @return true if hardware acceleration is supported
     */
    private fun detectHardwareCapabilities(context: Context): Boolean {
        return try {
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            cameraManager.cameraIdList.any { cameraId ->
                val characteristics = cameraManager.getCameraCharacteristics(cameraId)
                characteristics.get(CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL) ==
                    CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_3
            }
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Cleans up camera resources and executors.
     */
    fun cleanupResources() {
        try {
            cameraExecutor.shutdown()
            _cameraState.value = CameraState.Inactive
        } catch (e: Exception) {
            _cameraState.value = CameraState.Error(e)
        }
    }

    /**
     * Extension function to check if a Size is within aspect ratio tolerance.
     */
    private fun Size.isWithinAspectRatioTolerance(targetRatio: Float): Boolean {
        val ratio = width.toFloat() / height
        return abs(ratio - targetRatio) <= ASPECT_RATIO_TOLERANCE
    }
}