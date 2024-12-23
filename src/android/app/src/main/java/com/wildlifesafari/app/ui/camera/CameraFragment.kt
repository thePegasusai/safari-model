package com.wildlifesafari.app.ui.camera

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.View
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.wildlifesafari.app.R
import com.wildlifesafari.app.ui.common.BaseFragment
import com.wildlifesafari.app.utils.CameraUtils
import com.wildlifesafari.app.utils.Constants
import com.wildlifesafari.app.utils.ImageUtils
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import javax.inject.Inject
import android.graphics.Bitmap
import android.graphics.BitmapPool
import android.hardware.HardwareBuffer
import android.location.Location
import android.location.LocationManager
import androidx.core.view.isVisible
import com.google.android.material.button.MaterialButton
import com.google.android.material.chip.Chip
import com.google.android.material.floatingactionbutton.FloatingActionButton
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.wildlifesafari.app.domain.models.SpeciesModel

/**
 * Fragment responsible for camera interface and real-time species detection using LNN.
 * Implements hardware-accelerated processing and WCAG 2.1 AA compliant accessibility.
 */
@AndroidEntryPoint
class CameraFragment : BaseFragment(R.layout.fragment_camera) {

    @Inject
    lateinit var viewModel: CameraViewModel

    private lateinit var previewView: PreviewView
    private lateinit var captureButton: FloatingActionButton
    private lateinit var flashButton: MaterialButton
    private lateinit var modeToggle: Chip
    private lateinit var bottomSheet: View
    private lateinit var bottomSheetBehavior: BottomSheetBehavior<View>
    
    private var bitmapPool: BitmapPool? = null
    private var hardwareAccelerator: HardwareBuffer? = null
    private lateinit var accessibilityManager: AccessibilityManager
    private var lastLocation: Location? = null

    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        if (isGranted) {
            setupCamera()
        } else {
            handleError(getString(R.string.camera_permission_denied))
        }
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        
        initializeViews(view)
        setupAccessibility()
        checkCameraPermission()
        initializeHardwareAcceleration()
        setupObservers()
        setupClickListeners()
    }

    private fun initializeViews(view: View) {
        previewView = view.findViewById(R.id.camera_preview)
        captureButton = view.findViewById(R.id.capture_button)
        flashButton = view.findViewById(R.id.flash_button)
        modeToggle = view.findViewById(R.id.mode_toggle)
        bottomSheet = view.findViewById(R.id.bottom_sheet)
        
        bottomSheetBehavior = BottomSheetBehavior.from(bottomSheet)
        bottomSheetBehavior.state = BottomSheetBehavior.STATE_HIDDEN
    }

    private fun setupAccessibility() {
        accessibilityManager = requireContext().getSystemService(AccessibilityManager::class.java)
        
        captureButton.apply {
            contentDescription = getString(R.string.capture_button_description)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
        }

        modeToggle.apply {
            contentDescription = getString(R.string.mode_toggle_description)
            isClickable = true
            isFocusable = true
        }
    }

    private fun checkCameraPermission() {
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

    private fun initializeHardwareAcceleration() {
        if (Constants.MLConstants.SUPPORTS_HARDWARE_ACCELERATION) {
            bitmapPool = CameraUtils.setupBitmapPool(
                width = Constants.ML_MODEL_INPUT_SIZE,
                height = Constants.ML_MODEL_INPUT_SIZE
            )
            hardwareAccelerator = CameraUtils.configureHardwareAcceleration()
        }
    }

    private fun setupCamera() {
        lifecycleScope.launch {
            try {
                val config = CameraUtils.CameraConfig(
                    enableHardwareAcceleration = Constants.MLConstants.SUPPORTS_HARDWARE_ACCELERATION,
                    analysisTargetSize = Constants.ML_MODEL_INPUT_SIZE
                )

                CameraUtils.setupCamera(
                    context = requireContext(),
                    previewView = previewView,
                    analyzer = createImageAnalyzer(),
                    config = config
                )

                announceForAccessibility(getString(R.string.camera_ready))
            } catch (e: Exception) {
                handleError(getString(R.string.camera_setup_error))
            }
        }
    }

    private fun createImageAnalyzer(): ImageAnalysis.Analyzer {
        return ImageAnalysis.Analyzer { imageProxy ->
            processImage(imageProxy)
        }
    }

    private fun processImage(imageProxy: ImageProxy) {
        lifecycleScope.launch {
            try {
                val bitmap = ImageUtils.convertImageProxyToBitmap(
                    imageProxy,
                    Constants.MLConstants.SUPPORTS_HARDWARE_ACCELERATION
                )

                lastLocation?.let { location ->
                    viewModel.processImage(
                        bitmap,
                        location.latitude,
                        location.longitude
                    )
                }
            } finally {
                imageProxy.close()
            }
        }
    }

    private fun setupObservers() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                launch {
                    viewModel.detectionState.collectLatest { state ->
                        handleDetectionState(state)
                    }
                }

                launch {
                    viewModel.flashEnabled.collectLatest { enabled ->
                        updateFlashState(enabled)
                    }
                }

                launch {
                    viewModel.cameraMode.collectLatest { mode ->
                        updateCameraMode(mode)
                    }
                }
            }
        }
    }

    private fun handleDetectionState(state: CameraViewModel.DetectionState) {
        when (state) {
            is CameraViewModel.DetectionState.Processing -> {
                showLoading()
                announceForAccessibility(getString(R.string.processing_image))
            }
            is CameraViewModel.DetectionState.Success -> {
                hideLoading()
                showDetectionResult(state.species)
            }
            is CameraViewModel.DetectionState.Error -> {
                hideLoading()
                handleError(state.message)
            }
            is CameraViewModel.DetectionState.Idle -> {
                hideLoading()
                bottomSheetBehavior.state = BottomSheetBehavior.STATE_HIDDEN
            }
        }
    }

    private fun showDetectionResult(species: SpeciesModel) {
        bottomSheetBehavior.state = BottomSheetBehavior.STATE_EXPANDED
        
        val announcement = getString(
            R.string.species_detected,
            species.commonName,
            species.detectionConfidence * 100
        )
        announceForAccessibility(announcement)
    }

    private fun setupClickListeners() {
        captureButton.setOnClickListener {
            viewModel.processImage(
                ImageUtils.convertImageProxyToBitmap(
                    previewView.bitmap ?: return@setOnClickListener,
                    Constants.MLConstants.SUPPORTS_HARDWARE_ACCELERATION
                ),
                lastLocation?.latitude ?: 0.0,
                lastLocation?.longitude ?: 0.0
            )
        }

        flashButton.setOnClickListener {
            viewModel.toggleFlash()
        }

        modeToggle.setOnClickListener {
            viewModel.switchCameraMode(
                if (viewModel.cameraMode.value == CameraViewModel.CameraMode.WILDLIFE)
                    CameraViewModel.CameraMode.FOSSIL
                else CameraViewModel.CameraMode.WILDLIFE
            )
        }
    }

    override fun getScreenTitle(): String = getString(R.string.camera_screen_title)

    override fun getFirstFocusableElementId(): Int = R.id.camera_preview

    override fun onDestroyView() {
        super.onDestroyView()
        bitmapPool?.let { CameraUtils.releaseBitmapPool(it) }
        hardwareAccelerator?.close()
        CameraUtils.cleanupResources()
    }

    companion object {
        fun newInstance() = CameraFragment()
    }
}