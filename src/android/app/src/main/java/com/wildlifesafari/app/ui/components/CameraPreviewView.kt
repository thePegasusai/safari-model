package com.wildlifesafari.app.ui.components

import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import androidx.camera.core.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.wildlifesafari.app.utils.CameraUtils
import com.wildlifesafari.app.utils.ImageUtils
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

/**
 * Advanced camera preview component with hardware acceleration and performance optimization.
 * Implements real-time species detection with sub-100ms latency target.
 *
 * @version 1.0
 * @since 2023-10-01
 */
@Composable
fun CameraPreview(
    modifier: Modifier = Modifier,
    viewModel: CameraViewModel,
    enableTorch: Boolean = false,
    enableHardwareAcceleration: Boolean = true
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val coroutineScope = rememberCoroutineScope()

    // Camera state management
    var cameraProvider by remember { mutableStateOf<ProcessCameraProvider?>(null) }
    var previewView by remember { mutableStateOf<PreviewView?>(null) }

    // Error handling state
    var errorState by remember { mutableStateOf<String?>(null) }

    // Lifecycle observer for proper cleanup
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_DESTROY -> {
                    cameraProvider?.unbindAll()
                    CameraUtils.cleanupResources()
                }
                else -> { /* Handle other lifecycle events if needed */ }
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    // Camera state flow collector
    LaunchedEffect(Unit) {
        CameraUtils.cameraState.collectLatest { state ->
            when (state) {
                is CameraUtils.CameraState.Error -> {
                    errorState = state.exception.message
                    Log.e("CameraPreview", "Camera error", state.exception)
                }
                else -> errorState = null
            }
        }
    }

    // Main camera preview composable
    Box(modifier = modifier.fillMaxSize()) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx ->
                PreviewView(ctx).apply {
                    implementationMode = if (enableHardwareAcceleration) {
                        PreviewView.ImplementationMode.PERFORMANCE
                    } else {
                        PreviewView.ImplementationMode.COMPATIBLE
                    }
                    previewView = this
                    setupCamera(ctx, viewModel, enableTorch, enableHardwareAcceleration)
                }
            },
            update = { view ->
                // Update camera configuration when props change
                updateCameraConfig(
                    view.context,
                    viewModel,
                    enableTorch,
                    enableHardwareAcceleration
                )
            }
        )

        // Error overlay if needed
        errorState?.let { error ->
            ErrorOverlay(error = error) {
                coroutineScope.launch {
                    retryCamera(context, viewModel, enableTorch, enableHardwareAcceleration)
                }
            }
        }
    }
}

/**
 * Sets up the camera with optimal configuration for wildlife detection.
 */
private suspend fun setupCamera(
    context: Context,
    viewModel: CameraViewModel,
    enableTorch: Boolean,
    enableHardwareAcceleration: Boolean
) {
    try {
        val config = CameraUtils.CameraConfig(
            enableHardwareAcceleration = enableHardwareAcceleration,
            analysisTargetSize = 640 // Optimal size for ML processing
        )

        CameraUtils.setupCamera(
            context = context,
            previewView = previewView!!,
            analyzer = { imageProxy ->
                processFrame(imageProxy, viewModel, enableHardwareAcceleration)
            },
            config = config
        ).also { provider ->
            provider.cameraInfo?.torchState?.value = enableTorch
        }
    } catch (e: Exception) {
        Log.e("CameraPreview", "Failed to setup camera", e)
        throw e
    }
}

/**
 * Processes camera frames with hardware acceleration when available.
 */
private fun processFrame(
    imageProxy: ImageProxy,
    viewModel: CameraViewModel,
    enableHardwareAcceleration: Boolean
) {
    try {
        val bitmap = ImageUtils.convertImageProxyToBitmap(
            imageProxy,
            enableHardwareAcceleration
        )

        viewModel.processFrame(bitmap)
    } catch (e: Exception) {
        Log.e("CameraPreview", "Frame processing error", e)
    } finally {
        imageProxy.close()
    }
}

/**
 * Updates camera configuration when properties change.
 */
private fun updateCameraConfig(
    context: Context,
    viewModel: CameraViewModel,
    enableTorch: Boolean,
    enableHardwareAcceleration: Boolean
) {
    try {
        previewView?.let { preview ->
            preview.implementationMode = if (enableHardwareAcceleration) {
                PreviewView.ImplementationMode.PERFORMANCE
            } else {
                PreviewView.ImplementationMode.COMPATIBLE
            }
        }

        cameraProvider?.cameraInfo?.torchState?.value = enableTorch
    } catch (e: Exception) {
        Log.e("CameraPreview", "Failed to update camera config", e)
    }
}

/**
 * Retries camera setup after error.
 */
private suspend fun retryCamera(
    context: Context,
    viewModel: CameraViewModel,
    enableTorch: Boolean,
    enableHardwareAcceleration: Boolean
) {
    try {
        cameraProvider?.unbindAll()
        setupCamera(context, viewModel, enableTorch, enableHardwareAcceleration)
    } catch (e: Exception) {
        Log.e("CameraPreview", "Retry failed", e)
    }
}

/**
 * Error overlay composable for camera errors.
 */
@Composable
private fun ErrorOverlay(
    error: String,
    onRetry: () -> Unit
) {
    // Implementation of error overlay UI
    // This would show error message and retry button
}

companion object {
    private const val TAG = "CameraPreview"
}