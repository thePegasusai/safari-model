/*
 * Room Database: AppDatabase
 * Version: 1.0
 *
 * Dependencies:
 * - androidx.room:room-runtime:2.6.0
 * - androidx.room:room-ktx:2.6.0
 */

package com.wildlifesafari.app.data.database

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.wildlifesafari.app.data.database.dao.CollectionDao
import com.wildlifesafari.app.data.database.dao.DiscoveryDao
import com.wildlifesafari.app.data.database.dao.SpeciesDao
import com.wildlifesafari.app.data.database.entities.Collection
import com.wildlifesafari.app.data.database.entities.Discovery
import com.wildlifesafari.app.data.database.entities.Species
import com.wildlifesafari.app.data.database.converters.Converters

/**
 * Main Room database class for the Wildlife Safari application.
 * Provides thread-safe access to the local SQLite database with comprehensive
 * offline storage capabilities and performance optimization.
 *
 * Features:
 * - Thread-safe singleton implementation
 * - Automatic schema migrations
 * - Type conversion support
 * - Performance optimization through indexing
 * - Data integrity through foreign key constraints
 */
@Database(
    entities = [
        Collection::class,
        Discovery::class,
        Species::class
    ],
    version = 1,
    exportSchema = true
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {

    /**
     * Data Access Object for Collection entity operations
     */
    abstract val collectionDao: CollectionDao

    /**
     * Data Access Object for Discovery entity operations
     */
    abstract val discoveryDao: DiscoveryDao

    /**
     * Data Access Object for Species entity operations
     */
    abstract val speciesDao: SpeciesDao

    companion object {
        private const val DATABASE_NAME = "wildlife_safari.db"

        @Volatile
        private var instance: AppDatabase? = null

        /**
         * Gets the singleton database instance, creating it if necessary.
         * Ensures thread-safety through double-checked locking pattern.
         *
         * @param context Application context
         * @return Single database instance
         */
        fun getInstance(context: Context): AppDatabase {
            return instance ?: synchronized(this) {
                instance ?: buildDatabase(context).also { instance = it }
            }
        }

        private fun buildDatabase(context: Context): AppDatabase {
            return Room.databaseBuilder(
                context.applicationContext,
                AppDatabase::class.java,
                DATABASE_NAME
            ).apply {
                // Enable foreign keys for referential integrity
                enableForeignKeyConstraints()

                // Add migration support
                addMigrations(*DatabaseMigrations.ALL_MIGRATIONS)

                // Add callback for database creation/opening
                addCallback(DatabaseCallback())

                // Configure database for optimal performance
                setJournalMode(RoomDatabase.JournalMode.WRITE_AHEAD_LOGGING)

                // Allow queries on main thread only in debug builds
                if (BuildConfig.DEBUG) {
                    allowMainThreadQueries()
                }

                // Configure query execution executor
                setQueryExecutor(DatabaseExecutors.queryExecutor)
                setTransactionExecutor(DatabaseExecutors.transactionExecutor)

                // Enable database encryption if needed
                // TODO: Implement encryption when security requirements are finalized
            }.build()
        }
    }
}

/**
 * Callback for database lifecycle events
 */
private class DatabaseCallback : RoomDatabase.Callback() {
    override fun onCreate(db: SupportSQLiteDatabase) {
        super.onCreate(db)
        // Initialize database with required data
        DatabaseInitializer.initializeDatabase(db)
    }

    override fun onOpen(db: SupportSQLiteDatabase) {
        super.onOpen(db)
        // Perform any necessary checks or cleanup on database open
    }
}

/**
 * Custom executors for database operations
 */
private object DatabaseExecutors {
    val queryExecutor = Executors.newFixedThreadPool(4)
    val transactionExecutor = Executors.newSingleThreadExecutor()
}

/**
 * Database migrations between versions
 */
private object DatabaseMigrations {
    val ALL_MIGRATIONS = arrayOf<Migration>(
        // Add migrations here when updating schema
    )
}

/**
 * Database initialization utilities
 */
private object DatabaseInitializer {
    fun initializeDatabase(db: SupportSQLiteDatabase) {
        // Initialize with required data if needed
    }
}