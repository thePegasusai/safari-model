// External dependencies
import { Router, Request, Response, NextFunction } from 'express'; // v4.18.2
import * as z from 'zod'; // v3.22.2
import compression from 'compression'; // v1.7.4
import { RateLimiter } from 'express-rate-limit'; // v6.9.0

// Internal dependencies
import { DiscoveryService } from '../services/discovery.service';
import { validateDiscovery, validateUUID } from '../utils/validation';

// Constants
const RATE_LIMIT_WINDOW = 3600; // 1 hour in seconds
const RATE_LIMIT_MAX = 100; // Maximum requests per window
const BULK_OPERATION_LIMIT = 50; // Maximum items per bulk operation

/**
 * Enhanced error response interface
 */
interface ErrorResponse {
  status: 'error';
  code: number;
  message: string;
  details?: any;
}

/**
 * Success response interface with HATEOAS links
 */
interface SuccessResponse {
  status: 'success';
  data: any;
  links: {
    self: string;
    collection?: string;
    species?: string;
  };
}

/**
 * Controller handling discovery-related HTTP requests with enhanced validation and rate limiting
 */
export class DiscoveryController {
  private readonly discoveryService: DiscoveryService;
  private readonly router: Router;
  private readonly rateLimiter: RateLimiter;

  constructor(
    discoveryService: DiscoveryService,
    rateLimiter: RateLimiter
  ) {
    this.discoveryService = discoveryService;
    this.rateLimiter = rateLimiter;
    this.router = Router();
    this.initializeRoutes();
  }

  /**
   * Initializes controller routes with middleware
   */
  private initializeRoutes(): void {
    // Apply compression middleware
    this.router.use(compression());

    // Apply rate limiting to all routes
    this.router.use(this.rateLimiter.create({
      windowMs: RATE_LIMIT_WINDOW * 1000,
      max: RATE_LIMIT_MAX,
      message: 'Too many requests, please try again later',
      standardHeaders: true,
      legacyHeaders: false
    }));

    // Discovery routes
    this.router.post('/', this.createDiscovery.bind(this));
    this.router.post('/bulk', this.bulkCreateDiscoveries.bind(this));
    this.router.get('/:discoveryId', this.getDiscovery.bind(this));
    this.router.get('/collection/:collectionId', this.getDiscoveriesByCollection.bind(this));
    this.router.put('/:discoveryId', this.updateDiscovery.bind(this));
    this.router.delete('/:discoveryId', this.deleteDiscovery.bind(this));
    this.router.post('/:discoveryId/sync', this.syncDiscovery.bind(this));

    // Error handling middleware
    this.router.use(this.errorHandler.bind(this));
  }

