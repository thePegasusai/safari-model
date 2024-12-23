// External dependencies
import { describe, it, beforeEach, afterEach, expect, jest } from '@jest/globals'; // v29.6.0
import { v4 as uuidv4 } from 'uuid'; // v9.0.0
import { performance } from 'perf_hooks'; // v1.0.0

// Internal dependencies
import { Collection, ICollection } from '../src/models/collection.model';
import { CollectionService } from '../src/services/collection.service';
import { pool } from '../src/config/database';
import { redisClient } from '../src/config/redis';

// Test constants
const TEST_TIMEOUT = 10000;
const PERFORMANCE_THRESHOLD = 100; // 100ms SLA requirement
const TEST_USER_ID = uuidv4();

// Test data generators
const generateTestCollection = (securityLevel: 'public' | 'private' | 'sensitive' = 'private'): Partial<ICollection> => ({
  user_id: TEST_USER_ID,
  name: `Test Collection ${uuidv4()}`,
  description: 'Test collection for automated testing',
  metadata: {
    tags: ['test', 'automated'],
    category: 'wildlife',
    visibility: securityLevel,
    stats: {
      total_discoveries: 0,
      unique_species: 0,
      rare_findings: 0
    }
  }
});

describe('CollectionService', () => {
  let collectionService: CollectionService;
  let testCollectionId: string;

  // Setup test environment
  beforeEach(async () => {
    collectionService = new CollectionService();
    // Clear test data and cache
    await pool.query('DELETE FROM collections WHERE user_id = $1', [TEST_USER_ID]);
    const cacheKeys = await redisClient.keys('collection:test:*');
    if (cacheKeys.length > 0) {
      await redisClient.del(...cacheKeys);
    }
  });

  // Cleanup after tests
  afterEach(async () => {
    await pool.query('DELETE FROM collections WHERE user_id = $1', [TEST_USER_ID]);
    const cacheKeys = await redisClient.keys('collection:test:*');
    if (cacheKeys.length > 0) {
      await redisClient.del(...cacheKeys);
    }
  });

  describe('CRUD Operations', () => {
    it('should create a new collection with proper validation', async () => {
      const testData = generateTestCollection();
      const result = await collectionService.createCollection(testData);

      expect(result).toHaveProperty('collection_id');
      expect(result.user_id).toBe(TEST_USER_ID);
      expect(result.metadata.visibility).toBe('private');
      testCollectionId = result.collection_id;
    }, TEST_TIMEOUT);

    it('should retrieve a collection with cache hit', async () => {
      // Create test collection
      const created = await collectionService.createCollection(generateTestCollection());
      
      // First retrieval - cache miss
      const start1 = performance.now();
      const result1 = await collectionService.getCollection(created.collection_id, TEST_USER_ID);
      const duration1 = performance.now() - start1;
      
      // Second retrieval - cache hit
      const start2 = performance.now();
      const result2 = await collectionService.getCollection(created.collection_id, TEST_USER_ID);
      const duration2 = performance.now() - start2;

      expect(result1).toEqual(result2);
      expect(duration2).toBeLessThan(duration1); // Cache hit should be faster
    }, TEST_TIMEOUT);

    it('should update collection with security metadata preserved', async () => {
      const created = await collectionService.createCollection(generateTestCollection('private'));
      
      const updateData = {
        name: 'Updated Collection',
        description: 'Updated description'
      };

      const updated = await collectionService.updateCollection(
        created.collection_id,
        TEST_USER_ID,
        updateData
      );

      expect(updated.name).toBe(updateData.name);
      expect(updated.metadata.visibility).toBe('private');
      expect(updated.updated_at).not.toEqual(created.updated_at);
    }, TEST_TIMEOUT);

    it('should soft delete collection and clear cache', async () => {
      const created = await collectionService.createCollection(generateTestCollection());
      
      await collectionService.deleteCollection(created.collection_id, TEST_USER_ID);
      
      // Verify cache is cleared
      const cached = await redisClient.get(`collection:test:${created.collection_id}`);
      expect(cached).toBeNull();

      // Verify soft delete
      const result = await Collection.findById(created.collection_id);
      expect(result).toBeNull();
    }, TEST_TIMEOUT);
  });

  describe('Performance Validation', () => {
    it('should meet performance SLA requirements', async () => {
      const testData = generateTestCollection();
      
      const start = performance.now();
      await collectionService.createCollection(testData);
      const duration = performance.now() - start;

      expect(duration).toBeLessThan(PERFORMANCE_THRESHOLD);
    }, TEST_TIMEOUT);

    it('should handle concurrent operations efficiently', async () => {
      const operations = Array(10).fill(null).map(() => 
        collectionService.createCollection(generateTestCollection())
      );

      const start = performance.now();
      const results = await Promise.all(operations);
      const duration = performance.now() - start;

      expect(results).toHaveLength(10);
      expect(duration / 10).toBeLessThan(PERFORMANCE_THRESHOLD);
    }, TEST_TIMEOUT);
  });

  describe('Security Validation', () => {
    it('should prevent unauthorized access to collections', async () => {
      const created = await collectionService.createCollection(generateTestCollection());
      
      await expect(
        collectionService.getCollection(created.collection_id, uuidv4())
      ).rejects.toThrow('Unauthorized access to collection');
    });

    it('should enforce data classification for sensitive collections', async () => {
      const sensitiveCollection = await collectionService.createCollection(
        generateTestCollection('sensitive')
      );

      const result = await collectionService.getCollection(
        sensitiveCollection.collection_id,
        TEST_USER_ID
      );

      expect(result?.metadata.visibility).toBe('sensitive');
    });

    it('should validate input data against injection attempts', async () => {
      const maliciousData = {
        ...generateTestCollection(),
        name: "'); DROP TABLE collections; --"
      };

      await expect(
        collectionService.createCollection(maliciousData)
      ).rejects.toThrow();
    });
  });

  describe('Cache Management', () => {
    it('should properly invalidate cache on updates', async () => {
      const created = await collectionService.createCollection(generateTestCollection());
      
      // Get cached version
      await collectionService.getCollection(created.collection_id, TEST_USER_ID);
      
      // Update collection
      const updated = await collectionService.updateCollection(
        created.collection_id,
        TEST_USER_ID,
        { name: 'Updated Name' }
      );

      // Get from cache
      const cached = await redisClient.get(`collection:test:${created.collection_id}`);
      const cachedData = cached ? JSON.parse(cached) : null;

      expect(cachedData?.name).toBe('Updated Name');
    });

    it('should handle cache misses gracefully', async () => {
      const nonExistentId = uuidv4();
      
      const result = await collectionService.getCollection(nonExistentId, TEST_USER_ID);
      
      expect(result).toBeNull();
    });
  });
});