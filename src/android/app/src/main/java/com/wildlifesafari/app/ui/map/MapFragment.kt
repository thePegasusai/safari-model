package com.wildlifesafari.app.ui.map

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.google.android.gms.maps.CameraUpdateFactory // version: 18.1.0
import com.google.android.gms.maps.GoogleMap
import com.google.android.gms.maps.MapView
import com.google.android.gms.maps.model.LatLngBounds
import com.google.android.gms.maps.model.MapStyleOptions
import com.google.maps.android.clustering.ClusterManager // version: 2.0.0
import com.google.maps.android.clustering.algo.NonHierarchicalDistanceBasedAlgorithm
import com.wildlifesafari.app.R
import com.wildlifesafari.app.ui.common.BaseFragment
import com.wildlifesafari.app.utils.LocationUtils
import com.wildlifesafari.app.data.model.DiscoveryModel
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import timber.log.Timber // version: 5.0.1
import javax.inject.Inject

/**
 * Fragment responsible for displaying and managing the interactive map view showing wildlife 
 * discoveries and fossil locations. Implements battery-optimized location tracking and 
 * marker clustering for optimal performance.
 */
@AndroidEntryPoint
class MapFragment : BaseFragment(R.layout.fragment_map) {

    @Inject
    lateinit var viewModel: MapViewModel

