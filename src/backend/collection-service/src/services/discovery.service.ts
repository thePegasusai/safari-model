// External dependencies
import axios, { AxiosInstance } from 'axios'; // v1.6.0
import * as z from 'zod'; // v3.22.2
import Redis from 'ioredis'; // v5.3.2
import { CircuitBreaker } from 'opossum'; // v7.1.0
import { RateLimiterRedis } from 'rate-limiter-flexible'; // v4.1.0
import { Metrics } from 'prom-client'; // v14.2.0

// Internal dependencies
import { Discovery, IDiscovery, DiscoverySchema } from '../models/discovery.model';
import { Collection } from '../models/collection.model';

// Constants
const CACHE_TTL = 3600; // 1 hour in seconds
const RATE_LIMIT_POINTS = 100; // Number of requests
const RATE_LIMIT_DURATION = 3600; // Per hour

// Interface for external API responses
interface BiodiversityAPIResponse {
  success: boolean;
  reference_id?: string;
  error?: string;
}

// Interface for discovery filters
interface DiscoveryFilters {
  species_id?: string;
  confidence_min?: number;
  date_from?: Date;
  date_to?: Date;
}

export class DiscoveryService {
  private readonly discoveryModel: typeof Discovery;
  private readonly collectionModel: typeof Collection;
  private readonly redisClient: Redis;
  private readonly rateLimiter: RateLimiterRedis;
  private readonly metricsCollector: Metrics;
  private readonly iNaturalistAPI: AxiosInstance;
  private readonly gbifAPI: AxiosInstance;
  private readonly circuitBreaker: CircuitBreaker;

  constructor(
    discoveryModel: typeof Discovery,
    collectionModel: typeof Collection,
    redisClient: Redis
  ) {
    this.discoveryModel = discoveryModel;
    this.collectionModel = collectionModel;
    this.redisClient = redisClient;

    // Initialize rate limiter
    this.rateLimiter = new RateLimiterRedis({
      storeClient: redisClient,
      points: RATE_LIMIT_POINTS,
      duration: RATE_LIMIT_DURATION,
      keyPrefix: 'discovery_ratelimit'
    });

    // Initialize API clients
    this.iNaturalistAPI = axios.create({
      baseURL: process.env.INATURALIST_API_URL,
      timeout: 5000,
      headers: {
        'Authorization': `Bearer ${process.env.INATURALIST_API_KEY}`
      }
    });

    this.gbifAPI = axios.create({
      baseURL: process.env.GBIF_API_URL,
      timeout: 5000,
      headers: {
        'Authorization': `Bearer ${process.env.GBIF_API_KEY}`
      }
    });

    // Initialize circuit breaker for external APIs
    this.circuitBreaker = new CircuitBreaker(this.syncWithBiodiversityDatabases, {
      timeout: 10000,
      resetTimeout: 30000,
      errorThresholdPercentage: 50
    });

    // Initialize metrics
    this.metricsCollector = new Metrics();
    this.initializeMetrics();
  }

  /**
   * Creates a new wildlife or fossil discovery
   * @param discoveryData Discovery data to create
   * @returns Promise<IDiscovery>
   */
  async createDiscovery(discoveryData: Partial<IDiscovery>): Promise<IDiscovery> {
    try {
      // Rate limit check
      await this.rateLimiter.consume(discoveryData.collection_id);

      // Validate discovery data
      const validatedData = DiscoverySchema.parse(discoveryData);

      // Verify collection exists
      const collection = await this.collectionModel.findById(validatedData.collection_id);
      if (!collection) {
        throw new Error('Collection not found');
      }

      // Create discovery instance
      const discovery = new this.discoveryModel(validatedData);

      // Save discovery
      const savedDiscovery = await discovery.save();

      // Sync with external databases
      await this.circuitBreaker.fire(savedDiscovery);

      // Cache the new discovery
      await this.redisClient.setex(
        `discovery:${savedDiscovery.discovery_id}`,
        CACHE_TTL,
        JSON.stringify(savedDiscovery)
      );

      // Update collection stats
      await collection.updateStats();

      // Record metrics
      this.metricsCollector.increment('discoveries_created_total');

      return savedDiscovery;
    } catch (error) {
      this.metricsCollector.increment('discoveries_creation_errors_total');
      throw error;
    }
  }

  /**
   * Retrieves a discovery by ID with caching
   * @param discoveryId Discovery UUID
   * @returns Promise<IDiscovery | null>
   */
  async getDiscoveryById(discoveryId: string): Promise<IDiscovery | null> {
    try {
      // Check cache first
      const cachedDiscovery = await this.redisClient.get(`discovery:${discoveryId}`);
      if (cachedDiscovery) {
        this.metricsCollector.increment('cache_hits_total');
        return JSON.parse(cachedDiscovery);
      }

      // Cache miss - fetch from database
      this.metricsCollector.increment('cache_misses_total');
      const discovery = await this.discoveryModel.findById(discoveryId);

      if (discovery) {
        // Update cache
        await this.redisClient.setex(
          `discovery:${discoveryId}`,
          CACHE_TTL,
          JSON.stringify(discovery)
        );
      }

      return discovery;
    } catch (error) {
      this.metricsCollector.increment('discovery_retrieval_errors_total');
      throw error;
    }
  }

