package com.wildlifesafari.app.ui.profile

import androidx.lifecycle.viewModelScope
import com.wildlifesafari.app.data.api.ApiService
import com.wildlifesafari.app.data.repository.CollectionRepository
import com.wildlifesafari.app.ui.common.BaseViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.UUID

/**
 * ViewModel for managing user profile data, statistics, and collection management.
 * Implements offline-first architecture with background synchronization.
 *
 * @property collectionRepository Repository for managing user collections
 * @property apiService API service for remote data operations
 */
class ProfileViewModel @Inject constructor(
    private val collectionRepository: CollectionRepository,
    private val apiService: ApiService
) : BaseViewModel() {

    // User statistics state
    private val _userStats = MutableStateFlow(UserStats())
    val userStats: StateFlow<UserStats> = _userStats.asStateFlow()

    // Collections state with pagination support
    private val _collections = MutableStateFlow<List<CollectionSummary>>(emptyList())
    val collections: StateFlow<List<CollectionSummary>> = _collections.asStateFlow()

    // User settings state
    private val _settings = MutableStateFlow(UserSettings())
    val settings: StateFlow<UserSettings> = _settings.asStateFlow()

    // Sync state management
    private val _syncState = MutableStateFlow<SyncState>(SyncState.Idle)
    val syncState: StateFlow<SyncState> = _syncState.asStateFlow()

    init {
        loadInitialData()
        observeSyncStatus()
    }

    /**
     * Loads initial user data including statistics and collections.
     */
    private fun loadInitialData() {
        loadUserStats()
        loadCollections(page = 0, pageSize = INITIAL_PAGE_SIZE)
    }

    /**
     * Loads comprehensive user statistics including discoveries and research contributions.
     */
    fun loadUserStats() {
        launchDataLoad {
            try {
                val stats = apiService.getUserStats().blockingGet()
                val updatedStats = UserStats(
                    totalDiscoveries = stats.totalDiscoveries,
                    uniqueSpecies = stats.uniqueSpecies,
                    researchContributions = stats.researchContributions,
                    activeDays = stats.activeDays,
                    impactScore = calculateImpactScore(stats),
                    lastUpdated = Instant.now().epochSecond
                )
                _userStats.value = updatedStats
            } catch (e: Exception) {
                handleNetworkError(e)
            }
        }
    }

    /**
     * Loads user's collection summaries with pagination support.
     *
     * @param page Page number (0-based)
     * @param pageSize Number of items per page
     */
    fun loadCollections(page: Int, pageSize: Int = PAGE_SIZE) {
        launchDataLoad {
            try {
                val collections = collectionRepository.getAllCollections()
                    .collect { collections ->
                        val summaries = collections.map { collection ->
                            CollectionSummary(
                                id = collection.id,
                                name = collection.name,
                                discoveryCount = collection.discoveryIds.size,
                                lastUpdated = collection.updatedAt,
                                isSynced = collection.isSynced
                            )
                        }
                        _collections.value = summaries
                    }
            } catch (e: Exception) {
                handleNetworkError(e)
            }
        }
    }

    /**
     * Initiates manual synchronization of user data with conflict resolution.
     *
     * @param forceSync Forces immediate sync regardless of network conditions
     */
    fun syncUserData(forceSync: Boolean = false) {
        viewModelScope.launch {
            _syncState.value = SyncState.Syncing
            try {
                val result = collectionRepository.syncCollections()
                when (result) {
                    is Result.Success -> {
                        _syncState.value = SyncState.Success(
                            SyncResult(
                                syncedItems = result.data.syncedItems,
                                failedItems = result.data.failedItems,
                                timestamp = result.data.timestamp
                            )
                        )
                        loadInitialData() // Refresh data after sync
                    }
                    is Result.Error -> {
                        _syncState.value = SyncState.Error(result.exception)
                        showError("Sync failed: ${result.exception.message}")
                    }
                }
            } catch (e: Exception) {
                _syncState.value = SyncState.Error(e)
                handleNetworkError(e)
            }
        }
    }

    /**
     * Updates user application settings with validation.
     *
     * @param newSettings Updated user settings
     */
    fun updateSettings(newSettings: UserSettings) {
        viewModelScope.launch {
            try {
                validateSettings(newSettings)
                _settings.value = newSettings
                // Persist settings changes
                apiService.updateUserSettings(newSettings).blockingGet()
            } catch (e: Exception) {
                showError("Failed to update settings: ${e.message}")
            }
        }
    }

    /**
     * Observes collection sync status changes.
     */
    private fun observeSyncStatus() {
        viewModelScope.launch {
            collectionRepository.syncStatus.collect { status ->
                when (status) {
                    is SyncStatus.Success -> {
                        _syncState.value = SyncState.Success(
                            SyncResult(
                                syncedItems = status.result.succeeded,
                                failedItems = emptyList(),
                                timestamp = System.currentTimeMillis()
                            )
                        )
                    }
                    is SyncStatus.Error -> {
                        _syncState.value = SyncState.Error(status.error)
                    }
                    else -> {} // Handle other states if needed
                }
            }
        }
    }

    /**
     * Calculates user impact score based on contributions and engagement.
     */
    private fun calculateImpactScore(stats: UserStats): Float {
        return (stats.researchContributions * RESEARCH_WEIGHT +
                stats.uniqueSpecies * SPECIES_WEIGHT +
                stats.activeDays * ACTIVITY_WEIGHT) / SCORE_NORMALIZER
    }

    /**
     * Validates user settings before applying changes.
     */
    private fun validateSettings(settings: UserSettings) {
        require(settings.notificationRadius in MIN_NOTIFICATION_RADIUS..MAX_NOTIFICATION_RADIUS) {
            "Notification radius must be between $MIN_NOTIFICATION_RADIUS and $MAX_NOTIFICATION_RADIUS"
        }
    }

    companion object {
        private const val INITIAL_PAGE_SIZE = 20
        private const val PAGE_SIZE = 20
        private const val RESEARCH_WEIGHT = 2.0f
        private const val SPECIES_WEIGHT = 1.5f
        private const val ACTIVITY_WEIGHT = 1.0f
        private const val SCORE_NORMALIZER = 100f
        private const val MIN_NOTIFICATION_RADIUS = 1
        private const val MAX_NOTIFICATION_RADIUS = 100
    }
}

/**
 * Data class representing user statistics.
 */
data class UserStats(
    val totalDiscoveries: Int = 0,
    val uniqueSpecies: Int = 0,
    val researchContributions: Int = 0,
    val activeDays: Int = 0,
    val impactScore: Float = 0f,
    val lastUpdated: Long = 0
)

/**
 * Data class representing collection summary information.
 */
data class CollectionSummary(
    val id: UUID,
    val name: String,
    val discoveryCount: Int,
    val lastUpdated: Long,
    val isSynced: Boolean
)

/**
 * Data class representing user application settings.
 */
data class UserSettings(
    val notificationsEnabled: Boolean = true,
    val notificationRadius: Int = 10,
    val darkModeEnabled: Boolean = false,
    val offlineModeEnabled: Boolean = false,
    val autoSyncEnabled: Boolean = true
)

/**
 * Sealed class representing possible sync states.
 */
sealed class SyncState {
    object Idle : SyncState()
    object Syncing : SyncState()
    data class Success(val result: SyncResult) : SyncState()
    data class Error(val error: Throwable) : SyncState()
}

/**
 * Data class representing sync operation results.
 */
data class SyncResult(
    val syncedItems: Int,
    val failedItems: List<String>,
    val timestamp: Long
)