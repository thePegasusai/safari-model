package com.wildlifesafari.app.utils

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.os.Looper
import androidx.core.app.ActivityCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.Priority
import com.wildlifesafari.app.utils.Constants.LOCATION_UPDATE_INTERVAL_MS
import com.wildlifesafari.app.utils.Constants.LOCATION_FASTEST_INTERVAL_MS
import com.wildlifesafari.app.utils.Constants.LOCATION_DISTANCE_METERS
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.launch
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Enhanced utility class providing robust location-related functionality for the Wildlife Safari application.
 * Implements battery-efficient location tracking, offline support, and accurate coordinate calculations.
 * @version 1.0
 */
class LocationTracker(
    private val context: Context,
    private val fusedLocationClient: FusedLocationProviderClient,
    private val geofencingClient: GeofencingClient
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val _locationUpdates = MutableStateFlow<Location?>(null)
    val locationUpdates: StateFlow<Location?> = _locationUpdates.asStateFlow()
    private var trackingJob: Job? = null
    private val locationCache = LocationCache()

    private val locationCallback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            result.lastLocation?.let { location ->
                if (isLocationValid(location)) {
                    scope.launch {
                        _locationUpdates.emit(location)
                        locationCache.cacheLocation(location)
                    }
                }
            }
        }
    }

    /**
     * Starts location tracking with specified accuracy and update interval.
     * Implements battery optimization and error handling.
     * @param accuracy Desired location accuracy
     * @param interval Update interval in milliseconds
     * @return Flow of filtered location updates
     */
    fun startTracking(
        accuracy: Int = Priority.PRIORITY_BALANCED_POWER_ACCURACY,
        interval: Long = LOCATION_UPDATE_INTERVAL_MS
    ): Flow<Location> = flow {
        if (!hasLocationPermission()) {
            throw LocationException("Location permission not granted")
        }

        val locationRequest = LocationRequest.Builder(interval)
            .setPriority(accuracy)
            .setMinUpdateIntervalMillis(LOCATION_FASTEST_INTERVAL_MS)
            .setMinUpdateDistanceMeters(LOCATION_DISTANCE_METERS)
            .build()

        if (ActivityCompat.checkSelfPermission(context, 
            Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
            
            fusedLocationClient.requestLocationUpdates(
                locationRequest,
                locationCallback,
                Looper.getMainLooper()
            )
        }
    }.catch { e ->
        emit(locationCache.getLastKnownLocation())
    }.filter { location ->
        isLocationValid(location)
    }.flowOn(Dispatchers.IO)

    /**
     * Stops location tracking and releases resources.
     */
    fun stopTracking() {
        trackingJob?.cancel()
        fusedLocationClient.removeLocationUpdates(locationCallback)
        scope.cancel()
    }

    /**
     * Validates location data for accuracy and freshness.
     * @param location Location to validate
     * @return Boolean indicating if location is valid
     */
    private fun isLocationValid(location: Location?): Boolean {
        return location != null &&
                location.accuracy <= LOCATION_DISTANCE_METERS &&
                System.currentTimeMillis() - location.time <= 60000 // 1 minute threshold
    }

    /**
     * Checks if required location permissions are granted.
     * @return Boolean indicating if permissions are granted
     */
    private fun hasLocationPermission(): Boolean {
        return ActivityCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }

    private inner class LocationCache {
        private val cachedLocations = mutableListOf<Location>()
        private val maxCacheSize = 100

        fun cacheLocation(location: Location) {
            synchronized(cachedLocations) {
                cachedLocations.add(location)
                if (cachedLocations.size > maxCacheSize) {
                    cachedLocations.removeAt(0)
                }
            }
        }

        fun getLastKnownLocation(): Location? {
            return synchronized(cachedLocations) {
                cachedLocations.lastOrNull()
            }
        }
    }
}

/**
 * Calculates accurate distance between two locations using the Haversine formula.
 * Includes error handling and accuracy corrections.
 * @param location1 First location
 * @param location2 Second location
 * @return Result containing distance in meters or error
 */
fun calculateDistance(location1: Location?, location2: Location?): Result<Float> {
    return try {
        if (location1 == null || location2 == null) {
            throw IllegalArgumentException("Locations cannot be null")
        }

        val lat1 = Math.toRadians(location1.latitude)
        val lon1 = Math.toRadians(location1.longitude)
        val lat2 = Math.toRadians(location2.latitude)
        val lon2 = Math.toRadians(location2.longitude)

        val earthRadius = 6371000.0 // Earth's radius in meters

        val dLat = lat2 - lat1
        val dLon = lon2 - lon1

        val a = sin(dLat / 2).pow(2) +
                cos(lat1) * cos(lat2) *
                sin(dLon / 2).pow(2)
        val c = 2 * atan2(sqrt(a), sqrt(1 - a))
        val distance = earthRadius * c

        // Apply accuracy correction
        val accuracyFactor = (location1.accuracy + location2.accuracy) / 2
        val correctedDistance = distance * (1 + accuracyFactor / 100)

        Result.success(correctedDistance.toFloat())
    } catch (e: Exception) {
        Result.failure(e)
    }
}

/**
 * Custom exception for location-related errors.
 */
class LocationException(message: String) : Exception(message)