  /**
   * Retrieves discoveries in a collection with filtering and pagination
   * @param collectionId Collection UUID
   * @param filters Optional filters
   * @returns Promise<IDiscovery[]>
   */
  async getDiscoveriesByCollection(
    collectionId: string,
    filters: DiscoveryFilters = {}
  ): Promise<IDiscovery[]> {
    try {
      // Generate cache key based on filters
      const cacheKey = `discoveries:${collectionId}:${JSON.stringify(filters)}`;

      // Check cache
      const cachedResults = await this.redisClient.get(cacheKey);
      if (cachedResults) {
        this.metricsCollector.increment('cache_hits_total');
        return JSON.parse(cachedResults);
      }

      // Fetch from database with filters
      const discoveries = await this.discoveryModel.findByCollectionId(collectionId);

      // Apply filters
      const filteredDiscoveries = discoveries.filter(discovery => {
        let matches = true;
        if (filters.species_id) {
          matches = matches && discovery.species_id === filters.species_id;
        }
        if (filters.confidence_min) {
          matches = matches && discovery.confidence >= filters.confidence_min;
        }
        if (filters.date_from) {
          matches = matches && discovery.created_at >= filters.date_from;
        }
        if (filters.date_to) {
          matches = matches && discovery.created_at <= filters.date_to;
        }
        return matches;
      });

      // Update cache
      await this.redisClient.setex(
        cacheKey,
        CACHE_TTL,
        JSON.stringify(filteredDiscoveries)
      );

      return filteredDiscoveries;
    } catch (error) {
      this.metricsCollector.increment('discovery_retrieval_errors_total');
      throw error;
    }
  }

  /**
   * Updates a discovery with validation and sync
   * @param discoveryId Discovery UUID
   * @param updateData Partial discovery data
   * @returns Promise<IDiscovery>
   */
  async updateDiscovery(
    discoveryId: string,
    updateData: Partial<IDiscovery>
  ): Promise<IDiscovery> {
    try {
      // Rate limit check
      await this.rateLimiter.consume(discoveryId);

      // Fetch existing discovery
      const existingDiscovery = await this.discoveryModel.findById(discoveryId);
      if (!existingDiscovery) {
        throw new Error('Discovery not found');
      }

      // Validate update data
      const validatedData = DiscoverySchema.partial().parse(updateData);

      // Update discovery
      const updatedDiscovery = new this.discoveryModel({
        ...existingDiscovery,
        ...validatedData,
        updated_at: new Date()
      });

      // Save changes
      const savedDiscovery = await updatedDiscovery.save();

      // Sync with external databases
      await this.circuitBreaker.fire(savedDiscovery);

      // Invalidate cache
      await this.redisClient.del(`discovery:${discoveryId}`);

      // Record metrics
      this.metricsCollector.increment('discoveries_updated_total');

      return savedDiscovery;
    } catch (error) {
      this.metricsCollector.increment('discovery_update_errors_total');
      throw error;
    }
  }

  /**
   * Deletes a discovery and associated data
   * @param discoveryId Discovery UUID
   * @returns Promise<void>
   */
  async deleteDiscovery(discoveryId: string): Promise<void> {
    try {
      // Fetch discovery
      const discovery = await this.discoveryModel.findById(discoveryId);
      if (!discovery) {
        throw new Error('Discovery not found');
      }

      // Delete discovery
      await discovery.delete();

      // Invalidate cache
      await this.redisClient.del(`discovery:${discoveryId}`);

      // Record metrics
      this.metricsCollector.increment('discoveries_deleted_total');
    } catch (error) {
      this.metricsCollector.increment('discovery_deletion_errors_total');
      throw error;
    }
  }

  /**
   * Syncs discovery with external biodiversity databases
   * @param discovery Discovery to sync
   * @returns Promise<void>
   */
  private async syncWithBiodiversityDatabases(discovery: IDiscovery): Promise<void> {
    try {
      // Sync with iNaturalist
      const iNaturalistResponse = await this.iNaturalistAPI.post<BiodiversityAPIResponse>(
        '/observations',
        {
          species_id: discovery.species_id,
          location: discovery.location,
          observed_at: discovery.created_at,
          photos: discovery.media_urls
        }
      );

      // Sync with GBIF
      const gbifResponse = await this.gbifAPI.post<BiodiversityAPIResponse>(
        '/occurrences',
        {
          taxonKey: discovery.species_id,
          decimalLatitude: discovery.location.latitude,
          decimalLongitude: discovery.location.longitude,
          eventDate: discovery.created_at,
          mediaUrls: discovery.media_urls
        }
      );

      // Record successful sync
      this.metricsCollector.increment('external_sync_success_total');
    } catch (error) {
      this.metricsCollector.increment('external_sync_errors_total');
      throw error;
    }
  }

  /**
   * Initializes metrics collectors
   */
  private initializeMetrics(): void {
    this.metricsCollector.counter({
      name: 'discoveries_created_total',
      help: 'Total number of discoveries created'
    });

    this.metricsCollector.counter({
      name: 'discoveries_updated_total',
      help: 'Total number of discoveries updated'
    });

    this.metricsCollector.counter({
      name: 'discoveries_deleted_total',
      help: 'Total number of discoveries deleted'
    });

    this.metricsCollector.counter({
      name: 'cache_hits_total',
      help: 'Total number of cache hits'
    });

    this.metricsCollector.counter({
      name: 'cache_misses_total',
      help: 'Total number of cache misses'
    });

    this.metricsCollector.counter({
      name: 'external_sync_success_total',
      help: 'Total number of successful external syncs'
    });

    this.metricsCollector.counter({
      name: 'external_sync_errors_total',
      help: 'Total number of external sync errors'
    });
  }
}