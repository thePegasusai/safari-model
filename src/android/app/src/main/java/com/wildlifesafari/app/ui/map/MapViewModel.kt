package com.wildlifesafari.app.ui.map

import androidx.lifecycle.viewModelScope
import com.google.android.gms.location.GeofencingClient // version: 21.0.1
import com.google.android.gms.maps.model.LatLngBounds
import com.wildlifesafari.app.ui.common.BaseViewModel
import com.wildlifesafari.app.utils.LocationTracker
import com.wildlifesafari.app.utils.Constants
import com.wildlifesafari.app.data.model.DiscoveryModel
import com.wildlifesafari.app.data.model.LocationData
import com.wildlifesafari.app.data.repository.DiscoveryRepository
import com.wildlifesafari.app.utils.calculateDistance
import javax.inject.Inject
import kotlinx.coroutines.flow.* // version: 1.7.3
import kotlinx.coroutines.launch
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import java.util.*
import java.util.concurrent.TimeUnit
import timber.log.Timber // version: 5.0.1

/**
 * Enhanced ViewModel managing map-related data and user interactions with battery-optimized location tracking.
 * Implements efficient discovery management and caching for optimal performance.
 *
 * @property discoveryRepository Repository for managing wildlife discoveries
 * @property locationTracker Battery-optimized location tracking utility
 * @property geofencingClient Google's geofencing client for region monitoring
 */
