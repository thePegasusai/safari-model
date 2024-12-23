package com.wildlifesafari.app.ui.collection

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.viewModelScope
import com.wildlifesafari.app.domain.models.CollectionModel
import com.wildlifesafari.app.domain.usecases.GetCollectionsUseCase
import com.wildlifesafari.app.ui.common.BaseViewModel
import dagger.hilt.android.lifecycle.HiltViewModel // version: 2.48
import kotlinx.coroutines.flow.* // version: 1.7.3
import kotlinx.coroutines.launch
import timber.log.Timber // version: 5.0.1
import java.util.UUID
import javax.inject.Inject

/**
 * ViewModel responsible for managing UI state and business logic for the collection screen.
 * Implements offline-first architecture with sync status tracking and efficient state management.
 *
 * Features:
 * - Offline-first data management
 * - Real-time sync status updates
 * - Efficient state management using StateFlow
 * - Process death handling
 * - Pagination support
 * - Sort and filter capabilities
 */
@HiltViewModel
class CollectionViewModel @Inject constructor(
    private val getCollectionsUseCase: GetCollectionsUseCase,
    private val savedStateHandle: SavedStateHandle
) : BaseViewModel() {

    // UI State
    private val _collections = MutableStateFlow<List<CollectionModel>>(emptyList())
    val collections: StateFlow<List<CollectionModel>> = _collections.asStateFlow()

    private val _selectedCollection = MutableStateFlow<CollectionModel?>(null)
    val selectedCollection: StateFlow<CollectionModel?> = _selectedCollection.asStateFlow()

    private val _sortOption = MutableStateFlow(
        savedStateHandle.get<SortOption>(KEY_SORT_OPTION) ?: SortOption.DATE_DESC
    )
    val sortOption: StateFlow<SortOption> = _sortOption.asStateFlow()

    private val _isOfflineMode = MutableStateFlow(
        savedStateHandle.get<Boolean>(KEY_OFFLINE_MODE) ?: false
    )
    val isOfflineMode: StateFlow<Boolean> = _isOfflineMode.asStateFlow()

    // Pagination state
    private var currentPage = 0
    private var isLastPage = false
    private var isLoading = false

    init {
        Timber.d("Initializing CollectionViewModel")
        loadInitialData()
    }

    /**
     * Loads initial collection data and restores saved state.
     */
    private fun loadInitialData() {
        viewModelScope.launch {
            savedStateHandle.get<UUID>(KEY_SELECTED_COLLECTION)?.let { id ->
                selectCollection(id)
            }
            loadCollections(refresh = true)
        }
    }

    /**
     * Loads collections with pagination support and current sort option.
     *
     * @param refresh Whether to refresh from the beginning
     * @param pageSize Number of items per page
     */
    fun loadCollections(refresh: Boolean = false, pageSize: Int = PAGE_SIZE) {
        if (isLoading || (!refresh && isLastPage)) return
        isLoading = true

        if (refresh) {
            currentPage = 0
            isLastPage = false
            _collections.value = emptyList()
        }

        launchDataLoad {
            val collections = if (_isOfflineMode.value) {
                getCollectionsUseCase.executeWithFilter(syncedOnly = true)
            } else {
                getCollectionsUseCase.execute()
            }.first()

            val sortedCollections = when (_sortOption.value) {
                SortOption.DATE_DESC -> collections.sortedByDescending { it.updatedAt }
                SortOption.DATE_ASC -> collections.sortedBy { it.updatedAt }
                SortOption.NAME_ASC -> collections.sortedBy { it.name }
                SortOption.NAME_DESC -> collections.sortedByDescending { it.name }
            }

            val paginatedCollections = sortedCollections
                .drop(currentPage * pageSize)
                .take(pageSize)

            isLastPage = paginatedCollections.size < pageSize
            currentPage++

            _collections.value = if (refresh) {
                paginatedCollections
            } else {
                _collections.value + paginatedCollections
            }

            isLoading = false
        }
    }

    /**
     * Selects a collection for detailed view.
     *
     * @param collectionId ID of the collection to select
     */
    fun selectCollection(collectionId: UUID) {
        viewModelScope.launch {
            _selectedCollection.value = _collections.value.find { it.id == collectionId }
            savedStateHandle[KEY_SELECTED_COLLECTION] = collectionId
        }
    }

    /**
     * Updates the sort option and triggers collection reload.
     *
     * @param option New sort option to apply
     */
    fun setSortOption(option: SortOption) {
        _sortOption.value = option
        savedStateHandle[KEY_SORT_OPTION] = option
        loadCollections(refresh = true)
    }

    /**
     * Toggles offline mode and updates collection loading strategy.
     */
    fun toggleOfflineMode() {
        _isOfflineMode.value = !_isOfflineMode.value
        savedStateHandle[KEY_OFFLINE_MODE] = _isOfflineMode.value
        loadCollections(refresh = true)
    }

    /**
     * Refreshes the collection list.
     */
    fun refresh() {
        loadCollections(refresh = true)
    }

    /**
     * Clears the selected collection.
     */
    fun clearSelection() {
        _selectedCollection.value = null
        savedStateHandle.remove<UUID>(KEY_SELECTED_COLLECTION)
    }

    companion object {
        private const val PAGE_SIZE = 20
        private const val KEY_SELECTED_COLLECTION = "selected_collection"
        private const val KEY_SORT_OPTION = "sort_option"
        private const val KEY_OFFLINE_MODE = "offline_mode"
    }
}

/**
 * Enum defining available sort options for collections.
 */
enum class SortOption {
    DATE_DESC,
    DATE_ASC,
    NAME_ASC,
    NAME_DESC
}