import Redis, { RedisOptions } from 'ioredis'; // v5.3.2
import { config } from 'dotenv'; // v16.3.1
import { EventEmitter } from 'events';

// Load environment variables
config();

// Interface for Redis configuration with high availability options
export interface RedisConfig {
  host: string;
  port: number;
  password: string;
  db: number;
  enableTLS: boolean;
  sentinels: Array<{ host: string; port: number }>;
  maxReconnectAttempts: number;
}

// Optimized Redis client configuration options
const REDIS_OPTIONS: RedisOptions = {
  retryStrategy: (times: number) => {
    const delay = Math.min(times * 50, 2000);
    return times <= 3 ? delay : null;
  },
  maxRetriesPerRequest: 3,
  enableReadyCheck: true,
  connectTimeout: 10000,
  keepAlive: 30000,
  keyPrefix: 'collection:',
  lazyConnect: true,
  enableOfflineQueue: true,
  connectionPoolSize: 10,
  autoResubscribe: true,
  autoResendUnfulfilledCommands: true,
  sentinelRetryStrategy: true,
  tls: process.env.REDIS_ENABLE_TLS === 'true' ? {
    rejectUnauthorized: true
  } : undefined
};

// Create Redis configuration from environment variables
const createRedisConfig = (): RedisConfig => {
  const sentinels = process.env.REDIS_SENTINELS ? 
    JSON.parse(process.env.REDIS_SENTINELS) : [];

  return {
    host: process.env.REDIS_HOST || 'localhost',
    port: parseInt(process.env.REDIS_PORT || '6379', 10),
    password: process.env.REDIS_PASSWORD || '',
    db: parseInt(process.env.REDIS_DB || '0', 10),
    enableTLS: process.env.REDIS_ENABLE_TLS === 'true',
    sentinels,
    maxReconnectAttempts: parseInt(process.env.REDIS_MAX_RECONNECT_ATTEMPTS || '3', 10)
  };
};

// Create and configure Redis client with high availability support
const createRedisClient = async (): Promise<Redis> => {
  const config = createRedisConfig();
  let client: Redis;

  if (config.sentinels && config.sentinels.length > 0) {
    // Configure sentinel-based connection
    client = new Redis({
      ...REDIS_OPTIONS,
      sentinels: config.sentinels,
      name: 'mymaster',
      password: config.password,
      db: config.db,
      sentinelPassword: process.env.REDIS_SENTINEL_PASSWORD
    });
  } else {
    // Configure standalone connection
    client = new Redis({
      ...REDIS_OPTIONS,
      host: config.host,
      port: config.port,
      password: config.password,
      db: config.db
    });
  }

  // Configure error handling
  client.on('error', (error: Error) => {
    console.error('Redis client error:', error);
    // Emit error event for monitoring
    EventEmitter.defaultMaxListeners = 15;
    client.emit('clientError', error);
  });

  // Configure connection handling
  client.on('connect', () => {
    console.info('Redis client connected');
  });

  client.on('ready', () => {
    console.info('Redis client ready');
  });

  client.on('close', () => {
    console.warn('Redis client connection closed');
  });

  // Configure sentinel events if using sentinel
  if (config.sentinels && config.sentinels.length > 0) {
    client.on('+switch-master', (master: string) => {
      console.info(`Redis sentinel switched to new master: ${master}`);
    });
  }

  return client;
};

// Validate Redis connection health
const validateRedisConnection = async (client: Redis): Promise<boolean> => {
  try {
    // Perform basic health check
    const pingResponse = await client.ping();
    if (pingResponse !== 'PONG') {
      throw new Error('Redis ping failed');
    }

    // Check memory usage
    const info = await client.info('memory');
    const usedMemory = parseInt(info.match(/used_memory:(\d+)/)?.[1] || '0', 10);
    const maxMemory = parseInt(info.match(/maxmemory:(\d+)/)?.[1] || '0', 10);

    if (maxMemory > 0 && usedMemory / maxMemory > 0.9) {
      console.warn('Redis memory usage above 90%');
    }

    // Check client connections
    const clientInfo = await client.info('clients');
    const connectedClients = parseInt(clientInfo.match(/connected_clients:(\d+)/)?.[1] || '0', 10);

    if (connectedClients >= parseInt(process.env.REDIS_MAX_CLIENTS || '10000', 10)) {
      console.warn('Redis client connections near limit');
    }

    return true;
  } catch (error) {
    console.error('Redis health check failed:', error);
    return false;
  }
};

// Create and export Redis client instance
export const redisClient = await createRedisClient();

// Export connection validation utility
export const validateConnection = async (): Promise<boolean> => {
  return validateRedisConnection(redisClient);
};

// Export Redis client type for type safety
export type RedisClient = Redis;

// Export configured Redis instance with common operations
export default {
  get: redisClient.get.bind(redisClient),
  set: redisClient.set.bind(redisClient),
  del: redisClient.del.bind(redisClient),
  connect: redisClient.connect.bind(redisClient),
  disconnect: redisClient.disconnect.bind(redisClient),
  getConnectionStatus: validateConnection
};