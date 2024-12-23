package com.wildlifesafari.app.ui.collection

import android.os.Bundle
import android.view.View
import android.view.accessibility.AccessibilityEvent
import androidx.core.view.doOnLayout
import androidx.fragment.app.viewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout // version: 1.2.0
import com.google.android.material.snackbar.Snackbar // version: 1.9.0
import com.wildlifesafari.app.R
import com.wildlifesafari.app.databinding.FragmentCollectionBinding
import com.wildlifesafari.app.domain.models.CollectionModel
import com.wildlifesafari.app.ui.common.BaseFragment
import dagger.hilt.android.AndroidEntryPoint // version: 2.48
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import timber.log.Timber // version: 5.0.1

/**
 * Fragment responsible for displaying and managing the user's collection of wildlife and fossil discoveries.
 * Implements offline-first architecture with cloud sync capabilities and WCAG 2.1 AA accessibility compliance.
 *
 * Features:
 * - Grid and list view layouts with smooth transitions
 * - Pull-to-refresh with sync status indication
 * - Advanced sorting and filtering capabilities
 * - Offline-first data management
 * - WCAG 2.1 AA compliant UI elements
 */
@AndroidEntryPoint
class CollectionFragment : BaseFragment(R.layout.fragment_collection) {

    private val viewModel: CollectionViewModel by viewModels()
    private var _binding: FragmentCollectionBinding? = null
    private val binding get() = _binding!!

    private var isGridView = true
    private lateinit var collectionAdapter: CollectionAdapter
    private var currentSort = SortOption.DATE_DESC
    private var isLoadingMore = false

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        Timber.d("CollectionFragment: onViewCreated")
        
