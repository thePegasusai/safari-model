package com.wildlifesafari.app.ui.fossil

import android.Manifest
import android.annotation.SuppressLint
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.os.Bundle
import android.view.View
import android.view.accessibility.AccessibilityEvent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView // version: 1.2.0
import androidx.core.content.ContextCompat
import androidx.fragment.app.Fragment
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.bumptech.glide.load.engine.bitmap_recycle.BitmapPool // version: 4.15.1
import com.bumptech.glide.load.engine.bitmap_recycle.LruBitmapPool
import com.google.android.material.snackbar.Snackbar
import com.wildlifesafari.app.R
import com.wildlifesafari.app.ui.common.BaseFragment
import com.wildlifesafari.app.utils.Constants.MLConstants
import com.wildlifesafari.app.utils.ImageUtils
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import timber.log.Timber // version: 5.0.1
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import javax.inject.Inject
import kotlin.math.roundToInt

/**
 * Fragment responsible for handling fossil scanning functionality using device camera.
 * Implements real-time 3D fossil detection with optimized performance and accessibility support.
 *
 * Features:
 * - Real-time LNN-powered fossil detection
 * - Hardware-accelerated camera preview
 * - Memory-efficient bitmap processing
 * - Performance monitoring and optimization
 * - WCAG 2.1 AA compliant accessibility
 */
@AndroidEntryPoint
class FossilScanFragment : BaseFragment(R.layout.fragment_fossil_scan) {

    @Inject
    lateinit var viewModel: FossilScanViewModel

    private lateinit var cameraPreview: PreviewView
    private var cameraProvider: ProcessCameraProvider? = null
    private lateinit var bitmapPool: BitmapPool
    private lateinit var cameraExecutor: ExecutorService
    private var imageCapture: ImageCapture? = null
    private var imageAnalyzer: ImageAnalysis? = null

    companion object {
        private const val TAG = "FossilScanFragment"
        private const val RATIO_4_3_VALUE = 4.0 / 3.0
        private const val RATIO_16_9_VALUE = 16.0 / 9.0
        private const val BITMAP_POOL_SIZE_BYTES = 1024 * 1024 * 30 // 30MB

        fun newInstance() = FossilScanFragment()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        initializeBitmapPool()
        initializeCameraExecutor()
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        
        cameraPreview = view.findViewById(R.id.camera_preview)
        setupAccessibility()
        setupCameraPermissions()
        setupStateObservers()
        setupPerformanceMonitoring()
    }

    private fun initializeBitmapPool() {
        bitmapPool = LruBitmapPool(BITMAP_POOL_SIZE_BYTES)
    }

    private fun initializeCameraExecutor() {
        cameraExecutor = Executors.newSingleThreadExecutor()
    }

    private fun setupAccessibility() {
        cameraPreview.apply {
            contentDescription = getString(R.string.fossil_camera_preview_description)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
    }

    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        if (isGranted) {
            setupCamera()
        } else {
            showPermissionError()
        }
    }

    private fun setupCameraPermissions() {
        when {
            ContextCompat.checkSelfPermission(
                requireContext(),
                Manifest.permission.CAMERA
            ) == PackageManager.PERMISSION_GRANTED -> {
                setupCamera()
            }
            shouldShowRequestPermissionRationale(Manifest.permission.CAMERA) -> {
                showPermissionRationale()
            }
            else -> {
                requestPermissionLauncher.launch(Manifest.permission.CAMERA)
            }
        }
    }

    @SuppressLint("UnsafeOptInUsageError")
    private fun setupCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(requireContext())
        
