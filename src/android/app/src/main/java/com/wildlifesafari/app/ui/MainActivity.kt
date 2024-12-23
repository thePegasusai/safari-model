package com.wildlifesafari.app.ui

import android.os.Bundle
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.navigation.NavController
import androidx.navigation.fragment.NavHostFragment
import androidx.navigation.ui.AppBarConfiguration
import androidx.navigation.ui.NavigationUI
import androidx.navigation.ui.setupWithNavController
import com.google.android.material.bottomnavigation.BottomNavigationView
import com.wildlifesafari.app.R

/**
 * MainActivity serves as the main entry point and container for the Wildlife Detection Safari Pokédex application.
 * It manages navigation between core features, handles state preservation, and ensures accessibility compliance.
 *
 * @version 1.0
 * @see AppCompatActivity
 */
class MainActivity : AppCompatActivity() {

    // Navigation components
    private lateinit var navController: NavController
    private lateinit var bottomNav: BottomNavigationView
    private lateinit var appBarConfiguration: AppBarConfiguration

    // State flags
    private var isRestoringState: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        // Initialize navigation components
        setupNavigation()
        
        // Setup accessibility features
        setupAccessibility()

        // Restore state if needed
        savedInstanceState?.let {
            isRestoringState = true
            restoreNavigationState(it)
        }

        // Handle deep links
        handleIntent()
    }

    /**
     * Sets up the navigation components including NavController and BottomNavigationView.
     */
    private fun setupNavigation() {
        // Initialize NavController from NavHostFragment
        val navHostFragment = supportFragmentManager
            .findFragmentById(R.id.nav_host_fragment) as NavHostFragment
        navController = navHostFragment.navController

        // Setup bottom navigation
        bottomNav = findViewById(R.id.bottom_navigation)
        bottomNav.setupWithNavController(navController)

        // Configure AppBarConfiguration with top-level destinations
        appBarConfiguration = AppBarConfiguration(
            setOf(
                R.id.cameraFragment,
                R.id.collectionFragment,
                R.id.mapFragment,
                R.id.profileFragment
            )
        )

        // Setup ActionBar with NavController
        NavigationUI.setupActionBarWithNavController(this, navController, appBarConfiguration)

        // Handle navigation item reselection
        bottomNav.setOnItemReselectedListener { menuItem ->
            when (menuItem.itemId) {
                R.id.cameraFragment -> navController.popBackStack(R.id.cameraFragment, false)
                R.id.collectionFragment -> navController.popBackStack(R.id.collectionFragment, false)
                R.id.mapFragment -> navController.popBackStack(R.id.mapFragment, false)
                R.id.profileFragment -> navController.popBackStack(R.id.profileFragment, false)
            }
        }
    }

    /**
     * Configures accessibility features for navigation components.
     * Implements WCAG 2.1 AA standards for navigation and touch targets.
     */
    private fun setupAccessibility() {
        // Configure touch target sizes
        bottomNav.apply {
            ViewCompat.setMinimumTouchTargetSize(this, resources.getDimensionPixelSize(R.dimen.min_touch_target_size))
        }

        // Set content descriptions for navigation items
        bottomNav.menu.apply {
            findItem(R.id.cameraFragment)?.contentDescription = getString(R.string.cd_camera)
            findItem(R.id.collectionFragment)?.contentDescription = getString(R.string.cd_collection)
            findItem(R.id.mapFragment)?.contentDescription = getString(R.string.cd_map)
            findItem(R.id.profileFragment)?.contentDescription = getString(R.string.cd_profile)
        }

        // Enable keyboard navigation
        bottomNav.isFocusable = true
        bottomNav.isFocusableInTouchMode = true
    }

    /**
     * Handles deep link intents for direct navigation to specific features.
     */
    private fun handleIntent() {
        navController.handleDeepLink(intent)
    }

    /**
     * Saves the current state during configuration changes or process death.
     */
    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        // Save navigation state
        outState.putBundle(NAV_STATE_KEY, navController.saveState())
        // Save bottom navigation state
        outState.putInt(SELECTED_TAB_KEY, bottomNav.selectedItemId)
    }

    /**
     * Restores the navigation state from saved instance.
     */
    private fun restoreNavigationState(savedInstanceState: Bundle) {
        // Restore navigation state
        savedInstanceState.getBundle(NAV_STATE_KEY)?.let { navState ->
            navController.restoreState(navState)
        }
        // Restore selected tab
        savedInstanceState.getInt(SELECTED_TAB_KEY).let { selectedId ->
            bottomNav.selectedItemId = selectedId
        }
    }

    /**
     * Handles the Up button press in the action bar.
     */
    override fun onSupportNavigateUp(): Boolean {
        return NavigationUI.navigateUp(navController, appBarConfiguration)
    }

    /**
     * Handles back button press with proper navigation hierarchy.
     */
    override fun onBackPressed() {
        if (!navController.popBackStack()) {
            super.onBackPressed()
        }
    }

    companion object {
        private const val NAV_STATE_KEY = "nav_state"
        private const val SELECTED_TAB_KEY = "selected_tab"
    }
}