  /**
   * Creates a new discovery with validation and automatic biodiversity sync
   */
  private async createDiscovery(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      // Validate request body
      const isValid = await validateDiscovery(req.body);
      if (!isValid) {
        throw new Error('Invalid discovery data');
      }

      // Create discovery
      const discovery = await this.discoveryService.createDiscovery(req.body);

      // Generate HATEOAS links
      const links = {
        self: `/api/v1/discoveries/${discovery.discovery_id}`,
        collection: `/api/v1/collections/${discovery.collection_id}`,
        species: `/api/v1/species/${discovery.species_id}`
      };

      // Send response
      const response: SuccessResponse = {
        status: 'success',
        data: discovery,
        links
      };

      res.status(201).json(response);
    } catch (error) {
      next(error);
    }
  }

  /**
   * Handles bulk creation of discoveries with batch processing
   */
  private async bulkCreateDiscoveries(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const { discoveries } = req.body;

      // Validate bulk request
      if (!Array.isArray(discoveries) || discoveries.length === 0) {
        throw new Error('Invalid bulk discovery data');
      }

      if (discoveries.length > BULK_OPERATION_LIMIT) {
        throw new Error(`Cannot process more than ${BULK_OPERATION_LIMIT} discoveries at once`);
      }

      // Process discoveries in batches
      const results = await this.discoveryService.bulkCreateDiscoveries(discoveries);

      // Send response with processing results
      res.status(207).json({
        status: 'success',
        data: {
          total: discoveries.length,
          successful: results.filter(r => r.success).length,
          failed: results.filter(r => !r.success).length,
          results
        }
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * Retrieves a discovery by ID with caching
   */
  private async getDiscovery(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const { discoveryId } = req.params;

      // Validate UUID format
      if (!validateUUID(discoveryId)) {
        throw new Error('Invalid discovery ID format');
      }

      // Get discovery
      const discovery = await this.discoveryService.getDiscoveryById(discoveryId);
      if (!discovery) {
        res.status(404).json({
          status: 'error',
          code: 404,
          message: 'Discovery not found'
        });
        return;
      }

      // Generate HATEOAS links
      const links = {
        self: `/api/v1/discoveries/${discovery.discovery_id}`,
        collection: `/api/v1/collections/${discovery.collection_id}`,
        species: `/api/v1/species/${discovery.species_id}`
      };

      res.json({
        status: 'success',
        data: discovery,
        links
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * Retrieves discoveries by collection ID with filtering and pagination
   */
  private async getDiscoveriesByCollection(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const { collectionId } = req.params;
      const { species_id, confidence_min, date_from, date_to } = req.query;

      // Validate UUID format
      if (!validateUUID(collectionId)) {
        throw new Error('Invalid collection ID format');
      }

      // Build filters
      const filters = {
        species_id: species_id as string,
        confidence_min: confidence_min ? parseFloat(confidence_min as string) : undefined,
        date_from: date_from ? new Date(date_from as string) : undefined,
        date_to: date_to ? new Date(date_to as string) : undefined
      };

      // Get discoveries
      const discoveries = await this.discoveryService.getDiscoveriesByCollection(collectionId, filters);

      res.json({
        status: 'success',
        data: discoveries,
        links: {
          self: `/api/v1/discoveries/collection/${collectionId}`
        }
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * Updates a discovery with validation
   */
  private async updateDiscovery(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const { discoveryId } = req.params;

      // Validate UUID and request body
      if (!validateUUID(discoveryId)) {
        throw new Error('Invalid discovery ID format');
      }

      const isValid = await validateDiscovery(req.body);
      if (!isValid) {
        throw new Error('Invalid discovery data');
      }

      // Update discovery
      const discovery = await this.discoveryService.updateDiscovery(discoveryId, req.body);

      res.json({
        status: 'success',
        data: discovery,
        links: {
          self: `/api/v1/discoveries/${discovery.discovery_id}`
        }
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * Deletes a discovery and associated data
   */
  private async deleteDiscovery(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const { discoveryId } = req.params;

      // Validate UUID format
      if (!validateUUID(discoveryId)) {
        throw new Error('Invalid discovery ID format');
      }

      // Delete discovery
      await this.discoveryService.deleteDiscovery(discoveryId);

      res.status(204).send();
    } catch (error) {
      next(error);
    }
  }

  /**
   * Manually triggers biodiversity database synchronization
   */
  private async syncDiscovery(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const { discoveryId } = req.params;

      // Validate UUID format
      if (!validateUUID(discoveryId)) {
        throw new Error('Invalid discovery ID format');
      }

      // Get discovery
      const discovery = await this.discoveryService.getDiscoveryById(discoveryId);
      if (!discovery) {
        throw new Error('Discovery not found');
      }

      // Trigger sync
      await this.discoveryService.syncWithBiodiversityDatabases(discovery);

      res.json({
        status: 'success',
        message: 'Synchronization initiated',
        links: {
          self: `/api/v1/discoveries/${discoveryId}`
        }
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * Global error handler middleware
   */
  private errorHandler(error: Error, req: Request, res: Response, next: NextFunction): void {
    console.error('Error:', error);

    const errorResponse: ErrorResponse = {
      status: 'error',
      code: 500,
      message: 'Internal server error'
    };

    if (error instanceof z.ZodError) {
      errorResponse.code = 400;
      errorResponse.message = 'Validation error';
      errorResponse.details = error.errors;
    }

    res.status(errorResponse.code).json(errorResponse);
  }

  /**
   * Returns the configured router instance
   */
  public getRouter(): Router {
    return this.router;
  }
}

// Export controller
export default DiscoveryController;