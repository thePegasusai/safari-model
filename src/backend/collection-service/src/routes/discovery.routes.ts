// External dependencies
import { Router, Request, Response, NextFunction } from 'express'; // v4.18.2
import asyncHandler from 'express-async-handler'; // v1.2.0
import { authenticate } from 'express-jwt'; // v8.4.1
import rateLimit from 'express-rate-limit'; // v6.9.0
import cache from 'express-cache-controller'; // v1.1.0

// Internal dependencies
import { DiscoveryController } from '../controllers/discovery.controller';
import { validateDiscovery, validateUUID } from '../utils/validation';

// Constants
const ROUTE_PREFIX = '/api/v1';
const RATE_LIMIT_WINDOW = 60000; // 1 minute in milliseconds
const RATE_LIMIT_MAX = 1000; // Maximum requests per window
const CACHE_DURATION = 300; // 5 minutes in seconds
const BULK_LIMIT = 100; // Maximum items for bulk operations

/**
 * Configures discovery routes with enhanced security and performance features
 * @param controller - Instance of DiscoveryController
 * @returns Configured Express router
 */
export function configureDiscoveryRoutes(controller: DiscoveryController): Router {
    const router = Router();

    // Configure rate limiters
    const standardLimiter = rateLimit({
        windowMs: RATE_LIMIT_WINDOW,
        max: RATE_LIMIT_MAX,
        message: 'Too many requests, please try again later',
        standardHeaders: true,
        legacyHeaders: false
    });

    const bulkLimiter = rateLimit({
        windowMs: RATE_LIMIT_WINDOW,
        max: 10, // Stricter limit for bulk operations
        message: 'Too many bulk operations, please try again later'
    });

    // Authentication middleware
    router.use(authenticate({
        secret: process.env.JWT_SECRET!,
        algorithms: ['RS256']
    }));

    // Standard discovery routes
    router.post(
        `${ROUTE_PREFIX}/discoveries`,
        standardLimiter,
        asyncHandler(async (req: Request, res: Response, next: NextFunction) => {
            // Validate request body
            const isValid = await validateDiscovery(req.body);
            if (!isValid) {
                res.status(400).json({
                    status: 'error',
                    message: 'Invalid discovery data'
                });
                return;
            }

            const result = await controller.createDiscovery(req.body);
            res.status(201).json({
                status: 'success',
                data: result
            });
        })
    );

    // Bulk discovery creation
    router.post(
        `${ROUTE_PREFIX}/discoveries/bulk`,
        bulkLimiter,
        asyncHandler(async (req: Request, res: Response, next: NextFunction) => {
            const { discoveries } = req.body;

            if (!Array.isArray(discoveries) || discoveries.length > BULK_LIMIT) {
                res.status(400).json({
                    status: 'error',
                    message: `Bulk operations limited to ${BULK_LIMIT} items`
                });
                return;
            }

            const result = await controller.createBulkDiscoveries(discoveries);
            res.status(207).json({
                status: 'success',
                data: result
            });
        })
    );

    // Get single discovery with caching
    router.get(
        `${ROUTE_PREFIX}/discoveries/:id`,
        cache(`public, max-age=${CACHE_DURATION}`),
        asyncHandler(async (req: Request, res: Response, next: NextFunction) => {
            if (!validateUUID(req.params.id)) {
                res.status(400).json({
                    status: 'error',
                    message: 'Invalid discovery ID format'
                });
                return;
            }

            const discovery = await controller.getDiscovery(req.params.id);
            if (!discovery) {
                res.status(404).json({
                    status: 'error',
                    message: 'Discovery not found'
                });
                return;
            }

            res.json({
                status: 'success',
                data: discovery
            });
        })
    );

    // Get collection discoveries with pagination
    router.get(
        `${ROUTE_PREFIX}/collections/:id/discoveries`,
        standardLimiter,
        asyncHandler(async (req: Request, res: Response, next: NextFunction) => {
            if (!validateUUID(req.params.id)) {
                res.status(400).json({
                    status: 'error',
                    message: 'Invalid collection ID format'
                });
                return;
            }

            const { page = '1', limit = '50', sort = 'created_at' } = req.query;
            const options = {
                page: parseInt(page as string),
                limit: Math.min(parseInt(limit as string), 100),
                sort: sort as string
            };

            const discoveries = await controller.getCollectionDiscoveries(
                req.params.id,
                options
            );

            res.json({
                status: 'success',
                data: discoveries
            });
        })
    );

    // Update discovery
    router.put(
        `${ROUTE_PREFIX}/discoveries/:id`,
        standardLimiter,
        asyncHandler(async (req: Request, res: Response, next: NextFunction) => {
            if (!validateUUID(req.params.id)) {
                res.status(400).json({
                    status: 'error',
                    message: 'Invalid discovery ID format'
                });
                return;
            }

            const isValid = await validateDiscovery(req.body);
            if (!isValid) {
                res.status(400).json({
                    status: 'error',
                    message: 'Invalid discovery data'
                });
                return;
            }

            const result = await controller.updateDiscovery(req.params.id, req.body);
            res.json({
                status: 'success',
                data: result
            });
        })
    );

    // Delete discovery
    router.delete(
        `${ROUTE_PREFIX}/discoveries/:id`,
        standardLimiter,
        asyncHandler(async (req: Request, res: Response, next: NextFunction) => {
            if (!validateUUID(req.params.id)) {
                res.status(400).json({
                    status: 'error',
                    message: 'Invalid discovery ID format'
                });
                return;
            }

            await controller.deleteDiscovery(req.params.id);
            res.status(204).send();
        })
    );

    // Manual biodiversity database sync
    router.post(
        `${ROUTE_PREFIX}/discoveries/:id/sync`,
        standardLimiter,
        asyncHandler(async (req: Request, res: Response, next: NextFunction) => {
            if (!validateUUID(req.params.id)) {
                res.status(400).json({
                    status: 'error',
                    message: 'Invalid discovery ID format'
                });
                return;
            }

            await controller.syncWithBiodiversityDB(req.params.id);
            res.json({
                status: 'success',
                message: 'Synchronization initiated'
            });
        })
    );

    // Error handling middleware
    router.use((err: Error, req: Request, res: Response, next: NextFunction) => {
        console.error('Route error:', err);
        res.status(500).json({
            status: 'error',
            message: 'Internal server error'
        });
    });

    return router;
}

export default configureDiscoveryRoutes;