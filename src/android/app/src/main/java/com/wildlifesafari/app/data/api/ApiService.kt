package com.wildlifesafari.app.data.api

import com.wildlifesafari.app.domain.models.SpeciesModel
import io.reactivex.rxjava3.core.Single // version: 3.1.5
import okhttp3.MultipartBody // version: 4.9.0
import retrofit2.http.* // version: 2.9.0
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.Headers
import retrofit2.http.Multipart
import retrofit2.http.POST
import retrofit2.http.Part
import retrofit2.http.Query

/**
 * Retrofit interface defining the API endpoints for the Wildlife Safari application.
 * Implements rate-limited endpoints with comprehensive error handling and caching support.
 *
 * Rate limits:
 * - Species detection: 60 requests/minute
 * - Collection management: 120 requests/minute
 * - Species information: 300 requests/minute
 * - Data synchronization: 30 requests/minute
 */
interface ApiService {

    companion object {
        private const val DEFAULT_TIMEOUT_SECONDS = 30
        private const val DEFAULT_PAGE_SIZE = 20
        private const val MAX_PAGE_SIZE = 100
        private const val BASE_API_PATH = "/api/v1"
    }

    /**
     * Sends image data for real-time species detection using LNN.
     *
     * @param image Image file as MultipartBody.Part
     * @param latitude Location latitude
     * @param longitude Location longitude
     * @param timeoutSeconds Optional custom timeout (default: 30s)
     * @return Single<SpeciesModel> with detection results
     */
    @Multipart
    @POST("$BASE_API_PATH/detect")
    @Headers(
        "Content-Type: multipart/form-data",
        "Accept-Encoding: gzip",
        "X-Rate-Limit: 60/minute"
    )
    fun detectSpecies(
        @Part image: MultipartBody.Part,
        @Part("latitude") latitude: Double,
        @Part("longitude") longitude: Double,
        @Query("timeout") timeoutSeconds: Int = DEFAULT_TIMEOUT_SECONDS
    ): Single<SpeciesModel>

    /**
     * Retrieves user's wildlife collection with pagination support.
     *
     * @param page Page number (0-based)
     * @param pageSize Number of items per page
     * @return Single<List<SpeciesModel>> containing paginated collection
     */
    @GET("$BASE_API_PATH/collections")
    @Headers(
        "Cache-Control: max-age=600",
        "X-Rate-Limit: 120/minute"
    )
    fun getCollections(
        @Query("page") page: Int,
        @Query("pageSize") pageSize: Int = DEFAULT_PAGE_SIZE
    ): Single<List<SpeciesModel>>

    /**
     * Retrieves detailed information about a specific species.
     *
     * @param speciesId Unique species identifier
     * @return Single<SpeciesModel> with comprehensive species data
     */
    @GET("$BASE_API_PATH/species/{speciesId}")
    @Headers(
        "Cache-Control: max-age=3600",
        "X-Rate-Limit: 300/minute"
    )
    fun getSpeciesDetails(
        @Path("speciesId") speciesId: String
    ): Single<SpeciesModel>

    /**
     * Synchronizes local collection data with the backend.
     *
     * @param collections List of locally modified collections
     * @return Single<SyncResponse> with synchronization results
     */
    @POST("$BASE_API_PATH/sync")
    @Headers(
        "Content-Type: application/json",
        "X-Rate-Limit: 30/minute"
    )
    fun syncCollections(
        @Body collections: List<SpeciesModel>
    ): Single<SyncResponse>

    /**
     * Uploads media files associated with species observations.
     *
     * @param speciesId Species identifier
     * @param media Media file as MultipartBody.Part
     * @param metadata Optional metadata about the media
     * @return Single<MediaUploadResponse> with upload results
     */
    @Multipart
    @POST("$BASE_API_PATH/species/{speciesId}/media")
    @Headers(
        "Content-Type: multipart/form-data",
        "X-Rate-Limit: 60/minute"
    )
    fun uploadSpeciesMedia(
        @Path("speciesId") speciesId: String,
        @Part media: MultipartBody.Part,
        @Part("metadata") metadata: String? = null
    ): Single<MediaUploadResponse>

    /**
     * Reports incorrect species identification or inappropriate content.
     *
     * @param speciesId Species identifier
     * @param reportReason Reason for the report
     * @return Single<ReportResponse> with report submission status
     */
    @POST("$BASE_API_PATH/species/{speciesId}/report")
    @Headers(
        "Content-Type: application/json",
        "X-Rate-Limit: 30/minute"
    )
    fun reportSpecies(
        @Path("speciesId") speciesId: String,
        @Body reportReason: ReportReason
    ): Single<ReportResponse>
}

/**
 * Response model for sync operations
 */
data class SyncResponse(
    val syncedItems: Int,
    val failedItems: List<String>,
    val timestamp: Long
)

/**
 * Response model for media uploads
 */
data class MediaUploadResponse(
    val mediaId: String,
    val url: String,
    val timestamp: Long
)

/**
 * Model for species reporting
 */
data class ReportReason(
    val reason: String,
    val description: String,
    val reporterDeviceId: String
)

/**
 * Response model for report submission
 */
data class ReportResponse(
    val reportId: String,
    val status: String,
    val timestamp: Long
)