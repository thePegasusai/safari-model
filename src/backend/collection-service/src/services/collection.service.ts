// External dependencies
import { Logger, createLogger, format, transports } from 'winston'; // v3.10.0
import * as z from 'zod'; // v3.22.2

// Internal dependencies
import { Collection, ICollection, CollectionSchema } from '../models/collection.model';
import { Discovery } from '../models/discovery.model';
import { pool } from '../config/database';
import { redisClient } from '../config/redis';

// Constants for caching and performance
const CACHE_TTL = 3600; // 1 hour in seconds
const BATCH_SIZE = 100;
const CACHE_PREFIX = 'collection:';

// Enhanced collection service interface
export interface ICollectionService {
  createCollection(data: Partial<ICollection>): Promise<ICollection>;
  getCollection(collectionId: string, userId: string): Promise<ICollection | null>;
  getUserCollections(userId: string, page?: number, limit?: number): Promise<{ collections: ICollection[]; total: number }>;
  updateCollection(collectionId: string, userId: string, data: Partial<ICollection>): Promise<ICollection>;
  deleteCollection(collectionId: string, userId: string): Promise<void>;
}

// Collection service implementation
export class CollectionService implements ICollectionService {
  private logger: Logger;
  private readonly cacheKeyPrefix: string;

  constructor() {
    // Initialize structured logging
    this.logger = createLogger({
      level: process.env.LOG_LEVEL || 'info',
      format: format.combine(
        format.timestamp(),
        format.json(),
        format.metadata()
      ),
      defaultMeta: { service: 'collection-service' },
      transports: [
        new transports.Console(),
        new transports.File({ filename: 'error.log', level: 'error' })
      ]
    });

    this.cacheKeyPrefix = `${CACHE_PREFIX}${process.env.NODE_ENV}:`;
  }

  /**
   * Creates a new collection with validation and caching
   * @param data Collection data to create
   * @returns Promise<ICollection>
   */
  async createCollection(data: Partial<ICollection>): Promise<ICollection> {
    try {
      // Validate input data
      const validatedData = CollectionSchema.parse(data);
      
      // Create new collection instance
      const collection = new Collection(validatedData);
      
      // Save to database with transaction
      const savedCollection = await collection.save();
      
      // Cache the result
      await this.cacheCollection(savedCollection);
      
      this.logger.info('Collection created successfully', {
        collectionId: savedCollection.collection_id,
        userId: savedCollection.user_id
      });
      
      return savedCollection;
    } catch (error) {
      this.logger.error('Failed to create collection', { error, data });
      throw error;
    }
  }

  /**
   * Retrieves a collection by ID with caching
   * @param collectionId Collection UUID
   * @param userId User UUID for authorization
   * @returns Promise<ICollection | null>
   */
  async getCollection(collectionId: string, userId: string): Promise<ICollection | null> {
    try {
      // Check cache first
      const cachedCollection = await this.getCachedCollection(collectionId);
      if (cachedCollection) {
        // Verify user authorization
        if (cachedCollection.user_id !== userId) {
          throw new Error('Unauthorized access to collection');
        }
        return cachedCollection;
      }

      // Get from database if not cached
      const collection = await Collection.findById(collectionId);
      
      if (!collection) {
        return null;
      }

      // Verify user authorization
      if (collection.user_id !== userId) {
        throw new Error('Unauthorized access to collection');
      }

      // Cache the result
      await this.cacheCollection(collection);

      return collection;
    } catch (error) {
      this.logger.error('Failed to retrieve collection', { error, collectionId });
      throw error;
    }
  }

  /**
   * Retrieves all collections for a user with pagination and caching
   * @param userId User UUID
   * @param page Page number (optional)
   * @param limit Items per page (optional)
   * @returns Promise<{ collections: ICollection[]; total: number }>
   */
  async getUserCollections(
    userId: string,
    page: number = 1,
    limit: number = 50
  ): Promise<{ collections: ICollection[]; total: number }> {
    try {
      const offset = (page - 1) * limit;
      
      // Get paginated collections
      const result = await Collection.findByUserId(userId, {
        limit,
        offset,
        sort_by: 'updated_at',
        sort_order: 'desc'
      });

      // Cache individual collections
      await Promise.all(
        result.items.map(collection => this.cacheCollection(collection))
      );

      return {
        collections: result.items,
        total: result.total
      };
    } catch (error) {
      this.logger.error('Failed to retrieve user collections', { error, userId });
      throw error;
    }
  }

  /**
   * Updates a collection with validation and cache management
   * @param collectionId Collection UUID
   * @param userId User UUID for authorization
   * @param data Updated collection data
   * @returns Promise<ICollection>
   */
  async updateCollection(
    collectionId: string,
    userId: string,
    data: Partial<ICollection>
  ): Promise<ICollection> {
    try {
      // Get existing collection
      const existingCollection = await Collection.findById(collectionId);
      
      if (!existingCollection) {
        throw new Error('Collection not found');
      }

      // Verify user authorization
      if (existingCollection.user_id !== userId) {
        throw new Error('Unauthorized access to collection');
      }

      // Merge and validate updated data
      const updatedData = {
        ...existingCollection,
        ...data,
        updated_at: new Date()
      };

      const validatedData = CollectionSchema.parse(updatedData);
      
      // Update collection
      const collection = new Collection(validatedData);
      const savedCollection = await collection.save();

      // Update cache
      await this.cacheCollection(savedCollection);

      return savedCollection;
    } catch (error) {
      this.logger.error('Failed to update collection', { error, collectionId });
      throw error;
    }
  }

  /**
   * Deletes a collection with cascade operations
   * @param collectionId Collection UUID
   * @param userId User UUID for authorization
   * @returns Promise<void>
   */
  async deleteCollection(collectionId: string, userId: string): Promise<void> {
    const client = await pool.connect();
    
    try {
      await client.query('BEGIN');

      // Get collection and verify ownership
      const collection = await Collection.findById(collectionId);
      
      if (!collection) {
        throw new Error('Collection not found');
      }

      if (collection.user_id !== userId) {
        throw new Error('Unauthorized access to collection');
      }

      // Delete associated discoveries
      const discoveries = await Discovery.findByCollectionId(collectionId);
      await Promise.all(discoveries.map(discovery => discovery.delete()));

      // Soft delete collection
      await collection.softDelete();

      // Remove from cache
      await this.removeCacheCollection(collectionId);

      await client.query('COMMIT');

      this.logger.info('Collection deleted successfully', { collectionId });
    } catch (error) {
      await client.query('ROLLBACK');
      this.logger.error('Failed to delete collection', { error, collectionId });
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Private helper methods for cache management
   */
  private async cacheCollection(collection: ICollection): Promise<void> {
    const cacheKey = `${this.cacheKeyPrefix}${collection.collection_id}`;
    await redisClient.set(
      cacheKey,
      JSON.stringify(collection),
      'EX',
      CACHE_TTL
    );
  }

  private async getCachedCollection(collectionId: string): Promise<ICollection | null> {
    const cacheKey = `${this.cacheKeyPrefix}${collectionId}`;
    const cached = await redisClient.get(cacheKey);
    return cached ? JSON.parse(cached) : null;
  }

  private async removeCacheCollection(collectionId: string): Promise<void> {
    const cacheKey = `${this.cacheKeyPrefix}${collectionId}`;
    await redisClient.del(cacheKey);
  }
}