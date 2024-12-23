package com.wildlifesafari.app.ui.components

import android.content.Context
import android.util.AttributeSet
import android.view.LayoutInflater
import android.view.View
import android.widget.ImageView
import android.widget.TextView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import androidx.core.view.updatePadding
import com.bumptech.glide.Glide // version: 4.15.1
import com.bumptech.glide.load.resource.drawable.DrawableTransitionOptions
import com.google.android.material.card.MaterialCardView // version: 1.9.0
import com.wildlifesafari.app.R
import com.wildlifesafari.app.domain.models.SpeciesModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.Locale

/**
 * A Material Design card component that displays detailed species information with
 * accessibility support and performance optimizations.
 */
class SpeciesInfoCard @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = com.google.android.material.R.attr.materialCardViewStyle
) : MaterialCardView(context, attrs, defStyleAttr) {

    private val layoutInflater: LayoutInflater = LayoutInflater.from(context)
    private val contentLayout: ConstraintLayout
    private val speciesImageView: ImageView
    private val commonNameTextView: TextView
    private val scientificNameTextView: TextView
    private val conservationStatusTextView: TextView
    private val confidenceTextView: TextView

    private var clickListener: OnSpeciesClickListener? = null

    private val _isLoadingState = MutableStateFlow(false)
    val isLoadingState: StateFlow<Boolean> = _isLoadingState.asStateFlow()

    private val _hasErrorState = MutableStateFlow(false)
    val hasErrorState: StateFlow<Boolean> = _hasErrorState.asStateFlow()

    init {
        // Inflate and bind views
        contentLayout = layoutInflater.inflate(R.layout.species_info_card, this, true)
            .findViewById(R.id.species_card_content)
        
        speciesImageView = findViewById(R.id.species_image)
        commonNameTextView = findViewById(R.id.species_common_name)
        scientificNameTextView = findViewById(R.id.species_scientific_name)
        conservationStatusTextView = findViewById(R.id.species_conservation_status)
        confidenceTextView = findViewById(R.id.species_confidence)

        // Set up Material Design styling
        radius = context.resources.getDimension(R.dimen.card_corner_radius)
        elevation = context.resources.getDimension(R.dimen.card_elevation)
        strokeWidth = context.resources.getDimensionPixelSize(R.dimen.card_stroke_width)
        strokeColor = ContextCompat.getColor(context, R.color.card_stroke_color)

        // Configure accessibility defaults
        ViewCompat.setAccessibilityHeading(this, true)
        contentDescription = context.getString(R.string.species_card_description)
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES

        // Set up touch feedback
        isClickable = true
        isFocusable = true
        rippleColor = ContextCompat.getColorStateList(context, R.color.card_ripple_color)

        // Ensure minimum touch target size
        val minTouchSize = context.resources.getDimensionPixelSize(R.dimen.min_touch_target_size)
        minimumHeight = minTouchSize
        contentLayout.updatePadding(
            left = minTouchSize / 4,
            right = minTouchSize / 4,
            top = minTouchSize / 4,
            bottom = minTouchSize / 4
        )
    }

    /**
     * Binds species data to the card views with proper styling and accessibility support.
     */
    fun bindSpecies(species: SpeciesModel) {
        _isLoadingState.value = true
        _hasErrorState.value = false

        try {
            // Load species image with Glide
            species.imageUrl?.let { url ->
                Glide.with(context)
                    .load(url)
                    .transition(DrawableTransitionOptions.withCrossFade())
                    .error(R.drawable.ic_species_placeholder)
                    .into(speciesImageView)
            } ?: run {
                speciesImageView.setImageResource(R.drawable.ic_species_placeholder)
            }

            // Set text content with proper styling
            commonNameTextView.text = species.commonName
            scientificNameTextView.apply {
                text = species.scientificName
                setTypeface(typeface, android.graphics.Typeface.ITALIC)
            }

            // Set conservation status with semantic color
            conservationStatusTextView.apply {
                text = species.conservationStatus
                setTextColor(getConservationStatusColor(species.conservationStatus))
            }

            // Format confidence percentage
            confidenceTextView.text = context.getString(
                R.string.species_confidence_format,
                (species.detectionConfidence * 100).toInt()
            )

            // Update accessibility
            updateAccessibility(species)

            // Set up click handling
            setOnClickListener { view ->
                clickListener?.onSpeciesClick(species, view)
            }

            _isLoadingState.value = false
        } catch (e: Exception) {
            _hasErrorState.value = true
            _isLoadingState.value = false
        }
    }

    /**
     * Updates accessibility properties for screen readers and touch interaction.
     */
    private fun updateAccessibility(species: SpeciesModel) {
        // Set comprehensive content description
        val accessibilityDescription = context.getString(
            R.string.species_accessibility_description,
            species.commonName,
            species.scientificName,
            species.conservationStatus,
            (species.detectionConfidence * 100).toInt()
        )
        contentDescription = accessibilityDescription

        // Configure custom accessibility actions
        ViewCompat.replaceAccessibilityAction(
            this,
            AccessibilityNodeInfoCompat.AccessibilityActionCompat.ACTION_CLICK,
            context.getString(R.string.species_action_view_details)
        ) { _, _ ->
            performClick()
            true
        }

        // Set proper traversal order
        ViewCompat.setAccessibilityTraversalBefore(
            scientificNameTextView,
            commonNameTextView.id
        )

        // Configure state description for screen readers
        ViewCompat.setStateDescription(
            this,
            when {
                isLoadingState.value -> context.getString(R.string.species_state_loading)
                hasErrorState.value -> context.getString(R.string.species_state_error)
                else -> null
            }
        )

        // Handle RTL support
        ViewCompat.setLayoutDirection(
            this,
            if (Locale.getDefault().layoutDirection == View.LAYOUT_DIRECTION_RTL)
                ViewCompat.LAYOUT_DIRECTION_RTL
            else ViewCompat.LAYOUT_DIRECTION_LTR
        )
    }

    /**
     * Sets the click listener for species card interactions.
     */
    fun setOnSpeciesClickListener(listener: OnSpeciesClickListener?) {
        clickListener = listener
    }

    private fun getConservationStatusColor(status: String): Int {
        return ContextCompat.getColor(
            context,
            when (status.lowercase()) {
                "extinct" -> R.color.status_extinct
                "critically endangered" -> R.color.status_critically_endangered
                "endangered" -> R.color.status_endangered
                "vulnerable" -> R.color.status_vulnerable
                "near threatened" -> R.color.status_near_threatened
                else -> R.color.status_least_concern
            }
        )
    }
}

/**
 * Interface for handling species card click events with accessibility support.
 */
interface OnSpeciesClickListener {
    /**
     * Called when a species card is clicked.
     * @param species The species model associated with the clicked card
     * @param view The view that was clicked (for transition animations)
     */
    fun onSpeciesClick(species: SpeciesModel, view: View)
}