/*
 * ViewModel: SpeciesDetailViewModel
 * Version: 1.0
 *
 * Dependencies:
 * - javax.inject:javax.inject:1
 * - kotlinx.coroutines:kotlinx-coroutines-core:1.7.3
 * - androidx.lifecycle:lifecycle-viewmodel-ktx:2.6.2
 */

package com.wildlifesafari.app.ui.species

import androidx.lifecycle.viewModelScope
import com.wildlifesafari.app.ui.common.BaseViewModel
import com.wildlifesafari.app.domain.models.SpeciesModel
import com.wildlifesafari.app.data.repository.SpeciesRepository
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import timber.log.Timber // version: 5.0.1

/**
 * ViewModel responsible for managing species detail screen state and business logic.
 * Implements offline-first architecture with enhanced state management.
 *
 * Features:
 * - Reactive state management using StateFlow
 * - Offline-first data loading
 * - Automatic error handling
 * - Favorite functionality
 * - Sharing capabilities
 * - Comprehensive species information display
 */
class SpeciesDetailViewModel @Inject constructor(
    private val speciesRepository: SpeciesRepository
) : BaseViewModel() {

    // UI State
    private val _species = MutableStateFlow<SpeciesModel?>(null)
    val species: StateFlow<SpeciesModel?> = _species.asStateFlow()

    private val _isFavorite = MutableStateFlow(false)
    val isFavorite: StateFlow<Boolean> = _isFavorite.asStateFlow()

    private val _isOffline = MutableStateFlow(false)
    val isOffline: StateFlow<Boolean> = _isOffline.asStateFlow()

    private val _loadingState = MutableStateFlow<LoadingState>(LoadingState.IDLE)
    private sealed class LoadingState {
        object IDLE : LoadingState()
        object LOADING : LoadingState()
        data class ERROR(val message: String) : LoadingState()
    }

    /**
     * Loads species details with offline support.
     * Implements offline-first approach by first loading from local cache,
     * then syncing with remote data if available.
     *
     * @param speciesId Unique identifier of the species to load
     */
    fun loadSpecies(speciesId: String) {
        _loadingState.value = LoadingState.LOADING

        launchDataLoad {
            try {
                // First attempt to load from local cache
                speciesRepository.getSpeciesById(speciesId)
                    .collect { cachedSpecies ->
                        cachedSpecies?.let {
                            _species.value = it
                            _isFavorite.value = it.metadata?.get("favorite") == "true"
                            _isOffline.value = true
                        }

                        // Attempt to sync with remote data
                        try {
                            val syncedSpecies = speciesRepository.syncSpecies(speciesId)
                            _species.value = syncedSpecies
                            _isOffline.value = false
                        } catch (e: Exception) {
                            Timber.w(e, "Failed to sync species data, using cached data")
                            // Continue with cached data if sync fails
                        }
                    }
            } catch (e: Exception) {
                handleError(e)
            } finally {
                _loadingState.value = LoadingState.IDLE
            }
        }
    }

    /**
     * Toggles and persists favorite status for the current species.
     * Implements offline-first approach with background sync.
     */
    fun toggleFavorite() {
        val currentSpecies = _species.value ?: return

        launchDataLoad {
            try {
                val updatedMetadata = (currentSpecies.metadata ?: mutableMapOf()).toMutableMap().apply {
                    this["favorite"] = (!_isFavorite.value).toString()
                }

                val updatedSpecies = currentSpecies.copy(
                    metadata = updatedMetadata,
                    lastUpdated = System.currentTimeMillis()
                )

                // Update local cache immediately
                speciesRepository.saveSpecies(updatedSpecies)
                _species.value = updatedSpecies
                _isFavorite.value = !_isFavorite.value

                // Queue background sync
                viewModelScope.launch {
                    try {
                        speciesRepository.syncSpecies(currentSpecies.id)
                    } catch (e: Exception) {
                        Timber.w(e, "Failed to sync favorite status")
                    }
                }
            } catch (e: Exception) {
                handleError(e)
            }
        }
    }

    /**
     * Prepares comprehensive species data for sharing.
     * Includes scientific details, conservation status, and educational information.
     *
     * @return Formatted string containing shareable species information
     */
    fun shareSpecies(): String {
        val species = _species.value ?: return ""
        
        return buildString {
            appendLine("Wildlife Safari Discovery")
            appendLine()
            appendLine("Scientific Name: ${species.scientificName}")
            appendLine("Common Name: ${species.commonName}")
            appendLine("Conservation Status: ${species.conservationStatus}")
            
            species.description?.let {
                appendLine()
                appendLine("Description:")
                appendLine(it)
            }

            species.metadata?.get("habitat")?.let {
                appendLine()
                appendLine("Habitat: $it")
            }

            appendLine()
            appendLine("Learn more about this species in the Wildlife Safari app!")
            appendLine("https://wildlifesafari.app/species/${species.id}")
        }
    }

    /**
     * Handles various error scenarios with appropriate user messaging
     */
    private fun handleError(error: Exception) {
        Timber.e(error, "Error in SpeciesDetailViewModel")
        when (error) {
            is java.net.UnknownHostException -> {
                showError("Unable to connect to network. Using cached data if available.")
                _isOffline.value = true
            }
            is java.util.concurrent.TimeoutException -> {
                showError("Request timed out. Please try again.")
            }
            else -> {
                showError("An unexpected error occurred. Please try again later.")
            }
        }
        _loadingState.value = LoadingState.ERROR(error.message ?: "Unknown error")
    }

    override fun onCleared() {
        super.onCleared()
        // Cleanup any remaining operations
        viewModelScope.launch {
            try {
                // Ensure any pending changes are synced
                _species.value?.let { species ->
                    speciesRepository.syncSpecies(species.id)
                }
            } catch (e: Exception) {
                Timber.w(e, "Failed to sync final changes")
            }
        }
    }
}