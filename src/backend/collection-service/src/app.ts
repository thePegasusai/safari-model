import express, { Express, Request, Response, NextFunction } from 'express'; // v4.18.2
import helmet from 'helmet'; // v7.0.0
import cors from 'cors'; // v2.8.5
import morgan from 'morgan'; // v1.10.0
import compression from 'compression'; // v1.7.4
import rateLimit from 'express-rate-limit'; // v7.1.0
import { pool } from './config/database';
import { redisClient } from './config/redis';

// Constants for application configuration
const PORT = process.env.PORT || 3000;
const API_VERSION = 'v1';
const CORS_WHITELIST = process.env.CORS_WHITELIST?.split(',') || [];
const RATE_LIMIT_WINDOW = 15 * 60 * 1000; // 15 minutes
const RATE_LIMIT_MAX = 100;

/**
 * Custom error class for API errors
 */
class APIError extends Error {
  constructor(
    public statusCode: number,
    message: string,
    public code?: string
  ) {
    super(message);
    this.name = 'APIError';
  }
}

/**
 * Initialize Express application with security and performance middleware
 */
const initializeApp = (): Express => {
  const app = express();

  // Security middleware
  app.use(helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        scriptSrc: ["'self'"],
        styleSrc: ["'self'"],
        imgSrc: ["'self'", 'data:', 'https:'],
        connectSrc: ["'self'"],
        fontSrc: ["'self'"],
        objectSrc: ["'none'"],
        mediaSrc: ["'self'"],
        frameSrc: ["'none'"]
      }
    },
    crossOriginEmbedderPolicy: true,
    crossOriginOpenerPolicy: true,
    crossOriginResourcePolicy: { policy: "same-site" },
    dnsPrefetchControl: { allow: false },
    expectCt: { enforce: true, maxAge: 30 },
    frameguard: { action: "deny" },
    hidePoweredBy: true,
    hsts: { maxAge: 31536000, includeSubDomains: true, preload: true },
    ieNoOpen: true,
    noSniff: true,
    originAgentCluster: true,
    permittedCrossDomainPolicies: { permittedPolicies: "none" },
    referrerPolicy: { policy: "strict-origin-when-cross-origin" },
    xssFilter: true
  }));

  // CORS configuration
  app.use(cors({
    origin: (origin, callback) => {
      if (!origin || CORS_WHITELIST.includes(origin)) {
        callback(null, true);
      } else {
        callback(new Error('Not allowed by CORS'));
      }
    },
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
    credentials: true,
    maxAge: 600 // 10 minutes
  }));

  // Performance middleware
  app.use(compression());
  app.use(express.json({ limit: '10kb' }));
  app.use(express.urlencoded({ extended: true, limit: '10kb' }));

  // Request logging with performance metrics
  app.use(morgan(':method :url :status :response-time ms - :res[content-length]', {
    skip: (req) => req.url === '/health'
  }));

  // Rate limiting
  const limiter = rateLimit({
    windowMs: RATE_LIMIT_WINDOW,
    max: RATE_LIMIT_MAX,
    standardHeaders: true,
    legacyHeaders: false,
    message: 'Too many requests from this IP, please try again later.'
  });
  app.use(`/api/${API_VERSION}`, limiter);

  // Health check endpoint
  app.get('/health', async (req: Request, res: Response) => {
    try {
      await pool.query('SELECT 1');
      await redisClient.ping();
      res.status(200).json({ status: 'healthy', timestamp: new Date().toISOString() });
    } catch (error) {
      res.status(503).json({ status: 'unhealthy', error: error.message });
    }
  });

  // API routes will be mounted here
  app.use(`/api/${API_VERSION}`, (req: Request, res: Response) => {
    res.status(200).json({ message: 'Collection Service API' });
  });

  // Error handling middleware
  app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
    console.error('Error:', err);

    if (err instanceof APIError) {
      return res.status(err.statusCode).json({
        status: 'error',
        code: err.code,
        message: err.message
      });
    }

    return res.status(500).json({
      status: 'error',
      message: 'Internal server error'
    });
  });

  // 404 handler
  app.use((req: Request, res: Response) => {
    res.status(404).json({
      status: 'error',
      message: 'Resource not found'
    });
  });

  return app;
};

/**
 * Start server with graceful shutdown handling
 */
const startServer = async (app: Express): Promise<void> => {
  const server = app.listen(PORT, () => {
    console.log(`Collection Service listening on port ${PORT}`);
  });

  // Graceful shutdown handler
  const gracefulShutdown = async (signal: string) => {
    console.log(`Received ${signal}. Starting graceful shutdown...`);

    server.close(async () => {
      try {
        await pool.end();
        await redisClient.disconnect();
        console.log('Graceful shutdown completed');
        process.exit(0);
      } catch (error) {
        console.error('Error during shutdown:', error);
        process.exit(1);
      }
    });

    // Force shutdown after timeout
    setTimeout(() => {
      console.error('Forced shutdown due to timeout');
      process.exit(1);
    }, 30000);
  };

  // Register shutdown handlers
  process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
  process.on('SIGINT', () => gracefulShutdown('SIGINT'));

  // Unhandled rejection handler
  process.on('unhandledRejection', (reason: Error) => {
    console.error('Unhandled Rejection:', reason);
    // Implement error reporting to monitoring service
  });
};

// Initialize and start application
const app = initializeApp();
await startServer(app);

export { app };