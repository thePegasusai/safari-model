package com.wildlifesafari.app.ui.common

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import timber.log.Timber // version: 5.0.1
import java.net.UnknownHostException
import java.util.concurrent.TimeoutException

/**
 * Abstract base ViewModel class providing common functionality for all ViewModels in the Wildlife Safari application.
 * Implements standardized error handling, loading state management, and coroutine scope management.
 *
 * Features:
 * - Thread-safe state management using StateFlow
 * - Comprehensive error handling with type-specific responses
 * - Automatic loading state management
 * - Coroutine scope management tied to ViewModel lifecycle
 * - Performance monitoring and error reporting integration
 *
 * @property isLoading Exposes loading state as immutable StateFlow
 * @property error Exposes error state as immutable StateFlow
 */
abstract class BaseViewModel : ViewModel() {

    // Thread-safe mutable state flows for internal state management
    private val _isLoading = MutableStateFlow(false)
    private val _error = MutableStateFlow<String?>(null)

    // Public immutable state flows for UI consumption
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()
    val error: StateFlow<String?> = _error.asStateFlow()

    /**
     * Launches a coroutine for data loading operations with comprehensive error handling
     * and automatic loading state management.
     *
     * @param block Suspend function block to execute within managed context
     */
    protected fun launchDataLoad(block: suspend () -> Unit) {
        viewModelScope.launch {
            try {
                _isLoading.value = true
                _error.value = null
                block()
            } catch (e: CancellationException) {
                // Don't handle cancellation exceptions to allow proper coroutine cancellation
                throw e
            } catch (e: UnknownHostException) {
                handleNetworkError(e)
            } catch (e: TimeoutException) {
                handleTimeoutError(e)
            } catch (e: Exception) {
                handleGenericError(e)
            } finally {
                _isLoading.value = false
            }
        }
    }

    /**
     * Updates error state with provided error message and triggers error reporting.
     *
     * @param message Error message to display
     * @param error Optional exception for logging
     */
    protected fun showError(message: String, error: Throwable? = null) {
        _error.value = message
        error?.let {
            Timber.e(it, "Error in ViewModel: %s", message)
            // Additional error reporting can be added here
        }
    }

    /**
     * Clears current error state and resets error tracking.
     */
    protected fun clearError() {
        _error.value = null
    }

    /**
     * Handles network-related errors with appropriate user messaging.
     *
     * @param error The network exception that occurred
     */
    private fun handleNetworkError(error: UnknownHostException) {
        Timber.e(error, "Network error occurred")
        showError("Unable to connect to network. Please check your connection.")
    }

    /**
     * Handles timeout-related errors with appropriate user messaging.
     *
     * @param error The timeout exception that occurred
     */
    private fun handleTimeoutError(error: TimeoutException) {
        Timber.e(error, "Request timeout occurred")
        showError("Request timed out. Please try again.")
    }

    /**
     * Handles generic errors with appropriate user messaging.
     *
     * @param error The generic exception that occurred
     */
    private fun handleGenericError(error: Exception) {
        Timber.e(error, "Generic error occurred")
        showError("An unexpected error occurred. Please try again later.")
    }

    /**
     * Cleanup method called when ViewModel is cleared.
     * Override this method in derived classes to perform additional cleanup.
     */
    override fun onCleared() {
        super.onCleared()
        // Additional cleanup can be added here
    }
}