class MapViewModel @Inject constructor(
    private val discoveryRepository: DiscoveryRepository,
    private val locationTracker: LocationTracker,
    private val geofencingClient: GeofencingClient
) : BaseViewModel() {

    // State management for discoveries
    private val _discoveries = MutableStateFlow<List<DiscoveryModel>>(emptyList())
    val discoveries: StateFlow<List<DiscoveryModel>> = _discoveries.asStateFlow()

    // Location tracking states
    private val _currentLocation = MutableStateFlow<LocationData?>(null)
    val currentLocation: StateFlow<LocationData?> = _currentLocation.asStateFlow()

    private val _isTrackingEnabled = MutableStateFlow(false)
    val isTrackingEnabled: StateFlow<Boolean> = _isTrackingEnabled.asStateFlow()

    private val _trackingMode = MutableStateFlow(TrackingMode.BALANCED)
    val trackingMode: StateFlow<TrackingMode> = _trackingMode.asStateFlow()

    // Cache configuration
    private val discoveryCache = LruCache<String, CachedDiscoveries>(
        maxSize = Constants.CacheConstants.getOptimalCacheSize().toInt()
    )

    private var locationUpdateJob: Job? = null
    private var discoveryUpdateJob: Job? = null

    init {
        setupLocationTracking()
        initializeGeofencing()
    }

    /**
     * Loads and caches discoveries with offline support
     * @param collectionId Collection identifier
     * @param forceRefresh Force data refresh flag
     * @return Flow of discovery results
     */
    fun loadDiscoveries(collectionId: UUID, forceRefresh: Boolean = false) = launchDataLoad {
        val cacheKey = "discoveries_$collectionId"
        val cachedData = discoveryCache.get(cacheKey)

        if (!forceRefresh && cachedData?.isValid() == true) {
            _discoveries.value = cachedData.discoveries
            return@launchDataLoad
        }

        try {
            discoveryRepository.getDiscoveries(collectionId)
                .catch { e ->
                    Timber.e(e, "Error loading discoveries")
                    cachedData?.let { _discoveries.value = it.discoveries }
                    throw e
                }
                .collect { discoveries ->
                    _discoveries.value = discoveries
                    discoveryCache.put(cacheKey, CachedDiscoveries(discoveries))
                }
        } catch (e: Exception) {
            handleError(e)
        }
    }

    /**
     * Starts battery-optimized location tracking
     * @param mode Tracking mode for battery optimization
     */
    fun startLocationTracking(mode: TrackingMode = TrackingMode.BALANCED) {
        locationUpdateJob?.cancel()
        locationUpdateJob = viewModelScope.launch {
            _trackingMode.value = mode
            _isTrackingEnabled.value = true

            val updateInterval = when (mode) {
                TrackingMode.HIGH_ACCURACY -> Constants.LOCATION_FASTEST_INTERVAL_MS
                TrackingMode.BALANCED -> Constants.LOCATION_UPDATE_INTERVAL_MS
                TrackingMode.BATTERY_SAVING -> Constants.LOCATION_UPDATE_INTERVAL_MS * 2
            }

            locationTracker.startTracking(
                accuracy = mode.toPriority(),
                interval = updateInterval
            ).catch { e ->
                Timber.e(e, "Location tracking error")
                handleError(e)
            }.collect { location ->
                _currentLocation.value = LocationData(
                    latitude = location.latitude,
                    longitude = location.longitude,
                    accuracy = location.accuracy,
                    timestamp = location.time
                )
                updateNearbyDiscoveries()
            }
        }
    }

    /**
     * Stops location tracking and releases resources
     */
    fun stopLocationTracking() {
        locationUpdateJob?.cancel()
        _isTrackingEnabled.value = false
        locationTracker.stopTracking()
    }

    /**
     * Efficiently filters discoveries within map bounds
     * @param bounds Map viewport bounds
     * @return Flow of filtered discoveries
     */
    fun getDiscoveriesInRegion(bounds: LatLngBounds): Flow<List<DiscoveryModel>> = flow {
        discoveries.value.filter { discovery ->
            bounds.contains(discovery.toLatLng()) &&
                    isDiscoveryRelevant(discovery)
        }.sortedBy { discovery ->
            currentLocation.value?.let { location ->
                calculateDistance(
                    location.toAndroidLocation(),
                    discovery.toAndroidLocation()
                ).getOrNull()
            } ?: 0f
        }.take(Constants.MLConstants.MAX_DETECTIONS)
        .let { emit(it) }
    }.flowOn(viewModelScope.coroutineContext)

    /**
     * Updates tracking mode based on battery level and activity
     * @param mode New tracking mode
     */
    fun updateTrackingMode(mode: TrackingMode) {
        if (_trackingMode.value != mode) {
            _trackingMode.value = mode
            if (_isTrackingEnabled.value) {
                startLocationTracking(mode)
            }
        }
    }

    private fun setupLocationTracking() {
        viewModelScope.launch {
            locationTracker.locationUpdates
                .catch { e -> handleError(e) }
                .collect { location ->
                    _currentLocation.value = location?.toLocationData()
                }
        }
    }

    private fun initializeGeofencing() {
        viewModelScope.launch {
            try {
                // Setup geofencing for battery optimization
                discoveries.collect { discoveries ->
                    // Implementation of geofencing setup
                }
            } catch (e: Exception) {
                Timber.e(e, "Geofencing initialization error")
            }
        }
    }

    private fun updateNearbyDiscoveries() {
        discoveryUpdateJob?.cancel()
        discoveryUpdateJob = viewModelScope.launch {
            delay(Constants.LOCATION_UPDATE_INTERVAL_MS)
            currentLocation.value?.let { location ->
                // Update nearby discoveries based on current location
            }
        }
    }

    private fun isDiscoveryRelevant(discovery: DiscoveryModel): Boolean {
        val age = System.currentTimeMillis() - discovery.timestamp
        return age <= TimeUnit.DAYS.toMillis(Constants.REGION_DATA_RETENTION_DAYS)
    }

    override fun onCleared() {
        super.onCleared()
        stopLocationTracking()
        discoveryCache.evictAll()
    }

    private data class CachedDiscoveries(
        val discoveries: List<DiscoveryModel>,
        val timestamp: Long = System.currentTimeMillis()
    ) {
        fun isValid(): Boolean = 
            System.currentTimeMillis() - timestamp < TimeUnit.HOURS.toMillis(
                Constants.CacheConstants.CACHE_EXPIRY_HOURS
            )
    }

    enum class TrackingMode {
        HIGH_ACCURACY,
        BALANCED,
        BATTERY_SAVING;

        fun toPriority(): Int = when (this) {
            HIGH_ACCURACY -> Priority.PRIORITY_HIGH_ACCURACY
            BALANCED -> Priority.PRIORITY_BALANCED_POWER_ACCURACY
            BATTERY_SAVING -> Priority.PRIORITY_LOW_POWER
        }
    }
}