    private lateinit var mapView: MapView
    private var googleMap: GoogleMap? = null
    private var clusterManager: ClusterManager<DiscoveryModel>? = null
    private var isMapInitialized = false
    private var isOfflineMode = false

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        return super.onCreateView(inflater, container, savedInstanceState)?.also { view ->
            mapView = view.findViewById(R.id.map_view)
            mapView.onCreate(savedInstanceState)
            initializeMap()
        }
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        setupObservers()
        setupMapControls()
        checkOfflineAvailability()
    }

    private fun initializeMap() {
        mapView.getMapAsync { map ->
            googleMap = map.apply {
                // Apply custom map styling
                setMapStyle(MapStyleOptions.loadRawResourceStyle(requireContext(), R.raw.map_style))
                
                // Configure map settings
                uiSettings.apply {
                    isCompassEnabled = true
                    isMyLocationButtonEnabled = true
                    isMapToolbarEnabled = true
                    isZoomControlsEnabled = true
                }

                // Setup clustering
                setupClusterManager()
                
                // Initialize map camera position
                moveCamera(CameraUpdateFactory.newLatLngZoom(
                    DEFAULT_MAP_CENTER,
                    DEFAULT_ZOOM_LEVEL
                ))
            }
            isMapInitialized = true
            loadMapContent()
        }
    }

    private fun setupClusterManager() {
        googleMap?.let { map ->
            clusterManager = ClusterManager<DiscoveryModel>(requireContext(), map).apply {
                // Configure clustering algorithm
                algorithm = NonHierarchicalDistanceBasedAlgorithm<DiscoveryModel>().apply {
                    maxDistanceBetweenClusteredItems = CLUSTER_DISTANCE_PIXELS
                }

                // Setup custom renderers
                renderer = CustomClusterRenderer(
                    requireContext(),
                    map,
                    this,
                    isOfflineMode
                )

                // Setup cluster click listeners
                setOnClusterClickListener { cluster ->
                    val bounds = LatLngBounds.builder().apply {
                        cluster.items.forEach { include(it.toLatLng()) }
                    }.build()
                    map.animateCamera(CameraUpdateFactory.newLatLngBounds(
                        bounds,
                        CLUSTER_PADDING
                    ))
                    true
                }

                // Setup individual marker click listeners
                setOnClusterItemClickListener { discovery ->
                    showDiscoveryDetails(discovery)
                    true
                }
            }

            // Set cluster manager as map listeners
            map.setOnCameraIdleListener(clusterManager)
            map.setOnMarkerClickListener(clusterManager)
        }
    }

    private fun setupObservers() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                // Observe discoveries
                launch {
                    viewModel.discoveries.collectLatest { discoveries ->
                        updateMapMarkers(discoveries)
                    }
                }

                // Observe location updates
                launch {
                    viewModel.currentLocation.collectLatest { location ->
                        location?.let { updateUserLocation(it) }
                    }
                }

                // Observe tracking mode
                launch {
                    viewModel.trackingMode.collectLatest { mode ->
                        updateTrackingMode(mode)
                    }
                }
            }
        }
    }

    private fun updateMapMarkers(discoveries: List<DiscoveryModel>) {
        if (!isMapInitialized) return

        clusterManager?.apply {
            clearItems()
            addItems(discoveries)
            cluster()
        }
    }

    private fun updateUserLocation(location: LocationData) {
        googleMap?.let { map ->
            if (LocationUtils.isLocationEnabled(requireContext())) {
                map.isMyLocationEnabled = true
                if (shouldFollowUser) {
                    map.animateCamera(CameraUpdateFactory.newLatLngZoom(
                        location.toLatLng(),
                        FOLLOW_USER_ZOOM_LEVEL
                    ))
                }
            }
        }
    }

    private fun updateTrackingMode(mode: MapViewModel.TrackingMode) {
        when (mode) {
            MapViewModel.TrackingMode.BATTERY_SAVING -> {
                // Reduce map updates and location tracking frequency
                googleMap?.setMaxZoomPreference(BATTERY_SAVING_MAX_ZOOM)
                clusterManager?.algorithm?.maxDistanceBetweenClusteredItems = 
                    BATTERY_SAVING_CLUSTER_DISTANCE
            }
            MapViewModel.TrackingMode.BALANCED -> {
                // Default map settings
                googleMap?.resetMinMaxZoomPreference()
                clusterManager?.algorithm?.maxDistanceBetweenClusteredItems = 
                    CLUSTER_DISTANCE_PIXELS
            }
            MapViewModel.TrackingMode.HIGH_ACCURACY -> {
                // Enable high accuracy tracking and frequent updates
                googleMap?.setMinZoomPreference(HIGH_ACCURACY_MIN_ZOOM)
                clusterManager?.algorithm?.maxDistanceBetweenClusteredItems = 
                    HIGH_ACCURACY_CLUSTER_DISTANCE
            }
        }
    }

    private fun checkOfflineAvailability() {
        viewLifecycleOwner.lifecycleScope.launch {
            try {
                // Check offline map data availability
                isOfflineMode = !LocationUtils.isLocationEnabled(requireContext())
                if (isOfflineMode) {
                    showOfflineModeIndicator()
                }
            } catch (e: Exception) {
                Timber.e(e, "Error checking offline availability")
                handleError(getString(R.string.error_offline_check))
            }
        }
    }

    override fun getScreenTitle(): String = getString(R.string.map_screen_title)

    override fun getFirstFocusableElementId(): Int = R.id.map_view

    override fun onStart() {
        super.onStart()
        mapView.onStart()
    }

    override fun onResume() {
        super.onResume()
        mapView.onResume()
    }

    override fun onPause() {
        mapView.onPause()
        super.onPause()
    }

    override fun onStop() {
        mapView.onStop()
        super.onStop()
    }

    override fun onDestroy() {
        mapView.onDestroy()
        super.onDestroy()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        mapView.onSaveInstanceState(outState)
    }

    override fun onLowMemory() {
        super.onLowMemory()
        mapView.onLowMemory()
    }

    companion object {
        private const val DEFAULT_ZOOM_LEVEL = 12f
        private const val FOLLOW_USER_ZOOM_LEVEL = 15f
        private const val CLUSTER_DISTANCE_PIXELS = 100
        private const val CLUSTER_PADDING = 50
        private const val BATTERY_SAVING_MAX_ZOOM = 16f
        private const val HIGH_ACCURACY_MIN_ZOOM = 14f
        private const val BATTERY_SAVING_CLUSTER_DISTANCE = 150
        private const val HIGH_ACCURACY_CLUSTER_DISTANCE = 75
        private val DEFAULT_MAP_CENTER = com.google.android.gms.maps.model.LatLng(0.0, 0.0)
        private var shouldFollowUser = true
    }
}