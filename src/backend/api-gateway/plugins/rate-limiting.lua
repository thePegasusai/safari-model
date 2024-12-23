-- Rate Limiting Plugin for Wildlife Detection Safari Pokédex
-- Version: 1.0.0
-- Kong Version: 3.3
-- Redis Version: 7.0

local kong = require "kong"
local redis = require "kong.plugins.rate-limiting.policies.redis"
local timestamp = require "kong.tools.timestamp"

-- Plugin configuration
local plugin = {
  PRIORITY = 900,
  VERSION = "1.0.0",
  name = "rate-limiting"
}

-- Endpoint-specific rate limits (requests per minute)
local ENDPOINT_LIMITS = {
  ["/api/v1/detect"] = 60,
  ["/api/v1/collections"] = 120,
  ["/api/v1/species"] = 300,
  ["/api/v1/sync"] = 30,
  ["/api/v1/media"] = 100
}

-- Redis connection configuration
local REDIS_CONFIG = {
  host = "redis",
  port = 6379,
  timeout = 2000,
  database = 0,
  pool_size = 30
}

-- RateLimitingHandler class implementation
local RateLimitingHandler = {
  PRIORITY = 900
}

-- Constructor for RateLimitingHandler
function RateLimitingHandler:new(config)
  local self = {
    config = config or {},
    redis_client = nil,
    fallback_store = {},
    sync_manager = {},
    monitoring = {}
  }
  
  -- Initialize Redis connection pool
  self.redis_client = redis:new(REDIS_CONFIG)
  
  -- Set up monitoring
  self.monitoring = {
    counters = {},
    errors = {},
    last_sync = 0
  }
  
  return setmetatable(self, { __index = RateLimitingHandler })
end

-- Calculate window boundaries for sliding window rate limiting
local function calculate_window(current_timestamp, window_size)
  local window_start = math.floor(current_timestamp / window_size) * window_size
  return window_start, window_start + window_size
end

-- Generate rate limit key
local function generate_key(identifier, window_start)
  return string.format("ratelimit:%s:%d", identifier, window_start)
end

-- Increment counter with Redis
function RateLimitingHandler:increment_counter(identifier, window_size)
  local current_timestamp = timestamp.get_utc()
  local window_start, _ = calculate_window(current_timestamp, window_size)
  local key = generate_key(identifier, window_start)
  
  local success, count = pcall(function()
    return self.redis_client:incr(key)
  end)
  
  if not success then
    kong.log.err("Redis increment failed: ", count)
    -- Fallback to local counter
    self.fallback_store[key] = (self.fallback_store[key] or 0) + 1
    return self.fallback_store[key]
  end
  
  -- Set expiry for Redis key
  self.redis_client:expire(key, window_size * 2)
  
  return count
end

-- Check rate limit
function RateLimitingHandler:check_limit(conf, identifier)
  local route_path = kong.request.get_path()
  local limit = ENDPOINT_LIMITS[route_path] or 60 -- Default limit
  local window_size = 60 -- 1 minute window
  
  local count = self:increment_counter(identifier, window_size)
  local allowed = count <= limit
  
  -- Update monitoring metrics
  self.monitoring.counters[identifier] = count
  
  return allowed, count, limit
end

-- Access phase handler
function RateLimitingHandler:access(conf)
  local consumer_id = kong.client.get_consumer()
  local identifier = consumer_id or kong.client.get_forwarded_ip()
  
  local allowed, count, limit = self:check_limit(conf, identifier)
  
  if not allowed then
    return kong.response.error(429, "API rate limit exceeded")
  end
  
  -- Set rate limit headers
  kong.service.request.set_header("X-RateLimit-Limit", limit)
  kong.service.request.set_header("X-RateLimit-Remaining", math.max(0, limit - count))
  kong.service.request.set_header("X-RateLimit-Reset", calculate_window(timestamp.get_utc(), 60))
end

-- Header filter phase handler
function RateLimitingHandler:header_filter(conf)
  local headers = kong.response.get_headers()
  local limit = headers["X-RateLimit-Limit"]
  local remaining = headers["X-RateLimit-Remaining"]
  local reset = headers["X-RateLimit-Reset"]
  
  if limit then
    kong.response.set_header("X-RateLimit-Limit", limit)
    kong.response.set_header("X-RateLimit-Remaining", remaining)
    kong.response.set_header("X-RateLimit-Reset", reset)
  end
  
  -- Add retry-after header if rate limited
  if kong.response.get_status() == 429 then
    kong.response.set_header("Retry-After", reset - timestamp.get_utc())
  end
end

-- Log phase handler
function RateLimitingHandler:log(conf)
  -- Log rate limiting metrics for monitoring
  if conf.monitoring_enabled then
    kong.log.debug("Rate limiting metrics: ", kong.table.to_string(self.monitoring))
  end
end

-- Plugin schema
local schema = {
  name = plugin.name,
  fields = {
    { config = {
        type = "record",
        fields = {
          { redis_host = { type = "string", default = "redis" }},
          { redis_port = { type = "number", default = 6379 }},
          { redis_timeout = { type = "number", default = 2000 }},
          { redis_database = { type = "number", default = 0 }},
          { fault_tolerant = { type = "boolean", default = true }},
          { monitoring_enabled = { type = "boolean", default = true }},
          { sync_interval = { type = "number", default = 1000 }}
        }
    }}
  }
}

-- Export plugin
return {
  PRIORITY = plugin.PRIORITY,
  VERSION = plugin.VERSION,
  name = plugin.name,
  schema = schema,
  handler = RateLimitingHandler
}