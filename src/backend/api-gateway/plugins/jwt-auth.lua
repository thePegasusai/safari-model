-- jwt-auth.lua
-- Kong plugin for JWT authentication with RS256 signature verification and Redis caching
-- Version: 1.0.0
-- External dependencies:
-- kong v3.3
-- kong.plugins.jwt.jwt_parser v3.3
-- kong.plugins.jwt-auth.redis v3.0

local kong = require "kong"
local jwt_parser = require "kong.plugins.jwt.jwt_parser"
local redis = require "kong.plugins.jwt-auth.redis"

-- Constants
local PLUGIN_NAME = "jwt-auth"
local PLUGIN_PRIORITY = 1000
local REDIS_TTL = 3600  -- 1 hour cache TTL
local TOKEN_EXPIRATION = 604800  -- 7 days

-- Security headers configuration
local SECURITY_HEADERS = {
    ["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains",
    ["Content-Security-Policy"] = "default-src 'self'",
    ["X-Frame-Options"] = "DENY",
    ["X-Content-Type-Options"] = "nosniff"
}

-- Plugin schema definition
local plugin_schema = {
    name = PLUGIN_NAME,
    fields = {
        {
            config = {
                type = "record",
                fields = {
                    {
                        redis_host = { type = "string", required = true },
                        redis_port = { type = "number", default = 6379 },
                        redis_password = { type = "string" },
                        redis_database = { type = "number", default = 0 },
                        redis_timeout = { type = "number", default = 2000 },
                        jwt_secret = { type = "string", required = true },
                        issuer = { type = "string", required = true },
                        algorithm = { type = "string", default = "RS256", one_of = { "RS256" } },
                        rate_limit_second = { type = "number", default = 10 },
                        rate_limit_hour = { type = "number", default = 3600 }
                    }
                }
            }
        }
    }
}

-- JWTAuthHandler class
local JWTAuthHandler = {
    PRIORITY = PLUGIN_PRIORITY,
    VERSION = "1.0.0"
}

-- Constructor
function JWTAuthHandler:new(config)
    local self = {
        config = config,
        redis_client = nil,
        rate_limiter = {}
    }
    
    -- Initialize Redis connection
    self.redis_client = redis:new({
        host = config.redis_host,
        port = config.redis_port,
        password = config.redis_password,
        database = config.redis_database,
        timeout = config.redis_timeout
    })
    
    return setmetatable(self, { __index = JWTAuthHandler })
end

-- Validate JWT token
local function validate_token(self, token)
    if not token then
        return nil, "missing token"
    end
    
    -- Check Redis cache first
    local cached_validation = self.redis_client:get("jwt:" .. token)
    if cached_validation then
        return true
    end
    
    -- Parse and validate token
    local jwt, err = jwt_parser:new(token)
    if not jwt then
        return nil, "invalid token: " .. err
    end
    
    -- Verify RS256 signature
    local verified, verify_err = jwt:verify_signature(self.config.jwt_secret)
    if not verified then
        return nil, "invalid signature: " .. verify_err
    end
    
    -- Validate claims
    local claims = jwt.claims
    if not claims then
        return nil, "invalid claims"
    end
    
    -- Check expiration
    if claims.exp and claims.exp < ngx.time() then
        return nil, "token expired"
    end
    
    -- Validate issuer
    if claims.iss ~= self.config.issuer then
        return nil, "invalid issuer"
    end
    
    -- Cache successful validation
    self.redis_client:set("jwt:" .. token, "1", "EX", REDIS_TTL)
    
    return true
end

-- Rate limiting check
local function check_rate_limit(self, consumer_id)
    local second_key = "ratelimit:second:" .. consumer_id
    local hour_key = "ratelimit:hour:" .. consumer_id
    
    local second_count = self.redis_client:incr(second_key)
    local hour_count = self.redis_client:incr(hour_key)
    
    if second_count == 1 then
        self.redis_client:expire(second_key, 1)
    end
    if hour_count == 1 then
        self.redis_client:expire(hour_key, 3600)
    end
    
    return second_count <= self.config.rate_limit_second and 
           hour_count <= self.config.rate_limit_hour
end

-- Access phase handler
function JWTAuthHandler:access(conf)
    -- Extract token from Authorization header
    local auth_header = kong.request.get_header("Authorization")
    if not auth_header then
        return kong.response.exit(401, { message = "missing authorization header" })
    end
    
    local _, _, token = string.find(auth_header, "Bearer%s+(.+)")
    if not token then
        return kong.response.exit(401, { message = "invalid authorization header format" })
    end
    
    -- Validate token
    local valid, err = validate_token(self, token)
    if not valid then
        return kong.response.exit(401, { message = err })
    end
    
    -- Check rate limits
    local consumer_id = jwt_parser:new(token).claims.sub
    if not check_rate_limit(self, consumer_id) then
        return kong.response.exit(429, { message = "rate limit exceeded" })
    end
    
    -- Set consumer ID for downstream plugins
    kong.service.request.set_header("X-Consumer-ID", consumer_id)
    
    -- Log successful authentication
    kong.log.info("JWT authentication successful for consumer: " .. consumer_id)
end

-- Header filter phase handler
function JWTAuthHandler:header_filter(conf)
    -- Add security headers
    for header, value in pairs(SECURITY_HEADERS) do
        kong.response.set_header(header, value)
    end
    
    -- Add rate limit headers
    local consumer_id = kong.request.get_header("X-Consumer-ID")
    if consumer_id then
        local second_remaining = self.redis_client:ttl("ratelimit:second:" .. consumer_id)
        local hour_remaining = self.redis_client:ttl("ratelimit:hour:" .. consumer_id)
        
        kong.response.set_header("X-RateLimit-Remaining-Second", second_remaining)
        kong.response.set_header("X-RateLimit-Remaining-Hour", hour_remaining)
    end
end

-- Plugin registration
return {
    PRIORITY = PLUGIN_PRIORITY,
    VERSION = JWTAuthHandler.VERSION,
    name = PLUGIN_NAME,
    schema = plugin_schema,
    handler = JWTAuthHandler
}