package com.wildlifesafari.app.utils

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.Fragment
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Utility class providing permission management functionality for the Wildlife Safari application.
 * Handles runtime permissions for camera, location, and storage access with caching and state management.
 *
 * @version 1.0
 * @since 2023-09-20
 */
object PermissionUtils {

    /**
     * Required permissions for the application's core functionality
     */
    @JvmStatic
    val REQUIRED_PERMISSIONS = arrayOf(
        Manifest.permission.CAMERA,
        Manifest.permission.ACCESS_FINE_LOCATION,
        Manifest.permission.ACCESS_COARSE_LOCATION,
        Manifest.permission.READ_EXTERNAL_STORAGE,
        Manifest.permission.WRITE_EXTERNAL_STORAGE
    )

    /**
     * StateFlow to observe permission states across the application
     */
    private val _permissionStateFlow = MutableStateFlow<Map<String, Boolean>>(emptyMap())
    val permissionStateFlow = _permissionStateFlow.asStateFlow()

    /**
     * Cache for storing permission check results to minimize system calls
     */
    private val permissionCache = mutableMapOf<String, Boolean>()

    /**
     * Counter for tracking how many times rationale has been shown for each permission
     */
    private val rationaleShownCounter = mutableMapOf<String, Int>()

    /**
     * Maximum number of times to show rationale for a permission
     */
    private const val MAX_RATIONALE_SHOWN = 2

    /**
     * Checks if a specific permission is granted
     *
     * @param context Application context
     * @param permission Permission to check
     * @return Boolean indicating if permission is granted
     */
    @JvmStatic
    fun hasPermission(context: Context?, permission: String): Boolean {
        if (context == null) return false

        // Check cache first
        permissionCache[permission]?.let { return it }

        val granted = ContextCompat.checkSelfPermission(
            context,
            permission
        ) == PackageManager.PERMISSION_GRANTED

        // Cache the result
        permissionCache[permission] = granted
        return granted
    }

    /**
     * Checks if multiple permissions are granted
     *
     * @param context Application context
     * @param permissions Array of permissions to check
     * @return Boolean indicating if all permissions are granted
     */
    @JvmStatic
    fun hasPermissions(context: Context?, permissions: Array<String>): Boolean {
        if (context == null) return false
        return permissions.all { hasPermission(context, it) }
    }

    /**
     * Determines if permission rationale should be shown
     *
     * @param fragment Fragment requesting the permission
     * @param permission Permission to check
     * @return Boolean indicating if rationale should be shown
     */
    @JvmStatic
    fun shouldShowRationale(fragment: Fragment?, permission: String): Boolean {
        if (fragment == null) return false

        val timesShown = rationaleShownCounter.getOrDefault(permission, 0)
        if (timesShown >= MAX_RATIONALE_SHOWN) return false

        val shouldShow = fragment.shouldShowRequestPermissionRationale(permission)
        if (shouldShow) {
            rationaleShownCounter[permission] = timesShown + 1
        }
        return shouldShow
    }

    /**
     * Requests specified permissions using Activity Result API
     *
     * @param fragment Fragment requesting permissions
     * @param permissions Array of permissions to request
     * @param onResult Callback for permission request results
     */
    @JvmStatic
    fun requestPermissions(
        fragment: Fragment?,
        permissions: Array<String>,
        onResult: (Map<String, Boolean>) -> Unit
    ) {
        if (fragment == null) return

        val permissionRequest = fragment.registerForActivityResult(
            ActivityResultContracts.RequestMultiplePermissions()
        ) { results ->
            // Update cache and state flow
            permissionCache.putAll(results)
            _permissionStateFlow.value = results
            onResult(results)
        }

        permissionRequest.launch(permissions)
    }

    /**
     * Clears the permission cache and rationale counter
     */
    @JvmStatic
    fun clearCache() {
        permissionCache.clear()
        rationaleShownCounter.clear()
        _permissionStateFlow.value = emptyMap()
    }

    /**
     * Checks if a permission has been permanently denied
     *
     * @param fragment Fragment checking the permission
     * @param permission Permission to check
     * @return Boolean indicating if permission is permanently denied
     */
    @JvmStatic
    fun isPermissionPermanentlyDenied(fragment: Fragment?, permission: String): Boolean {
        if (fragment == null) return false
        return !hasPermission(fragment.context, permission) &&
                !fragment.shouldShowRequestPermissionRationale(permission)
    }

    /**
     * Opens the application settings page
     *
     * @param context Application context
     */
    @JvmStatic
    fun openAppSettings(context: Context?) {
        context?.let {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", context.packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        }
    }
}