        setupBinding(view)
        setupRecyclerView()
        setupSwipeRefresh()
        setupViewModeToggle()
        setupSortingControls()
        setupFilterControls()
        setupAccessibility()
        observeCollections()
        observeSyncStatus()
    }

    private fun setupBinding(view: View) {
        _binding = FragmentCollectionBinding.bind(view)
    }

    private fun setupRecyclerView() {
        collectionAdapter = CollectionAdapter(
            onItemClick = { collection -> handleCollectionClick(collection) },
            onItemLongClick = { collection -> handleCollectionLongClick(collection) }
        )

        binding.recyclerView.apply {
            adapter = collectionAdapter
            layoutManager = if (isGridView) {
                GridLayoutManager(requireContext(), GRID_SPAN_COUNT)
            } else {
                LinearLayoutManager(requireContext())
            }
            
            // Implement pagination
            addOnScrollListener(object : RecyclerView.OnScrollListener() {
                override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                    super.onScrolled(recyclerView, dx, dy)
                    if (!isLoadingMore) {
                        val layoutManager = recyclerView.layoutManager as? LinearLayoutManager
                        val visibleItemCount = layoutManager?.childCount ?: 0
                        val totalItemCount = layoutManager?.itemCount ?: 0
                        val firstVisibleItem = layoutManager?.findFirstVisibleItemPosition() ?: 0

                        if ((visibleItemCount + firstVisibleItem) >= totalItemCount - LOAD_MORE_THRESHOLD) {
                            loadMoreCollections()
                        }
                    }
                }
            })
        }
    }

    private fun setupSwipeRefresh() {
        binding.swipeRefreshLayout.apply {
            setOnRefreshListener {
                viewModel.refresh()
            }
            setColorSchemeResources(
                R.color.colorPrimary,
                R.color.colorSecondary
            )
        }
    }

    private fun setupViewModeToggle() {
        binding.viewModeToggle.apply {
            setOnClickListener {
                toggleViewMode()
            }
            contentDescription = if (isGridView) {
                getString(R.string.switch_to_list_view)
            } else {
                getString(R.string.switch_to_grid_view)
            }
        }
    }

    private fun setupSortingControls() {
        binding.sortButton.apply {
            setOnClickListener { showSortingDialog() }
            contentDescription = getString(R.string.sort_collections)
        }
    }

    private fun setupFilterControls() {
        binding.filterButton.apply {
            setOnClickListener { showFilterDialog() }
            contentDescription = getString(R.string.filter_collections)
        }
    }

    private fun setupAccessibility() {
        // Set minimum touch target sizes
        binding.apply {
            viewModeToggle.doOnLayout {
                it.minHeight = resources.getDimensionPixelSize(R.dimen.min_touch_target)
                it.minWidth = resources.getDimensionPixelSize(R.dimen.min_touch_target)
            }
            sortButton.doOnLayout {
                it.minHeight = resources.getDimensionPixelSize(R.dimen.min_touch_target)
                it.minWidth = resources.getDimensionPixelSize(R.dimen.min_touch_target)
            }
            filterButton.doOnLayout {
                it.minHeight = resources.getDimensionPixelSize(R.dimen.min_touch_target)
                it.minWidth = resources.getDimensionPixelSize(R.dimen.min_touch_target)
            }
        }

        // Set content grouping for screen readers
        binding.recyclerView.accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
    }

    private fun observeCollections() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.collections.collectLatest { collections ->
                    updateCollections(collections)
                }
            }
        }
    }

    private fun observeSyncStatus() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.syncStatus.collectLatest { status ->
                    handleSyncStatus(status)
                }
            }
        }
    }

    private fun updateCollections(collections: List<CollectionModel>) {
        collectionAdapter.submitList(collections) {
            if (collections.isEmpty()) {
                showEmptyState()
            } else {
                hideEmptyState()
            }
            announceCollectionsUpdate(collections.size)
        }
        binding.swipeRefreshLayout.isRefreshing = false
    }

    private fun handleSyncStatus(status: SyncStatus) {
        when (status) {
            is SyncStatus.Syncing -> showSyncing()
            is SyncStatus.Success -> showSyncSuccess()
            is SyncStatus.Error -> showSyncError(status.error)
            else -> Unit
        }
    }

    private fun showSyncing() {
        binding.swipeRefreshLayout.isRefreshing = true
        announceForAccessibility(getString(R.string.syncing_collections))
    }

    private fun showSyncSuccess() {
        binding.swipeRefreshLayout.isRefreshing = false
        Snackbar.make(
            binding.root,
            getString(R.string.sync_success),
            Snackbar.LENGTH_SHORT
        ).show()
        announceForAccessibility(getString(R.string.sync_complete))
    }

    private fun showSyncError(error: Throwable) {
        binding.swipeRefreshLayout.isRefreshing = false
        Snackbar.make(
            binding.root,
            getString(R.string.sync_error),
            Snackbar.LENGTH_LONG
        ).setAction(getString(R.string.retry)) {
            viewModel.refresh()
        }.show()
        announceForAccessibility(getString(R.string.sync_failed))
    }

    private fun toggleViewMode() {
        isGridView = !isGridView
        binding.recyclerView.layoutManager = if (isGridView) {
            GridLayoutManager(requireContext(), GRID_SPAN_COUNT)
        } else {
            LinearLayoutManager(requireContext())
        }
        collectionAdapter.setViewMode(isGridView)
        announceViewModeChange()
    }

    private fun loadMoreCollections() {
        isLoadingMore = true
        viewModel.loadCollections(refresh = false)
        isLoadingMore = false
    }

    private fun showEmptyState() {
        binding.emptyStateLayout.visibility = View.VISIBLE
        binding.recyclerView.visibility = View.GONE
    }

    private fun hideEmptyState() {
        binding.emptyStateLayout.visibility = View.GONE
        binding.recyclerView.visibility = View.VISIBLE
    }

    private fun announceCollectionsUpdate(count: Int) {
        val message = getString(R.string.collections_count, count)
        announceForAccessibility(message)
    }

    private fun announceViewModeChange() {
        val message = if (isGridView) {
            getString(R.string.grid_view_enabled)
        } else {
            getString(R.string.list_view_enabled)
        }
        announceForAccessibility(message)
    }

    override fun getScreenTitle(): String = getString(R.string.collections_screen_title)

    override fun getFirstFocusableElementId(): Int = R.id.sortButton

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    companion object {
        private const val GRID_SPAN_COUNT = 2
        private const val LOAD_MORE_THRESHOLD = 5

        fun newInstance() = CollectionFragment()
    }
}