// External dependencies
import { Router, Request, Response } from 'express'; // v4.18.2
import { Logger, createLogger, format, transports } from 'winston'; // v3.10.0
import * as z from 'zod'; // v3.22.2
import { RedisClient } from 'ioredis'; // v5.3.2
import { Histogram, Counter } from 'prom-client'; // v14.2.0

// Internal dependencies
import { CollectionService } from '../services/collection.service';
import { validateCollection, validateUUID } from '../utils/validation';
import { redisClient } from '../config/redis';
import { ICollection } from '../models/collection.model';

// Request validation schemas
const CreateCollectionSchema = z.object({
  name: z.string().min(3).max(100),
  description: z.string().max(1000).optional(),
  metadata: z.object({
    tags: z.array(z.string()).max(10).optional(),
    category: z.enum(['wildlife', 'fossil', 'mixed']).optional(),
    visibility: z.enum(['private', 'public', 'shared']).default('private'),
    shared_with: z.array(z.string().uuid()).optional()
  })
});

// Performance metrics
const requestDuration = new Histogram({
  name: 'collection_request_duration_seconds',
  help: 'Duration of collection API requests',
  labelNames: ['method', 'endpoint', 'status']
});

const requestCounter = new Counter({
  name: 'collection_requests_total',
  help: 'Total number of collection API requests',
  labelNames: ['method', 'endpoint', 'status']
});

export class CollectionController {
  private readonly collectionService: CollectionService;
  private readonly logger: Logger;
  private readonly router: Router;
  private readonly cache: RedisClient;
  private readonly cacheTTL: number = 3600; // 1 hour

  constructor() {
    this.collectionService = new CollectionService();
    this.router = Router();
    this.cache = redisClient;

    // Initialize structured logging
    this.logger = createLogger({
      level: process.env.LOG_LEVEL || 'info',
      format: format.combine(
        format.timestamp(),
        format.json(),
        format.metadata()
      ),
      defaultMeta: { service: 'collection-controller' },
      transports: [
        new transports.Console(),
        new transports.File({ filename: 'error.log', level: 'error' })
      ]
    });

    this.initializeRoutes();
  }

  private initializeRoutes(): void {
    // Collection management endpoints
    this.router.post('/collections', this.createCollection.bind(this));
    this.router.get('/collections/:id', this.getCollection.bind(this));
    this.router.get('/collections', this.getUserCollections.bind(this));
    this.router.put('/collections/:id', this.updateCollection.bind(this));
    this.router.delete('/collections/:id', this.deleteCollection.bind(this));
  }

  /**
   * Creates a new collection with validation and security checks
   */
  private async createCollection(req: Request, res: Response): Promise<void> {
    const startTime = Date.now();
    const endTimer = requestDuration.startTimer({ method: 'POST', endpoint: '/collections' });

    try {
      // Validate request body
      const validatedData = CreateCollectionSchema.parse(req.body);

      // Extract user ID from JWT token (assuming middleware sets this)
      const userId = req.user?.id;
      if (!userId) {
        throw new Error('User not authenticated');
      }

      // Create collection
      const collection = await this.collectionService.createCollection({
        ...validatedData,
        user_id: userId
      });

      // Cache the new collection
      await this.cache.set(
        `collection:${collection.collection_id}`,
        JSON.stringify(collection),
        'EX',
        this.cacheTTL
      );

      // Log success and increment metrics
      this.logger.info('Collection created successfully', {
        collectionId: collection.collection_id,
        userId,
        duration: Date.now() - startTime
      });

      requestCounter.inc({ method: 'POST', endpoint: '/collections', status: 201 });
      endTimer({ status: 201 });

      res.status(201).json({
        status: 'success',
        data: collection
      });
    } catch (error) {
      this.handleError(error, res, startTime, endTimer);
    }
  }

