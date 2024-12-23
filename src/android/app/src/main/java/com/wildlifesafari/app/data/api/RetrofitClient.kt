package com.wildlifesafari.app.data.api

import android.content.Context
import com.wildlifesafari.app.utils.Constants.NetworkConstants
import com.wildlifesafari.app.utils.Constants.CacheConstants
import com.wildlifesafari.app.utils.Constants.ApiEndpoints
import com.wildlifesafari.app.utils.Constants.ErrorConstants
import io.reactivex.rxjava3.core.Completable // version: 3.1.5
import okhttp3.Cache // version: 4.9.0
import okhttp3.CertificatePinner // version: 4.9.0
import okhttp3.ConnectionPool // version: 4.9.0
import okhttp3.Interceptor // version: 4.9.0
import okhttp3.OkHttpClient // version: 4.9.0
import okhttp3.logging.HttpLoggingInterceptor // version: 4.9.0
import retrofit2.Retrofit // version: 2.9.0
import retrofit2.adapter.rxjava3.RxJava3CallAdapterFactory // version: 2.9.0
import retrofit2.converter.gson.GsonConverterFactory // version: 2.9.0
import java.io.File
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton
import timber.log.Timber // version: 5.0.1

/**
 * Singleton class providing a configured Retrofit instance for making API calls to the Wildlife Safari backend.
 * Implements comprehensive security, caching, and monitoring features.
 */
@Singleton
class RetrofitClient @Inject constructor(
    private val authInterceptor: AuthInterceptor,
    private val context: Context
) {
    private val cache: Cache by lazy {
        Cache(
            directory = File(context.cacheDir, "http_cache"),
            maxSize = CacheConstants.MAX_DISK_CACHE_SIZE_BYTES
        )
    }

    private val certificatePinner: CertificatePinner by lazy {
        CertificatePinner.Builder()
            .add("api.wildlifesafari.com", "sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=") // Replace with actual certificate pin
            .build()
    }

    private val connectionPool: ConnectionPool by lazy {
        ConnectionPool(
            maxIdleConnections = NetworkConstants.CONNECTION_POOL_SIZE,
            keepAliveDuration = NetworkConstants.CONNECTION_KEEP_ALIVE_MS,
            timeUnit = TimeUnit.MILLISECONDS
        )
    }

    private val loggingInterceptor: HttpLoggingInterceptor by lazy {
        HttpLoggingInterceptor { message -> Timber.d(message) }.apply {
            level = HttpLoggingInterceptor.Level.BODY
        }
    }

    private val cacheInterceptor: Interceptor = Interceptor { chain ->
        val request = chain.request()
        val response = chain.proceed(request)

        // Cache control based on network availability
        if (isNetworkAvailable(context)) {
            response.newBuilder()
                .header("Cache-Control", "public, max-age=${CacheConstants.CACHE_EXPIRY_HOURS * 3600}")
                .build()
        } else {
            response.newBuilder()
                .header("Cache-Control", "public, only-if-cached, max-stale=${CacheConstants.CACHE_EXPIRY_HOURS * 3600}")
                .build()
        }
    }

    private val metricsInterceptor: Interceptor = Interceptor { chain ->
        val startTime = System.nanoTime()
        val request = chain.request()
        
        try {
            val response = chain.proceed(request)
            val duration = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startTime)
            
            // Log metrics
            Timber.d("Request: ${request.url}, Duration: ${duration}ms, Status: ${response.code}")
            
            response
        } catch (e: Exception) {
            Timber.e(e, "Request failed: ${request.url}")
            throw e
        }
    }

    private val okHttpClient: OkHttpClient by lazy {
        OkHttpClient.Builder().apply {
            // Timeouts
            connectTimeout(NetworkConstants.CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            readTimeout(NetworkConstants.READ_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            writeTimeout(NetworkConstants.WRITE_TIMEOUT_SECONDS, TimeUnit.SECONDS)

            // Security
            certificatePinner(certificatePinner)
            connectionPool(connectionPool)

            // Caching
            cache(cache)
            addNetworkInterceptor(cacheInterceptor)

            // Authentication and monitoring
            addInterceptor(authInterceptor)
            addInterceptor(metricsInterceptor)
            addInterceptor(loggingInterceptor)

            // Compression
            if (NetworkConstants.USE_OPTIMIZED_NETWORK) {
                addInterceptor(GzipRequestInterceptor())
            }

            // Retry on connection failure
            retryOnConnectionFailure(true)
        }.build()
    }

    private val retrofit: Retrofit by lazy {
        Retrofit.Builder()
            .baseUrl(ApiEndpoints.getFullUrl(""))
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create())
            .addCallAdapterFactory(RxJava3CallAdapterFactory.create())
            .build()
    }

    /**
     * Creates a configured instance of the API service interface
     * @return ApiService instance with all configured features
     */
    fun createApiService(): ApiService = retrofit.create(ApiService::class.java)

    /**
     * Clears the HTTP response cache
     * @return Completable indicating operation success/failure
     */
    fun clearCache(): Completable = Completable.fromAction {
        try {
            cache.evictAll()
            Timber.d("Cache cleared successfully")
        } catch (e: Exception) {
            Timber.e(e, "Failed to clear cache")
            throw e
        }
    }

    /**
     * Retrieves current client metrics
     * @return ClientMetrics containing performance and usage data
     */
    fun getMetrics(): ClientMetrics = ClientMetrics(
        cacheSize = cache.size(),
        cacheMaxSize = cache.maxSize(),
        cacheHitCount = cache.hitCount(),
        cacheMissCount = cache.missCount(),
        networkRequestCount = cache.networkCount(),
        requestSuccessCount = cache.requestCount(),
        lastClearTime = cache.directory.lastModified()
    )

    private fun isNetworkAvailable(context: Context): Boolean {
        // Implementation of network availability check
        return true // Placeholder - implement actual network check
    }

    /**
     * Data class containing client performance metrics
     */
    data class ClientMetrics(
        val cacheSize: Long,
        val cacheMaxSize: Long,
        val cacheHitCount: Int,
        val cacheMissCount: Int,
        val networkRequestCount: Int,
        val requestSuccessCount: Int,
        val lastClearTime: Long
    )

    /**
     * Interceptor for adding GZIP compression to requests
     */
    private class GzipRequestInterceptor : Interceptor {
        override fun intercept(chain: Interceptor.Chain): okhttp3.Response {
            val originalRequest = chain.request()
            if (originalRequest.body == null || originalRequest.header("Content-Encoding") != null) {
                return chain.proceed(originalRequest)
            }

            val compressedRequest = originalRequest.newBuilder()
                .header("Content-Encoding", "gzip")
                .method(originalRequest.method, originalRequest.body?.gzip())
                .build()
            return chain.proceed(compressedRequest)
        }
    }
}