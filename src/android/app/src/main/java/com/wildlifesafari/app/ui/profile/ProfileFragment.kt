package com.wildlifesafari.app.ui.profile

import android.os.Bundle
import android.view.View
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import androidx.core.content.ContextCompat.getSystemService
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import androidx.fragment.app.viewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.google.android.material.snackbar.Snackbar // version: 1.9.0
import com.wildlifesafari.app.R
import com.wildlifesafari.app.ui.common.BaseFragment
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import java.text.NumberFormat
import javax.inject.Inject

/**
 * Fragment displaying user profile information, statistics, and settings with enhanced accessibility.
 * Implements WCAG 2.1 AA compliance for optimal screen reader support and touch target sizes.
 */
class ProfileFragment : BaseFragment(R.layout.fragment_profile) {

    private val viewModel: ProfileViewModel by viewModels()
    private var syncJob: Job? = null
    private lateinit var accessibilityManager: AccessibilityManager

    // UI Components (to be initialized in onViewCreated)
    private var statsContainer: View? = null
    private var collectionsContainer: View? = null
    private var settingsContainer: View? = null
    private var syncButton: View? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        accessibilityManager = requireContext().getSystemService(AccessibilityManager::class.java)!!
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        
        initializeViews(view)
        setupAccessibility()
        setupObservers()
        setupSyncButton()
        
        // Initial data load
        viewModel.loadUserStats()
    }

    private fun initializeViews(view: View) {
        statsContainer = view.findViewById(R.id.stats_container)
        collectionsContainer = view.findViewById(R.id.collections_container)
        settingsContainer = view.findViewById(R.id.settings_container)
        syncButton = view.findViewById(R.id.sync_button)

        // Set minimum touch target sizes for accessibility
        listOf(statsContainer, collectionsContainer, settingsContainer, syncButton).forEach { container ->
            container?.let {
                ViewCompat.setMinimumTouchTargetSize(it, resources.getDimensionPixelSize(R.dimen.min_touch_target))
            }
        }
    }

    private fun setupAccessibility() {
        statsContainer?.let { container ->
            ViewCompat.setAccessibilityDelegate(container, object : androidx.core.view.AccessibilityDelegateCompat() {
                override fun onInitializeAccessibilityNodeInfo(host: View, info: AccessibilityNodeInfoCompat) {
                    super.onInitializeAccessibilityNodeInfo(host, info)
                    info.roleDescription = getString(R.string.accessibility_stats_section)
                    info.isHeading = true
                }
            })
        }

        syncButton?.let { button ->
            button.contentDescription = getString(R.string.accessibility_sync_button)
            button.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
        }
    }

    private fun setupObservers() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                // Observe user statistics
                launch {
                    viewModel.userStats.collectLatest { stats ->
                        updateStatsUI(stats)
                        announceForAccessibility(
                            view = requireView(),
                            announcement = getString(
                                R.string.accessibility_stats_updated,
                                NumberFormat.getInstance().format(stats.totalDiscoveries)
                            )
                        )
                    }
                }

                // Observe collections
                launch {
                    viewModel.collections.collectLatest { collections ->
                        updateCollectionsUI(collections)
                        if (collections.isNotEmpty()) {
                            announceForAccessibility(
                                view = requireView(),
                                announcement = getString(
                                    R.string.accessibility_collections_updated,
                                    collections.size
                                )
                            )
                        }
                    }
                }

                // Observe sync state
                launch {
                    viewModel.syncState.collectLatest { state ->
                        handleSyncState(state)
                    }
                }

                // Observe settings
                launch {
                    viewModel.settings.collectLatest { settings ->
                        updateSettingsUI(settings)
                    }
                }
            }
        }
    }

    private fun setupSyncButton() {
        syncButton?.setOnClickListener {
            handleSync()
        }
    }

    private fun handleSync() {
        syncJob?.cancel()
        syncJob = viewLifecycleOwner.lifecycleScope.launch {
            showLoading()
            announceForAccessibility(
                view = requireView(),
                announcement = getString(R.string.accessibility_sync_started)
            )

            try {
                viewModel.syncUserData()
            } catch (e: Exception) {
                handleError(getString(R.string.sync_error_message))
            } finally {
                hideLoading()
            }
        }
    }

    private fun handleSyncState(state: SyncState) {
        when (state) {
            is SyncState.Syncing -> {
                showLoading()
                syncButton?.isEnabled = false
            }
            is SyncState.Success -> {
                hideLoading()
                syncButton?.isEnabled = true
                showSyncSuccess(state.result)
            }
            is SyncState.Error -> {
                hideLoading()
                syncButton?.isEnabled = true
                handleError(getString(R.string.sync_error_message))
            }
            else -> {
                syncButton?.isEnabled = true
            }
        }
    }

    private fun showSyncSuccess(result: SyncResult) {
        val message = getString(
            R.string.sync_success_message,
            result.syncedItems,
            result.failedItems.size
        )
        Snackbar.make(requireView(), message, Snackbar.LENGTH_LONG).show()
        announceForAccessibility(requireView(), message)
    }

    private fun updateStatsUI(stats: UserStats) {
        // Update statistics UI components with proper content descriptions
        statsContainer?.findViewById<View>(R.id.total_discoveries)?.let {
            it.contentDescription = getString(
                R.string.accessibility_total_discoveries,
                stats.totalDiscoveries
            )
        }
        // Update other stats similarly...
    }

    private fun updateCollectionsUI(collections: List<CollectionSummary>) {
        // Update collections UI with proper accessibility labels
        collections.forEach { collection ->
            // Create or update collection items with proper accessibility support
        }
    }

    private fun updateSettingsUI(settings: UserSettings) {
        // Update settings UI components with proper accessibility support
        settingsContainer?.let { container ->
            // Update settings toggles and controls
        }
    }

    override fun getScreenTitle(): String = getString(R.string.profile_screen_title)

    override fun getFirstFocusableElementId(): Int = R.id.stats_container

    override fun onDestroyView() {
        syncJob?.cancel()
        syncJob = null
        statsContainer = null
        collectionsContainer = null
        settingsContainer = null
        syncButton = null
        super.onDestroyView()
    }

    companion object {
        fun newInstance() = ProfileFragment()
    }
}