        cameraProviderFuture.addListener({
            cameraProvider = cameraProviderFuture.get()
            
            val preview = Preview.Builder()
                .setTargetAspectRatio(aspectRatio())
                .build()
                .also {
                    it.setSurfaceProvider(cameraPreview.surfaceProvider)
                }

            imageCapture = ImageCapture.Builder()
                .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                .setTargetAspectRatio(aspectRatio())
                .build()

            imageAnalyzer = ImageAnalysis.Builder()
                .setTargetAspectRatio(aspectRatio())
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
                .also {
                    it.setAnalyzer(cameraExecutor) { imageProxy ->
                        processImage(imageProxy)
                    }
                }

            try {
                cameraProvider?.unbindAll()
                cameraProvider?.bindToLifecycle(
                    viewLifecycleOwner,
                    CameraSelector.DEFAULT_BACK_CAMERA,
                    preview,
                    imageCapture,
                    imageAnalyzer
                )
            } catch (e: Exception) {
                Timber.e(e, "Camera binding failed")
                showError(getString(R.string.camera_setup_error))
            }
        }, ContextCompat.getMainExecutor(requireContext()))
    }

    private fun setupStateObservers() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                launch {
                    viewModel.currentFossil.collectLatest { fossil ->
                        fossil?.let {
                            announceForAccessibility(
                                view!!,
                                getString(R.string.fossil_detected, it.speciesName)
                            )
                            showFossilDetails(it)
                        }
                    }
                }

                launch {
                    viewModel.processingMetrics.collectLatest { metrics ->
                        updatePerformanceIndicators(metrics)
                    }
                }
            }
        }
    }

    private fun processImage(imageProxy: ImageProxy) {
        try {
            val bitmap = ImageUtils.convertImageProxyToBitmap(
                imageProxy,
                MLConstants.SUPPORTS_HARDWARE_ACCELERATION
            )
            
            viewModel.scanFossil(
                bitmap,
                getLastLocation()?.latitude ?: 0.0,
                getLastLocation()?.longitude ?: 0.0
            )
            
            bitmapPool.put(bitmap)
        } catch (e: Exception) {
            Timber.e(e, "Image processing failed")
        } finally {
            imageProxy.close()
        }
    }

    private fun aspectRatio(): Int {
        val width = cameraPreview.width.toDouble()
        val height = cameraPreview.height.toDouble()
        val ratio = width / height

        return when {
            kotlin.math.abs(ratio - RATIO_4_3_VALUE) <= kotlin.math.abs(ratio - RATIO_16_9_VALUE) ->
                AspectRatio.RATIO_4_3
            else -> AspectRatio.RATIO_16_9
        }
    }

    private fun showFossilDetails(discovery: DiscoveryModel) {
        // Implementation for showing fossil details UI
        // This would be implemented based on the UI design specifications
    }

    private fun updatePerformanceIndicators(metrics: FossilScanViewModel.ProcessingMetrics) {
        if (!metrics.isPerformanceOptimal) {
            Timber.w("Sub-optimal processing performance: ${metrics.processingTimeMs}ms")
            // Implement performance optimization strategies
        }
    }

    private fun setupPerformanceMonitoring() {
        lifecycleScope.launch {
            viewModel.processingMetrics.collectLatest { metrics ->
                if (metrics.processingTimeMs > MLConstants.INFERENCE_TIMEOUT_MS) {
                    Timber.w("Processing time exceeded threshold: ${metrics.processingTimeMs}ms")
                }
            }
        }
    }

    override fun getScreenTitle(): String = getString(R.string.fossil_scan_screen_title)

    override fun getFirstFocusableElementId(): Int = R.id.camera_preview

    private fun showPermissionError() {
        Snackbar.make(
            requireView(),
            getString(R.string.camera_permission_required),
            Snackbar.LENGTH_INDEFINITE
        ).setAction(getString(R.string.settings)) {
            openAppSettings()
        }.show()
    }

    private fun showPermissionRationale() {
        Snackbar.make(
            requireView(),
            getString(R.string.camera_permission_rationale),
            Snackbar.LENGTH_LONG
        ).setAction(getString(R.string.grant)) {
            requestPermissionLauncher.launch(Manifest.permission.CAMERA)
        }.show()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        cameraProvider?.unbindAll()
    }

    override fun onDestroy() {
        super.onDestroy()
        cameraExecutor.shutdown()
        bitmapPool.clearMemory()
    }
}