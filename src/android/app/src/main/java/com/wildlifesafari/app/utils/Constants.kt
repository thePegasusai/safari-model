package com.wildlifesafari.app.utils

import android.os.Build
// version: latest

/**
 * Global constants and configuration parameters for the Wildlife Safari application.
 * Contains comprehensive settings for API, ML model, caching, and system-wide configurations.
 */
object Constants {
    // API Configuration
    const val API_BASE_URL = "https://api.wildlifesafari.com/"
    const val API_VERSION = "v1"
    const val API_TIMEOUT_SECONDS = 30L
    const val API_RATE_LIMIT_REQUESTS = 60
    const val API_RATE_LIMIT_PERIOD_MINUTES = 1

    // Database Configuration
    const val DATABASE_NAME = "wildlife_safari.db"
    const val DATABASE_VERSION = 1

    // ML Model Configuration
    const val ML_MODEL_INPUT_SIZE = 640
    const val ML_MODEL_CHANNELS = 3
    const val ML_MODEL_THREAD_COUNT = 4
    const val ML_MODEL_CONFIDENCE_THRESHOLD = 0.75f
    const val ML_MODEL_FILE_NAME = "lnn_model.tflite"

    // Camera Configuration
    const val CAMERA_PREVIEW_WIDTH = 1920
    const val CAMERA_PREVIEW_HEIGHT = 1080
    const val IMAGE_CAPTURE_QUALITY = 90

    // Cache Configuration
    const val MAX_CACHED_DISCOVERIES = 1000
    const val SYNC_INTERVAL_MINUTES = 15

    // Location Configuration
    const val LOCATION_UPDATE_INTERVAL_MS = 5000L
    const val LOCATION_FASTEST_INTERVAL_MS = 3000L
    const val LOCATION_DISTANCE_METERS = 10.0f

    // Regional Configuration
    const val REGION_EU_GDPR_ENABLED = true
    const val REGION_DATA_RETENTION_DAYS = 90

    // Device Requirements
    const val DEVICE_MIN_MEMORY_MB = 2048
    const val DEVICE_RECOMMENDED_MEMORY_MB = 4096

    /**
     * Network-related constant values with comprehensive timeout and retry configurations
     */
    object NetworkConstants {
        const val CONNECT_TIMEOUT_SECONDS = 30L
        const val READ_TIMEOUT_SECONDS = 30L
        const val WRITE_TIMEOUT_SECONDS = 30L
        const val MAX_RETRIES = 3
        const val RETRY_DELAY_MS = 1000L
        const val RETRY_MAX_DELAY_MS = 5000L
        const val RETRY_MULTIPLIER = 1.5f
        const val CONNECTION_POOL_SIZE = 5
        const val CONNECTION_KEEP_ALIVE_MS = 300000L

        /**
         * Determines if the device should use optimized network settings based on API level
         */
        val USE_OPTIMIZED_NETWORK = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
    }

    /**
     * Caching-related constant values with memory optimization settings
     */
    object CacheConstants {
        const val MAX_DISK_CACHE_SIZE_BYTES = 104857600L  // 100MB
        const val MAX_MEMORY_CACHE_SIZE_BYTES = 52428800L // 50MB
        const val CACHE_EXPIRY_HOURS = 24L
        const val CACHE_TRIM_THRESHOLD_BYTES = 52428800L  // 50MB
        const val CACHE_TRIM_TARGET_BYTES = 41943040L     // 40MB
        const val CACHE_MIN_FREE_SPACE_BYTES = 209715200L // 200MB

        /**
         * Determines optimal cache size based on device memory
         */
        fun getOptimalCacheSize(): Long {
            return if (Runtime.getRuntime().maxMemory() > DEVICE_RECOMMENDED_MEMORY_MB * 1024 * 1024) {
                MAX_MEMORY_CACHE_SIZE_BYTES
            } else {
                MAX_MEMORY_CACHE_SIZE_BYTES / 2
            }
        }
    }

    /**
     * Machine learning-related constant values with performance optimization settings
     */
    object MLConstants {
        const val NUM_THREADS = 4
        const val NUM_LITE_THREADS = 2
        const val DETECTION_THRESHOLD = 0.75f
        const val MAX_DETECTIONS = 10
        const val INFERENCE_TIMEOUT_MS = 100L
        const val MODEL_BATCH_SIZE = 32
        const val MODEL_QUANTIZATION_BITS = 8
        const val MODEL_MEMORY_LIMIT_MB = 256

        /**
         * Determines optimal thread count based on device capabilities
         */
        fun getOptimalThreadCount(): Int {
            return minOf(Runtime.getRuntime().availableProcessors(), NUM_THREADS)
        }

        /**
         * Determines if the device supports hardware acceleration
         */
        val SUPPORTS_HARDWARE_ACCELERATION = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
                Runtime.getRuntime().maxMemory() >= DEVICE_RECOMMENDED_MEMORY_MB * 1024 * 1024
    }

    /**
     * API endpoint configurations
     */
    object ApiEndpoints {
        const val DETECT = "detect"
        const val COLLECTIONS = "collections"
        const val SPECIES = "species"
        const val SYNC = "sync"
        const val MEDIA = "media"

        fun getFullUrl(endpoint: String): String = "$API_BASE_URL$API_VERSION/$endpoint"
    }

    /**
     * Error messages and codes
     */
    object ErrorConstants {
        const val ERROR_NETWORK_UNAVAILABLE = "Network connection unavailable"
        const val ERROR_TIMEOUT = "Request timed out"
        const val ERROR_SERVER = "Server error occurred"
        const val ERROR_RATE_LIMIT = "Rate limit exceeded"
        const val ERROR_INVALID_MODEL = "Invalid ML model configuration"
        const val ERROR_INSUFFICIENT_MEMORY = "Insufficient device memory"
    }
}