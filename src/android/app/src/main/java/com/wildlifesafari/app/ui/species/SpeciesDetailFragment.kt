/*
 * Fragment: SpeciesDetailFragment
 * Version: 1.0
 *
 * Dependencies:
 * - androidx.fragment.app:1.6.1
 * - com.github.bumptech.glide:4.15.1
 * - javax.inject:1
 * - androidx.lifecycle:2.6.2
 */

package com.wildlifesafari.app.ui.species

import android.os.Bundle
import android.view.View
import android.view.accessibility.AccessibilityEvent
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import androidx.fragment.app.viewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.bumptech.glide.Glide
import com.bumptech.glide.load.engine.DiskCacheStrategy
import com.wildlifesafari.app.R
import com.wildlifesafari.app.databinding.FragmentSpeciesDetailBinding
import com.wildlifesafari.app.ui.common.BaseFragment
import com.wildlifesafari.app.domain.models.SpeciesModel
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import javax.inject.Inject
import timber.log.Timber

/**
 * Fragment responsible for displaying detailed information about a detected wildlife species or fossil.
 * Implements WCAG 2.1 AA compliance and optimized performance with sub-100ms processing targets.
 */
@AndroidEntryPoint
class SpeciesDetailFragment : BaseFragment(R.layout.fragment_species_detail) {

    @Inject
    lateinit var viewModel: SpeciesDetailViewModel

    private var _binding: FragmentSpeciesDetailBinding? = null
    private val binding get() = _binding!!

    private var speciesId: String? = null
    private var isOffline = false

    companion object {
        const val ARG_SPECIES_ID = "species_id"
        const val TAG = "SpeciesDetailFragment"

        fun newInstance(speciesId: String) = SpeciesDetailFragment().apply {
            arguments = Bundle().apply {
                putString(ARG_SPECIES_ID, speciesId)
            }
        }
    }

    override fun getScreenTitle(): String = getString(R.string.species_detail_screen_title)

    override fun getFirstFocusableElementId(): Int = R.id.species_name_text

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        _binding = FragmentSpeciesDetailBinding.bind(view)

        speciesId = arguments?.getString(ARG_SPECIES_ID)
        if (speciesId == null) {
            showError(getString(R.string.error_invalid_species_id))
            return
        }

        setupUI()
        setupAccessibility()
        setupObservers()
        loadSpeciesData()
    }

    private fun setupUI() {
        with(binding) {
            favoriteButton.setOnClickListener {
                viewModel.toggleFavorite()
            }

            shareButton.setOnClickListener {
                viewModel.shareSpecies()?.let { shareText ->
                    shareSpeciesInfo(shareText)
                }
            }

            syncButton.setOnClickListener {
                if (!isOffline) {
                    viewModel.syncData()
                }
            }

            retryButton.setOnClickListener {
                loadSpeciesData()
            }
        }
    }

    private fun setupAccessibility() {
        with(binding) {
            // Set content descriptions
            favoriteButton.contentDescription = getString(R.string.accessibility_favorite_button)
            shareButton.contentDescription = getString(R.string.accessibility_share_button)
            
            // Configure touch targets
            ViewCompat.setMinimumTouchTargetSize(favoriteButton, 48)
            ViewCompat.setMinimumTouchTargetSize(shareButton, 48)

            // Set traversal order
            ViewCompat.setAccessibilityTraversalBefore(
                speciesNameText,
                scientificNameText.id
            )

            // Configure live regions for dynamic content
            speciesStatusText.accessibilityLiveRegion = 
                View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
    }

    private fun setupObservers() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                // Observe species data
                launch {
                    viewModel.species.collectLatest { species ->
                        species?.let { updateSpeciesUI(it) }
                    }
                }

                // Observe favorite status
                launch {
                    viewModel.isFavorite.collectLatest { isFavorite ->
                        updateFavoriteUI(isFavorite)
                    }
                }

                // Observe offline status
                launch {
                    viewModel.isOffline.collectLatest { offline ->
                        isOffline = offline
                        updateOfflineUI(offline)
                    }
                }

                // Observe sync status
                launch {
                    viewModel.syncStatus.collectLatest { status ->
                        updateSyncStatusUI(status)
                    }
                }
            }
        }
    }

    private fun loadSpeciesData() {
        speciesId?.let { id ->
            showLoading()
            viewModel.loadSpecies(id)
        }
    }

    private fun updateSpeciesUI(species: SpeciesModel) {
        with(binding) {
            speciesNameText.text = species.commonName
            scientificNameText.text = species.scientificName
            conservationStatusText.text = species.conservationStatus
            descriptionText.text = species.description

            // Load species image with Glide
            species.imageUrl?.let { url ->
                Glide.with(this@SpeciesDetailFragment)
                    .load(url)
                    .diskCacheStrategy(DiskCacheStrategy.ALL)
                    .placeholder(R.drawable.species_placeholder)
                    .error(R.drawable.species_error)
                    .into(speciesImage)
            }

            // Update taxonomy information
            taxonomyContainer.removeAllViews()
            species.taxonomy.forEach { (rank, name) ->
                addTaxonomyItem(rank, name)
            }

            // Announce content update for accessibility
            announceForAccessibility(
                view = root,
                announcement = getString(
                    R.string.accessibility_species_loaded,
                    species.commonName
                )
            )
        }
        hideLoading()
    }

    private fun updateFavoriteUI(isFavorite: Boolean) {
        binding.favoriteButton.apply {
            isSelected = isFavorite
            contentDescription = getString(
                if (isFavorite) R.string.accessibility_remove_favorite
                else R.string.accessibility_add_favorite
            )
        }
    }

    private fun updateOfflineUI(isOffline: Boolean) {
        with(binding) {
            offlineIndicator.visibility = if (isOffline) View.VISIBLE else View.GONE
            syncButton.isEnabled = !isOffline
            
            if (isOffline) {
                announceForAccessibility(
                    view = root,
                    announcement = getString(R.string.accessibility_offline_mode)
                )
            }
        }
    }

    private fun updateSyncStatusUI(status: SyncStatus) {
        with(binding) {
            when (status) {
                SyncStatus.SYNCING -> {
                    syncProgressBar.visibility = View.VISIBLE
                    syncButton.isEnabled = false
                }
                SyncStatus.SYNCED -> {
                    syncProgressBar.visibility = View.GONE
                    syncButton.isEnabled = true
                    showSuccess(getString(R.string.sync_success))
                }
                SyncStatus.ERROR -> {
                    syncProgressBar.visibility = View.GONE
                    syncButton.isEnabled = true
                    showError(getString(R.string.sync_error))
                }
            }
        }
    }

    private fun shareSpeciesInfo(shareText: String) {
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, shareText)
        }
        startActivity(Intent.createChooser(shareIntent, getString(R.string.share_species_title)))
    }

    private fun addTaxonomyItem(rank: String, name: String) {
        // Implementation for adding taxonomy items to the container
        // This would create and add individual taxonomy item views
    }

    override fun showLoading() {
        binding.loadingProgressBar.visibility = View.VISIBLE
        binding.contentContainer.visibility = View.GONE
    }

    override fun hideLoading() {
        binding.loadingProgressBar.visibility = View.GONE
        binding.contentContainer.visibility = View.VISIBLE
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}