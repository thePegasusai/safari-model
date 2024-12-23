import { Pool, PoolConfig } from 'pg'; // v8.11.3
import { config } from 'dotenv'; // v16.3.1
import { EventEmitter } from 'events';

// Load environment variables
config();

// Interface for enhanced database configuration
export interface DatabaseConfig {
  host: string;
  port: number;
  database: string;
  user: string;
  password: string;
  ssl: boolean;
  connectionTimeout: number;
  statementTimeout: number;
  keepAlive: boolean;
}

// Enhanced pool configuration with optimized settings
const POOL_CONFIG: PoolConfig = {
  max: 20, // Maximum number of clients in the pool
  min: 4, // Minimum number of idle clients maintained in the pool
  idleTimeoutMillis: 30000, // How long a client is allowed to remain idle before being closed
  connectionTimeoutMillis: 2000, // How long to wait when connecting a new client
  allowExitOnIdle: false, // Prevents the pool from closing while being idle
  keepAlive: true, // Enables TCP Keep-Alive
  statement_timeout: 10000, // Statement timeout in milliseconds
  query_timeout: 5000, // Query timeout in milliseconds
  ssl: {
    rejectUnauthorized: true, // Enforce valid SSL certificates
    checkServerIdentity: true // Validate server identity
  }
};

// Event emitter for pool monitoring
const poolEvents = new EventEmitter();

/**
 * Validates database connection with comprehensive health checks
 * @param pool - Database connection pool
 * @returns Promise<boolean> - Connection status
 */
async function validateConnection(pool: Pool): Promise<boolean> {
  try {
    // Test query to validate connection
    await pool.query('SELECT 1');
    
    // Validate pool metrics
    const poolStatus = await pool.query(`
      SELECT count(*) as connection_count 
      FROM pg_stat_activity 
      WHERE datname = $1
    `, [process.env.POSTGRES_DB]);

    // Check SSL status
    const sslStatus = await pool.query('SHOW ssl');
    
    if (sslStatus.rows[0].ssl !== 'on') {
      throw new Error('SSL is not enabled for the connection');
    }

    return true;
  } catch (error) {
    poolEvents.emit('connectionError', error);
    return false;
  }
}

/**
 * Initializes and configures the database connection pool with advanced features
 * @returns Promise<Pool> - Configured database pool instance
 */
async function initializePool(): Promise<Pool> {
  // Validate required environment variables
  const requiredEnvVars = [
    'POSTGRES_HOST',
    'POSTGRES_PORT',
    'POSTGRES_DB',
    'POSTGRES_USER',
    'POSTGRES_PASSWORD'
  ];

  for (const envVar of requiredEnvVars) {
    if (!process.env[envVar]) {
      throw new Error(`Missing required environment variable: ${envVar}`);
    }
  }

  // Create database configuration
  const dbConfig: DatabaseConfig = {
    host: process.env.POSTGRES_HOST!,
    port: parseInt(process.env.POSTGRES_PORT!, 10),
    database: process.env.POSTGRES_DB!,
    user: process.env.POSTGRES_USER!,
    password: process.env.POSTGRES_PASSWORD!,
    ssl: process.env.NODE_ENV === 'production',
    connectionTimeout: 2000,
    statementTimeout: 10000,
    keepAlive: true
  };

  // Initialize pool with merged configuration
  const pool = new Pool({
    ...POOL_CONFIG,
    ...dbConfig
  });

  // Set up error handling
  pool.on('error', (err, client) => {
    poolEvents.emit('poolError', { error: err, client });
    console.error('Unexpected error on idle client', err);
  });

  // Set up connection monitoring
  pool.on('connect', (client) => {
    poolEvents.emit('newConnection', { pid: client.processID });
    
    client.on('error', (err) => {
      poolEvents.emit('clientError', { error: err, pid: client.processID });
    });

    client.on('notice', (notice) => {
      poolEvents.emit('notice', notice);
    });
  });

  // Validate initial connection
  const isValid = await validateConnection(pool);
  if (!isValid) {
    throw new Error('Failed to establish initial database connection');
  }

  // Set up health check interval
  setInterval(async () => {
    try {
      await validateConnection(pool);
    } catch (error) {
      poolEvents.emit('healthCheckError', error);
    }
  }, 30000); // Check every 30 seconds

  return pool;
}

// Initialize the pool
const pool = await initializePool();

// Export configured pool instance and types
export { pool, DatabaseConfig };

// Error handling setup for pool events
poolEvents.on('poolError', ({ error, client }) => {
  console.error('Pool error:', error);
  // Implement error reporting to monitoring service
});

poolEvents.on('connectionError', (error) => {
  console.error('Connection error:', error);
  // Implement connection retry logic with exponential backoff
});

poolEvents.on('clientError', ({ error, pid }) => {
  console.error(`Client error on process ${pid}:`, error);
  // Implement client-specific error handling
});

poolEvents.on('healthCheckError', (error) => {
  console.error('Health check failed:', error);
  // Trigger alerts and failover procedures if necessary
});

// Graceful shutdown handler
process.on('SIGTERM', async () => {
  console.log('Received SIGTERM - Closing pool');
  try {
    await pool.end();
    console.log('Pool has been closed');
  } catch (err) {
    console.error('Error during pool shutdown:', err);
    process.exit(1);
  }
  process.exit(0);
});