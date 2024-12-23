package com.wildlifesafari.app.ui.common

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityEvent
import androidx.annotation.LayoutRes
import androidx.core.view.AccessibilityDelegateCompat
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import androidx.fragment.app.Fragment
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.google.android.material.snackbar.Snackbar // version: 1.9.0
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.collectLatest

/**
 * Abstract base Fragment class providing common functionality for all fragments in the Wildlife Safari application.
 * Implements WCAG 2.1 AA compliant accessibility features and standardized error handling.
 *
 * Features:
 * - Lifecycle-aware state management
 * - Accessibility support with screen reader announcements
 * - Standardized error handling with Snackbar integration
 * - Loading state management with accessibility announcements
 * - View caching for performance optimization
 *
 * @property layoutId Layout resource ID for the fragment
 * @property viewModel BaseViewModel instance for state management
 */
abstract class BaseFragment(@LayoutRes private val layoutId: Int) : Fragment() {

    protected abstract val viewModel: BaseViewModel
    private var _rootView: View? = null
    private var currentSnackbar: Snackbar? = null
    
    /**
     * Creates and returns the fragment's UI view hierarchy.
     * Implements view caching for performance optimization.
     */
    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        // Return cached view if available
        if (_rootView != null) {
            return _rootView
        }

        // Inflate and cache the view
        _rootView = inflater.inflate(layoutId, container, false).apply {
            setupAccessibilityDelegate(this)
        }
        
        return _rootView
    }

    /**
     * Initializes the fragment's view hierarchy and sets up state observers.
     */
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        
        setupLoadingState()
        setupErrorHandling()
        initializeAccessibility(view)
    }

    /**
     * Sets up accessibility delegate with enhanced support for screen readers.
     */
    private fun setupAccessibilityDelegate(view: View) {
        ViewCompat.setAccessibilityDelegate(view, object : AccessibilityDelegateCompat() {
            override fun onInitializeAccessibilityNodeInfo(
                host: View,
                info: AccessibilityNodeInfoCompat
            ) {
                super.onInitializeAccessibilityNodeInfo(host, info)
                info.roleDescription = "Screen"
                info.isScreenReaderFocusable = true
            }
        })
    }

    /**
     * Initializes accessibility features for the fragment.
     */
    private fun initializeAccessibility(view: View) {
        view.contentDescription = getScreenTitle()
        view.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
        setupAccessibilityTraversalOrder(view)
    }

    /**
     * Sets up logical accessibility traversal order for the view hierarchy.
     */
    private fun setupAccessibilityTraversalOrder(view: View) {
        ViewCompat.setAccessibilityTraversalBefore(
            view,
            getFirstFocusableElementId()
        )
    }

    /**
     * Sets up observer for loading state changes with accessibility announcements.
     */
    private fun setupLoadingState() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.isLoading.collectLatest { isLoading ->
                    handleLoadingState(isLoading)
                }
            }
        }
    }

    /**
     * Handles loading state changes with accessibility support.
     */
    private fun handleLoadingState(isLoading: Boolean) {
        _rootView?.let { view ->
            if (isLoading) {
                showLoading()
                announceForAccessibility(view, "Loading content")
            } else {
                hideLoading()
                announceForAccessibility(view, "Content loaded")
            }
        }
    }

    /**
     * Sets up observer for error state changes with accessibility support.
     */
    private fun setupErrorHandling() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.error.collectLatest { error ->
                    error?.let { errorMessage ->
                        handleError(errorMessage)
                    }
                }
            }
        }
    }

    /**
     * Handles error state with accessibility announcements and Snackbar display.
     */
    protected fun handleError(errorMessage: String) {
        _rootView?.let { view ->
            currentSnackbar?.dismiss()
            currentSnackbar = Snackbar.make(view, errorMessage, Snackbar.LENGTH_LONG)
                .setAction("Dismiss") {
                    viewModel.clearError()
                }
                .apply {
                    // Ensure error message is announced by screen readers
                    view.announceForAccessibility(errorMessage)
                    show()
                }
        }
    }

    /**
     * Shows loading indicator with accessibility announcement.
     */
    protected open fun showLoading() {
        // Override in subclasses to implement specific loading UI
    }

    /**
     * Hides loading indicator with accessibility announcement.
     */
    protected open fun hideLoading() {
        // Override in subclasses to implement specific loading UI
    }

    /**
     * Announces a message for accessibility services.
     */
    protected fun announceForAccessibility(view: View, announcement: String) {
        view.announceForAccessibility(announcement)
        view.sendAccessibilityEvent(AccessibilityEvent.TYPE_ANNOUNCEMENT)
    }

    /**
     * Returns the screen title for accessibility purposes.
     * Should be overridden by subclasses.
     */
    protected abstract fun getScreenTitle(): String

    /**
     * Returns the ID of the first focusable element for accessibility traversal.
     * Should be overridden by subclasses.
     */
    protected abstract fun getFirstFocusableElementId(): Int

    /**
     * Cleans up resources and references.
     */
    override fun onDestroyView() {
        currentSnackbar?.dismiss()
        currentSnackbar = null
        _rootView = null
        super.onDestroyView()
    }
}