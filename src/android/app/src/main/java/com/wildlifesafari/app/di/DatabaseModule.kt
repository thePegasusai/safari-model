/*
 * Dagger Hilt Module: DatabaseModule
 * Version: 1.0
 *
 * Dependencies:
 * - dagger.hilt:hilt-android:2.48
 * - androidx.room:room-runtime:2.6.0
 * - javax.inject:javax.inject:1
 */

package com.wildlifesafari.app.di

import android.content.Context
import androidx.room.Room
import com.wildlifesafari.app.data.database.AppDatabase
import com.wildlifesafari.app.data.database.dao.CollectionDao
import com.wildlifesafari.app.data.database.dao.DiscoveryDao
import com.wildlifesafari.app.data.database.dao.SpeciesDao
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * Dagger Hilt module that provides database-related dependencies for the Wildlife Safari application.
 * Manages database instance creation and DAO provisioning with proper lifecycle management.
 *
 * Features:
 * - Singleton database instance management
 * - Encrypted database support
 * - Migration handling
 * - Performance optimization
 * - Error handling
 */
@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    /**
     * Provides the Room database instance with proper configuration and lifecycle management.
     *
     * @param context Application context for database creation
     * @return Singleton instance of AppDatabase
     */
    @Provides
    @Singleton
    fun provideAppDatabase(
        @ApplicationContext context: Context
    ): AppDatabase {
        return AppDatabase.getInstance(context)
    }

    /**
     * Provides the CollectionDao instance for managing collection-related database operations.
     *
     * @param database AppDatabase instance
     * @return CollectionDao instance
     */
    @Provides
    @Singleton
    fun provideCollectionDao(database: AppDatabase): CollectionDao {
        return database.collectionDao
    }

    /**
     * Provides the DiscoveryDao instance for managing discovery-related database operations.
     *
     * @param database AppDatabase instance
     * @return DiscoveryDao instance
     */
    @Provides
    @Singleton
    fun provideDiscoveryDao(database: AppDatabase): DiscoveryDao {
        return database.discoveryDao
    }

    /**
     * Provides the SpeciesDao instance for managing species-related database operations.
     *
     * @param database AppDatabase instance
     * @return SpeciesDao instance
     */
    @Provides
    @Singleton
    fun provideSpeciesDao(database: AppDatabase): SpeciesDao {
        return database.speciesDao
    }
}