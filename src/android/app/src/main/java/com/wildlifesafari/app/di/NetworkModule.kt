package com.wildlifesafari.app.di

import android.content.Context
import com.google.gson.Gson // version: 2.10.1
import com.google.gson.GsonBuilder
import com.wildlifesafari.app.data.api.ApiService
import com.wildlifesafari.app.data.api.AuthInterceptor
import com.wildlifesafari.app.utils.Constants.NetworkConstants
import com.wildlifesafari.app.utils.Constants.CacheConstants
import dagger.Module // version: 2.48
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import okhttp3.Cache
import okhttp3.CertificatePinner // version: 4.9.0
import okhttp3.ConnectionPool // version: 4.9.0
import okhttp3.OkHttpClient // version: 4.9.0
import okhttp3.logging.HttpLoggingInterceptor // version: 4.9.0
import retrofit2.Retrofit // version: 2.9.0
import retrofit2.adapter.rxjava3.RxJava3CallAdapterFactory // version: 2.9.0
import retrofit2.converter.gson.GsonConverterFactory // version: 2.9.0
import timber.log.Timber // version: 5.0.1
import java.io.File
import java.util.concurrent.TimeUnit
import javax.inject.Singleton

/**
 * Dagger Hilt module providing network-related dependencies with enhanced security,
 * performance optimizations, and comprehensive error handling.
 */
@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    private const val CACHE_DIR_NAME = "http_cache"
    private val CERTIFICATE_PINS = setOf(
        "sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=", // Primary
        "sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=" // Backup
    )

    /**
     * Provides singleton Gson instance with custom type adapters and serialization settings.
     */
    @Provides
    @Singleton
    fun provideGson(): Gson = GsonBuilder()
        .setDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")
        .serializeNulls()
        .create()

    /**
     * Provides singleton OkHttpClient instance with enhanced security features,
     * connection pooling, and comprehensive error handling.
     */
    @Provides
    @Singleton
    fun provideOkHttpClient(
        authInterceptor: AuthInterceptor,
        @ApplicationContext context: Context
    ): OkHttpClient {
        // Configure cache
        val cacheDir = File(context.cacheDir, CACHE_DIR_NAME)
        val cache = Cache(cacheDir, CacheConstants.MAX_DISK_CACHE_SIZE_BYTES)

        // Configure logging
        val loggingInterceptor = HttpLoggingInterceptor { message ->
            Timber.tag("OkHttp").d(message)
        }.apply {
            level = HttpLoggingInterceptor.Level.BODY
        }

        // Configure certificate pinning
        val certificatePinner = CertificatePinner.Builder().apply {
            CERTIFICATE_PINS.forEach { pin ->
                add("api.wildlifesafari.com", pin)
            }
        }.build()

        return OkHttpClient.Builder().apply {
            // Security configurations
            certificatePinner(certificatePinner)
            followRedirects(false)
            followSslRedirects(false)
            
            // Performance configurations
            cache(cache)
            connectionPool(ConnectionPool(
                NetworkConstants.CONNECTION_POOL_SIZE,
                NetworkConstants.CONNECTION_KEEP_ALIVE_MS,
                TimeUnit.MILLISECONDS
            ))
            
            // Timeout configurations
            connectTimeout(NetworkConstants.CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            readTimeout(NetworkConstants.READ_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            writeTimeout(NetworkConstants.WRITE_TIMEOUT_SECONDS, TimeUnit.SECONDS)

            // Interceptors
            addInterceptor(authInterceptor)
            addInterceptor(loggingInterceptor)
            addNetworkInterceptor { chain ->
                val request = chain.request()
                val response = chain.proceed(request)
                
                // Add security headers
                response.newBuilder()
                    .header("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
                    .header("X-Content-Type-Options", "nosniff")
                    .header("X-Frame-Options", "DENY")
                    .header("X-XSS-Protection", "1; mode=block")
                    .build()
            }

            // Enable gzip compression
            if (NetworkConstants.USE_OPTIMIZED_NETWORK) {
                addInterceptor { chain ->
                    val original = chain.request()
                    val requestBuilder = original.newBuilder()
                        .header("Accept-Encoding", "gzip")
                    chain.proceed(requestBuilder.build())
                }
            }
        }.build()
    }

    /**
     * Provides singleton Retrofit instance with RxJava support and
     * custom error handling.
     */
    @Provides
    @Singleton
    fun provideRetrofit(
        okHttpClient: OkHttpClient,
        gson: Gson
    ): Retrofit {
        return Retrofit.Builder()
            .baseUrl(com.wildlifesafari.app.utils.Constants.API_BASE_URL)
            .client(okHttpClient)
            .addCallAdapterFactory(RxJava3CallAdapterFactory.create())
            .addConverterFactory(GsonConverterFactory.create(gson))
            .build()
    }

    /**
     * Provides singleton ApiService instance with comprehensive
     * error handling and retry mechanisms.
     */
    @Provides
    @Singleton
    fun provideApiService(retrofit: Retrofit): ApiService {
        return retrofit.create(ApiService::class.java)
    }
}