// External dependencies
import { jest } from '@jest/globals'; // v29.7.0
import { GenericContainer, StartedTestContainer } from 'testcontainers'; // v9.9.1
import Redis from 'ioredis-mock'; // v8.9.0
import axios from 'axios'; // v1.6.0
import { v4 as uuidv4 } from 'uuid'; // v9.0.0

// Internal dependencies
import { Discovery, IDiscovery } from '../src/models/discovery.model';
import { DiscoveryService } from '../src/services/discovery.service';
import { Collection } from '../src/models/collection.model';
import { pool } from '../src/config/database';

// Test constants
const TEST_COLLECTION_ID = uuidv4();
const TEST_USER_ID = uuidv4();

// Mock Redis client
const mockRedis = new Redis();

// Mock external APIs
jest.mock('axios');
const mockedAxios = axios as jest.Mocked<typeof axios>;

describe('Discovery Tests', () => {
  let postgresContainer: StartedTestContainer;
  let discoveryService: DiscoveryService;
  let testCollection: Collection;

  beforeAll(async () => {
    // Start PostgreSQL container
    postgresContainer = await new GenericContainer('postgres:15')
      .withEnvironment({
        POSTGRES_USER: 'test',
        POSTGRES_PASSWORD: 'test',
        POSTGRES_DB: 'test_db'
      })
      .withExposedPorts(5432)
      .start();

    // Create test collection
    testCollection = new Collection({
      collection_id: TEST_COLLECTION_ID,
      user_id: TEST_USER_ID,
      name: 'Test Collection',
      metadata: {
        tags: ['test'],
        visibility: 'private'
      }
    });
    await testCollection.save();

    // Initialize discovery service
    discoveryService = new DiscoveryService(
      Discovery,
      Collection,
      mockRedis
    );

    // Mock external API responses
    mockedAxios.create.mockReturnValue({
      post: jest.fn().mockResolvedValue({ data: { success: true } })
    } as any);
  });

  afterAll(async () => {
    await pool.end();
    await postgresContainer.stop();
    await mockRedis.quit();
  });

  describe('Discovery Model Tests', () => {
    const validWildlifeData = {
      collection_id: TEST_COLLECTION_ID,
      species_id: uuidv4(),
      location: {
        latitude: 40.7128,
        longitude: -74.006,
        altitude: 10
      },
      confidence: 0.95,
      media_urls: ['https://example.com/test-image.jpg'],
      metadata: {
        weather: {
          temperature: 22,
          humidity: 65,
          conditions: 'sunny'
        },
        habitat: 'urban',
        notes: 'Test discovery'
      }
    };

    test('should create new discovery with valid wildlife data', async () => {
      const discovery = new Discovery(validWildlifeData);
      const saved = await discovery.save();

      expect(saved).toBeDefined();
      expect(saved.discovery_id).toBeDefined();
      expect(saved.collection_id).toBe(TEST_COLLECTION_ID);
      expect(saved.confidence).toBe(0.95);
    });

    test('should validate required fields', async () => {
      const invalidData = {
        collection_id: TEST_COLLECTION_ID,
        // Missing required fields
      };

      await expect(async () => {
        new Discovery(invalidData);
      }).rejects.toThrow();
    });

    test('should enforce location constraints', async () => {
      const invalidLocation = {
        ...validWildlifeData,
        location: {
          latitude: 100, // Invalid latitude
          longitude: -74.006
        }
      };

      await expect(async () => {
        new Discovery(invalidLocation);
      }).rejects.toThrow();
    });

    test('should handle media array limits', async () => {
      const tooManyMedia = {
        ...validWildlifeData,
        media_urls: Array(11).fill('https://example.com/image.jpg')
      };

      await expect(async () => {
        new Discovery(tooManyMedia);
      }).rejects.toThrow();
    });
  });

  describe('Discovery Service Tests', () => {
    const validDiscoveryData = {
      collection_id: TEST_COLLECTION_ID,
      species_id: uuidv4(),
      location: {
        latitude: 40.7128,
        longitude: -74.006
      },
      confidence: 0.95,
      media_urls: ['https://example.com/test-image.jpg'],
      metadata: {
        habitat: 'urban'
      }
    };

    test('should create and sync discovery', async () => {
      const discovery = await discoveryService.createDiscovery(validDiscoveryData);

      expect(discovery).toBeDefined();
      expect(discovery.discovery_id).toBeDefined();
      expect(discovery.collection_id).toBe(TEST_COLLECTION_ID);
    });

    test('should handle cache operations', async () => {
      // Create discovery
      const discovery = await discoveryService.createDiscovery(validDiscoveryData);

      // First fetch - should cache
      const firstFetch = await discoveryService.getDiscoveryById(discovery.discovery_id);
      expect(firstFetch).toBeDefined();

      // Second fetch - should use cache
      const secondFetch = await discoveryService.getDiscoveryById(discovery.discovery_id);
      expect(secondFetch).toEqual(firstFetch);
    });

    test('should handle collection filtering', async () => {
      // Create multiple discoveries
      const discoveries = await Promise.all([
        discoveryService.createDiscovery({ ...validDiscoveryData, confidence: 0.8 }),
        discoveryService.createDiscovery({ ...validDiscoveryData, confidence: 0.9 }),
        discoveryService.createDiscovery({ ...validDiscoveryData, confidence: 0.95 })
      ]);

      const filteredDiscoveries = await discoveryService.getDiscoveriesByCollection(
        TEST_COLLECTION_ID,
        { confidence_min: 0.9 }
      );

      expect(filteredDiscoveries.length).toBe(2);
      expect(filteredDiscoveries.every(d => d.confidence >= 0.9)).toBe(true);
    });

    test('should handle concurrent operations', async () => {
      const operations = Array(10).fill(null).map(() => 
        discoveryService.createDiscovery(validDiscoveryData)
      );

      const results = await Promise.all(operations);
      expect(results).toHaveLength(10);
      expect(results.every(r => r.discovery_id)).toBe(true);
    });

    test('should sync with biodiversity databases', async () => {
      const discovery = await discoveryService.createDiscovery({
        ...validDiscoveryData,
        confidence: 0.98 // High confidence for sync
      });

      // Verify API calls
      expect(mockedAxios.create().post).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({
          species_id: discovery.species_id,
          location: discovery.location
        })
      );
    });

    test('should handle discovery updates', async () => {
      const discovery = await discoveryService.createDiscovery(validDiscoveryData);
      
      const updateData = {
        confidence: 0.97,
        metadata: {
          ...discovery.metadata,
          notes: 'Updated discovery'
        }
      };

      const updated = await discoveryService.updateDiscovery(
        discovery.discovery_id,
        updateData
      );

      expect(updated.confidence).toBe(0.97);
      expect(updated.metadata.notes).toBe('Updated discovery');
    });

    test('should handle discovery deletion', async () => {
      const discovery = await discoveryService.createDiscovery(validDiscoveryData);
      
      await discoveryService.deleteDiscovery(discovery.discovery_id);

      const deleted = await discoveryService.getDiscoveryById(discovery.discovery_id);
      expect(deleted).toBeNull();
    });
  });
});