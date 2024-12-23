package com.wildlifesafari.app.data.api

import com.wildlifesafari.app.utils.Constants.NetworkConstants
import okhttp3.Interceptor
import okhttp3.Response
import okhttp3.Request
import okhttp3.Protocol
import okhttp3.ResponseBody.Companion.toResponseBody
import java.io.IOException
import java.util.UUID
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import timber.log.Timber // version: 5.0.1
import kotlinx.coroutines.sync.Mutex // version: 1.7.3
import kotlinx.coroutines.sync.withLock

/**
 * Thread-safe OkHttp interceptor that handles JWT authentication, token validation,
 * and security headers for API requests.
 *
 * Features:
 * - JWT token management with thread safety
 * - Comprehensive error handling and retry mechanism
 * - Request/Response logging for monitoring
 * - Security headers injection
 * - Configurable timeouts and retry policies
 */
class AuthInterceptor @Inject constructor(
    private val tokenValidator: TokenValidator,
    private val securityHeadersProvider: SecurityHeadersProvider
) : Interceptor {

    private val mutex = Mutex()
    @Volatile private var authToken: String? = null
    private val retryCount = NetworkConstants.MAX_RETRIES

    companion object {
        private const val HEADER_AUTHORIZATION = "Authorization"
        private const val HEADER_ACCEPT = "Accept"
        private const val HEADER_CONTENT_TYPE = "Content-Type"
        private const val HEADER_REQUEST_ID = "X-Request-ID"
        private const val HEADER_API_VERSION = "X-API-Version"
        
        private const val BEARER_PREFIX = "Bearer "
        private const val MEDIA_TYPE_JSON = "application/json"
        private const val API_VERSION = "v1"
    }

    /**
     * Intercepts HTTP requests to add authentication and security headers
     * with comprehensive error handling and retry mechanism.
     *
     * @param chain The interceptor chain
     * @return Modified HTTP response with authentication headers
     * @throws IOException if network request fails after retries
     */
    @Throws(IOException::class)
    override fun intercept(chain: Interceptor.Chain): Response {
        var retriesLeft = retryCount
        var lastException: Exception? = null

        while (retriesLeft > 0) {
            try {
                return performIntercept(chain)
            } catch (e: IOException) {
                lastException = e
                retriesLeft--
                if (retriesLeft == 0) break
                
                // Exponential backoff
                val backoffMs = ((retryCount - retriesLeft) * NetworkConstants.RETRY_DELAY_MS * 
                    NetworkConstants.RETRY_MULTIPLIER).toLong()
                Thread.sleep(minOf(backoffMs, NetworkConstants.RETRY_MAX_DELAY_MS))
                
                Timber.w("Request failed, retrying (${retryCount - retriesLeft}/$retryCount): ${e.message}")
            }
        }

        // If all retries failed, throw the last exception
        throw lastException ?: IOException("Request failed after $retryCount retries")
    }

    /**
     * Performs the actual interception logic with token validation and header injection.
     *
     * @param chain The interceptor chain
     * @return Modified HTTP response
     * @throws IOException if the request fails
     */
    @Throws(IOException::class)
    private fun performIntercept(chain: Interceptor.Chain): Response {
        val token = authToken
        if (token != null && !tokenValidator.isTokenValid(token)) {
            clearAuthToken()
        }

        val originalRequest = chain.request()
        val requestBuilder = originalRequest.newBuilder().apply {
            // Add authentication header if token is available
            authToken?.let { token ->
                header(HEADER_AUTHORIZATION, "$BEARER_PREFIX$token")
            }

            // Add standard headers
            header(HEADER_ACCEPT, MEDIA_TYPE_JSON)
            header(HEADER_CONTENT_TYPE, MEDIA_TYPE_JSON)
            
            // Add security headers
            header(HEADER_REQUEST_ID, UUID.randomUUID().toString())
            header(HEADER_API_VERSION, API_VERSION)

            // Add additional security headers from provider
            securityHeadersProvider.getSecurityHeaders().forEach { (name, value) ->
                header(name, value)
            }
        }

        // Configure timeouts
        val modifiedChain = chain.withConnectTimeout(
            NetworkConstants.CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .withReadTimeout(NetworkConstants.READ_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .withWriteTimeout(NetworkConstants.WRITE_TIMEOUT_SECONDS, TimeUnit.SECONDS)

        val response = modifiedChain.proceed(requestBuilder.build())

        // Handle authentication errors
        when (response.code) {
            401 -> handleUnauthorized(response)
            403 -> handleForbidden(response)
        }

        return response
    }

    /**
     * Thread-safely updates the authentication token with validation.
     *
     * @param token The new JWT token
     * @throws IllegalArgumentException if the token is invalid
     */
    suspend fun setAuthToken(token: String?) {
        mutex.withLock {
            if (token != null && !tokenValidator.isTokenValid(token)) {
                throw IllegalArgumentException("Invalid token format or signature")
            }
            authToken = token
            Timber.d("Auth token updated successfully")
        }
    }

    /**
     * Clears the current authentication token.
     */
    private fun clearAuthToken() {
        authToken = null
        Timber.d("Auth token cleared")
    }

    /**
     * Handles 401 Unauthorized responses.
     *
     * @param response The unauthorized response
     * @return Modified response with error details
     */
    private fun handleUnauthorized(response: Response): Response {
        clearAuthToken()
        Timber.w("Unauthorized request: ${response.request.url}")
        return createErrorResponse(response, "Authentication required", 401)
    }

    /**
     * Handles 403 Forbidden responses.
     *
     * @param response The forbidden response
     * @return Modified response with error details
     */
    private fun handleForbidden(response: Response): Response {
        Timber.w("Forbidden request: ${response.request.url}")
        return createErrorResponse(response, "Access forbidden", 403)
    }

    /**
     * Creates an error response with detailed information.
     *
     * @param originalResponse The original response
     * @param message Error message
     * @param code HTTP status code
     * @return Modified response with error details
     */
    private fun createErrorResponse(
        originalResponse: Response,
        message: String,
        code: Int
    ): Response {
        val errorJson = """
            {
                "error": {
                    "code": $code,
                    "message": "$message",
                    "requestId": "${originalResponse.request.header(HEADER_REQUEST_ID)}"
                }
            }
        """.trimIndent()

        return Response.Builder()
            .request(originalResponse.request)
            .protocol(Protocol.HTTP_2)
            .code(code)
            .message(message)
            .body(errorJson.toResponseBody(null))
            .build()
    }
}

/**
 * Interface for token validation operations.
 */
interface TokenValidator {
    fun isTokenValid(token: String): Boolean
}

/**
 * Interface for providing security headers.
 */
interface SecurityHeadersProvider {
    fun getSecurityHeaders(): Map<String, String>
}