  /**
   * Retrieves a collection by ID with caching
   */
  private async getCollection(req: Request, res: Response): Promise<void> {
    const startTime = Date.now();
    const endTimer = requestDuration.startTimer({ method: 'GET', endpoint: '/collections/:id' });

    try {
      const { id } = req.params;
      const userId = req.user?.id;

      // Validate UUID format
      if (!validateUUID(id)) {
        throw new Error('Invalid collection ID format');
      }

      // Check cache first
      const cached = await this.cache.get(`collection:${id}`);
      if (cached) {
        const collection = JSON.parse(cached);
        if (collection.user_id === userId) {
          requestCounter.inc({ method: 'GET', endpoint: '/collections/:id', status: 200 });
          endTimer({ status: 200 });
          return res.json({ status: 'success', data: collection });
        }
      }

      // Get from service if not cached
      const collection = await this.collectionService.getCollection(id, userId);
      if (!collection) {
        throw new Error('Collection not found');
      }

      // Cache the result
      await this.cache.set(
        `collection:${id}`,
        JSON.stringify(collection),
        'EX',
        this.cacheTTL
      );

      requestCounter.inc({ method: 'GET', endpoint: '/collections/:id', status: 200 });
      endTimer({ status: 200 });

      res.json({
        status: 'success',
        data: collection
      });
    } catch (error) {
      this.handleError(error, res, startTime, endTimer);
    }
  }

  /**
   * Retrieves all collections for a user with pagination
   */
  private async getUserCollections(req: Request, res: Response): Promise<void> {
    const startTime = Date.now();
    const endTimer = requestDuration.startTimer({ method: 'GET', endpoint: '/collections' });

    try {
      const userId = req.user?.id;
      const page = parseInt(req.query.page as string) || 1;
      const limit = parseInt(req.query.limit as string) || 50;

      const result = await this.collectionService.getUserCollections(userId, page, limit);

      requestCounter.inc({ method: 'GET', endpoint: '/collections', status: 200 });
      endTimer({ status: 200 });

      res.json({
        status: 'success',
        data: result.collections,
        meta: {
          total: result.total,
          page,
          limit
        }
      });
    } catch (error) {
      this.handleError(error, res, startTime, endTimer);
    }
  }

  /**
   * Updates a collection with validation and cache management
   */
  private async updateCollection(req: Request, res: Response): Promise<void> {
    const startTime = Date.now();
    const endTimer = requestDuration.startTimer({ method: 'PUT', endpoint: '/collections/:id' });

    try {
      const { id } = req.params;
      const userId = req.user?.id;

      // Validate input data
      const validatedData = CreateCollectionSchema.parse(req.body);
      if (!validateUUID(id)) {
        throw new Error('Invalid collection ID format');
      }

      // Update collection
      const collection = await this.collectionService.updateCollection(id, userId, validatedData);

      // Update cache
      await this.cache.set(
        `collection:${id}`,
        JSON.stringify(collection),
        'EX',
        this.cacheTTL
      );

      requestCounter.inc({ method: 'PUT', endpoint: '/collections/:id', status: 200 });
      endTimer({ status: 200 });

      res.json({
        status: 'success',
        data: collection
      });
    } catch (error) {
      this.handleError(error, res, startTime, endTimer);
    }
  }

  /**
   * Deletes a collection with cache invalidation
   */
  private async deleteCollection(req: Request, res: Response): Promise<void> {
    const startTime = Date.now();
    const endTimer = requestDuration.startTimer({ method: 'DELETE', endpoint: '/collections/:id' });

    try {
      const { id } = req.params;
      const userId = req.user?.id;

      if (!validateUUID(id)) {
        throw new Error('Invalid collection ID format');
      }

      await this.collectionService.deleteCollection(id, userId);

      // Invalidate cache
      await this.cache.del(`collection:${id}`);

      requestCounter.inc({ method: 'DELETE', endpoint: '/collections/:id', status: 204 });
      endTimer({ status: 204 });

      res.status(204).send();
    } catch (error) {
      this.handleError(error, res, startTime, endTimer);
    }
  }

  /**
   * Centralized error handling with logging and metrics
   */
  private handleError(error: any, res: Response, startTime: number, endTimer: any): void {
    this.logger.error('Collection operation failed', {
      error: error.message,
      stack: error.stack,
      duration: Date.now() - startTime
    });

    let statusCode = 500;
    if (error instanceof z.ZodError) statusCode = 400;
    if (error.message.includes('not found')) statusCode = 404;
    if (error.message.includes('Unauthorized')) statusCode = 401;

    requestCounter.inc({ status: statusCode });
    endTimer({ status: statusCode });

    res.status(statusCode).json({
      status: 'error',
      message: error.message,
      errors: error instanceof z.ZodError ? error.errors : undefined
    });
  }

  public getRouter(): Router {
    return this.router;
  }
}

export default new CollectionController().getRouter();