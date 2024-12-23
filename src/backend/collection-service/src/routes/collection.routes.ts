// External dependencies
import { Router } from 'express'; // v4.18.2
import { expressjwt as authenticate } from 'express-jwt'; // v8.4.1
import rateLimit from 'express-rate-limit'; // v6.9.0
import compression from 'compression'; // v1.7.4
import cors from 'cors'; // v2.8.5
import helmet from 'helmet'; // v7.0.0

// Internal dependencies
import { CollectionController } from '../controllers/collection.controller';
import { validateCollection, validateUUID } from '../utils/validation';

// Constants for rate limiting and security
const RATE_LIMIT_WINDOW_MS = 60000; // 1 minute
const MAX_REQUESTS_PER_WINDOW = 120; // 120 requests per minute
const CORS_ALLOWED_ORIGINS = ['https://api.wildlifesafari.com'];
const REQUEST_TIMEOUT_MS = 5000;

/**
 * Configures and returns Express router with secured collection endpoints
 * @returns Router - Configured Express router instance
 */
const configureCollectionRoutes = (): Router => {
  const router = Router();
  const collectionController = new CollectionController();

  // Apply security middleware
  router.use(helmet({
    xssFilter: true,
    noSniff: true,
    hidePoweredBy: true,
    hsts: {
      maxAge: 31536000,
      includeSubDomains: true,
      preload: true
    }
  }));

  // Configure CORS
  router.use(cors({
    origin: CORS_ALLOWED_ORIGINS,
    methods: ['GET', 'POST', 'PUT', 'DELETE'],
    allowedHeaders: ['Content-Type', 'Authorization'],
    exposedHeaders: ['X-Total-Count', 'X-Request-ID'],
    maxAge: 86400, // 24 hours
    credentials: true
  }));

  // Apply compression for response optimization
  router.use(compression({
    level: 6,
    threshold: '1kb',
    filter: (req, res) => {
      if (req.headers['x-no-compression']) {
        return false;
      }
      return compression.filter(req, res);
    }
  }));

  // Configure rate limiting
  const limiter = rateLimit({
    windowMs: RATE_LIMIT_WINDOW_MS,
    max: MAX_REQUESTS_PER_WINDOW,
    standardHeaders: true,
    legacyHeaders: false,
    message: {
      status: 'error',
      message: 'Too many requests, please try again later.'
    }
  });
  router.use(limiter);

  // JWT Authentication middleware
  router.use(authenticate({
    secret: process.env.JWT_PUBLIC_KEY!,
    algorithms: ['RS256'],
    requestProperty: 'user',
    getToken: (req) => {
      if (req.headers.authorization?.split(' ')[0] === 'Bearer') {
        return req.headers.authorization.split(' ')[1];
      }
      return null;
    }
  }));

  // Collection routes with validation and error handling
  router.get('/collections', async (req, res, next) => {
    try {
      const page = parseInt(req.query.page as string) || 1;
      const limit = parseInt(req.query.limit as string) || 50;
      
      if (page < 1 || limit < 1 || limit > 100) {
        return res.status(400).json({
          status: 'error',
          message: 'Invalid pagination parameters'
        });
      }

      await collectionController.getUserCollections(req, res);
    } catch (error) {
      next(error);
    }
  });

  router.get('/collections/:id', async (req, res, next) => {
    try {
      if (!validateUUID(req.params.id)) {
        return res.status(400).json({
          status: 'error',
          message: 'Invalid collection ID format'
        });
      }

      await collectionController.getCollection(req, res);
    } catch (error) {
      next(error);
    }
  });

  router.post('/collections', async (req, res, next) => {
    try {
      if (!await validateCollection(req.body)) {
        return res.status(400).json({
          status: 'error',
          message: 'Invalid collection data'
        });
      }

      await collectionController.createCollection(req, res);
    } catch (error) {
      next(error);
    }
  });

  router.put('/collections/:id', async (req, res, next) => {
    try {
      if (!validateUUID(req.params.id)) {
        return res.status(400).json({
          status: 'error',
          message: 'Invalid collection ID format'
        });
      }

      if (!await validateCollection(req.body)) {
        return res.status(400).json({
          status: 'error',
          message: 'Invalid collection data'
        });
      }

      await collectionController.updateCollection(req, res);
    } catch (error) {
      next(error);
    }
  });

  router.delete('/collections/:id', async (req, res, next) => {
    try {
      if (!validateUUID(req.params.id)) {
        return res.status(400).json({
          status: 'error',
          message: 'Invalid collection ID format'
        });
      }

      await collectionController.deleteCollection(req, res);
    } catch (error) {
      next(error);
    }
  });

  // Error handling middleware
  router.use((err: any, req: any, res: any, next: any) => {
    console.error('Route error:', err);

    // Handle JWT authentication errors
    if (err.name === 'UnauthorizedError') {
      return res.status(401).json({
        status: 'error',
        message: 'Invalid or expired token'
      });
    }

    // Handle validation errors
    if (err.name === 'ValidationError') {
      return res.status(400).json({
        status: 'error',
        message: 'Validation failed',
        errors: err.errors
      });
    }

    // Handle timeout errors
    if (err.name === 'TimeoutError') {
      return res.status(408).json({
        status: 'error',
        message: 'Request timeout'
      });
    }

    // Default error response
    res.status(500).json({
      status: 'error',
      message: 'Internal server error'
    });
  });

  return router;
};

// Export configured router
export const router = configureCollectionRoutes();