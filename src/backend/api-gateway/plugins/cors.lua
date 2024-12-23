-- Wildlife Detection Safari Pokédex CORS Plugin
-- Version: 1.0.0
-- Kong Gateway Version: 2.8.1
-- Purpose: Enhanced CORS handling with security and performance optimizations

local kong = require "kong"
local cjson = require "cjson.safe"

-- Plugin metadata and configuration
local CorsHandler = {
  PRIORITY = 2000,
  VERSION = "1.0.0"
}

-- Default configurations
local DEFAULT_ALLOW_HEADERS = {
  "Authorization",
  "Content-Type", 
  "X-Auth-Token",
  "X-Request-ID",
  "X-API-Version",
  "X-Device-ID",
  "X-Platform-Type"
}

local DEFAULT_ALLOW_METHODS = {
  "GET",
  "POST",
  "PUT",
  "DELETE",
  "OPTIONS",
  "PATCH"
}

-- Allowed origin patterns for enhanced security
local ALLOWED_ORIGIN_PATTERNS = {
  "^https?://.*%.wildlifesafari%.app$",
  "^https?://.*%.amazonaws%.com$"
}

-- Plugin schema definition
local schema = {
  name = "cors",
  fields = {
    { config = {
      type = "record",
      fields = {
        { origins = { type = "array", elements = { type = "string" }, default = {} } },
        { methods = { type = "array", elements = { type = "string" }, default = DEFAULT_ALLOW_METHODS } },
        { headers = { type = "array", elements = { type = "string" }, default = DEFAULT_ALLOW_HEADERS } },
        { exposed_headers = { type = "array", elements = { type = "string" }, default = {} } },
        { credentials = { type = "boolean", default = false } },
        { max_age = { type = "number", default = 3600 } },
        { preflight_continue = { type = "boolean", default = false } }
      }
    } }
  }
}

-- Utility function to check if origin matches allowed patterns
local function matches_allowed_pattern(origin)
  if not origin then return false end
  
  for _, pattern in ipairs(ALLOWED_ORIGIN_PATTERNS) do
    if ngx.re.match(origin, pattern, "jo") then
      return true
    end
  end
  return false
end

-- Utility function to validate and normalize headers
local function normalize_header(header)
  if type(header) ~= "string" then return nil end
  return header:lower():gsub("_", "-")
end

-- Handle preflight OPTIONS requests with caching optimization
local function handle_preflight(conf, origin)
  if not origin then
    return kong.response.exit(400, { message = "Missing Origin header" })
  end

  -- Validate the requested method
  local access_control_request_method = kong.request.get_header("Access-Control-Request-Method")
  if not access_control_request_method then
    return kong.response.exit(400, { message = "Missing Access-Control-Request-Method header" })
  end

  -- Validate requested headers
  local access_control_request_headers = kong.request.get_header("Access-Control-Request-Headers")
  if access_control_request_headers then
    access_control_request_headers = normalize_header(access_control_request_headers)
  end

  -- Build response headers
  local headers = {
    ["Access-Control-Allow-Origin"] = origin,
    ["Access-Control-Allow-Methods"] = table.concat(conf.methods, ", "),
    ["Access-Control-Allow-Headers"] = table.concat(conf.headers, ", "),
    ["Access-Control-Max-Age"] = tostring(conf.max_age),
    ["Access-Control-Allow-Credentials"] = conf.credentials and "true" or nil
  }

  -- Add security headers
  headers["X-Content-Type-Options"] = "nosniff"
  headers["X-Frame-Options"] = "DENY"
  headers["X-XSS-Protection"] = "1; mode=block"

  if not conf.preflight_continue then
    return kong.response.exit(204, nil, headers)
  end

  return headers
end

-- Add CORS headers to response
local function add_cors_headers(conf, origin)
  if not origin then return false end

  local headers = kong.response.get_headers()
  headers["Access-Control-Allow-Origin"] = origin
  
  if conf.credentials then
    headers["Access-Control-Allow-Credentials"] = "true"
  end

  if #conf.exposed_headers > 0 then
    headers["Access-Control-Expose-Headers"] = table.concat(conf.exposed_headers, ", ")
  end

  -- Add mobile-specific performance headers
  headers["Cache-Control"] = "no-transform"
  headers["Timing-Allow-Origin"] = origin

  kong.response.set_headers(headers)
  return true
end

-- Main plugin access function
function CorsHandler:access(conf)
  local origin = kong.request.get_header("Origin")
  
  -- Early exit if not a CORS request
  if not origin then
    return
  end

  -- Validate origin against allowed patterns
  if not matches_allowed_pattern(origin) then
    return kong.response.exit(403, { message = "Origin not allowed" })
  end

  -- Handle preflight requests
  if kong.request.get_method() == "OPTIONS" then
    local headers = handle_preflight(conf, origin)
    if conf.preflight_continue then
      kong.service.request.set_headers(headers)
    end
    return
  end

  -- Handle actual request
  kong.ctx.shared.cors = {
    origin = origin,
    headers = conf.headers,
    exposed_headers = conf.exposed_headers
  }
end

-- Response header handler
function CorsHandler:header_filter(conf)
  local cors = kong.ctx.shared.cors
  if not cors then
    return
  end

  add_cors_headers(conf, cors.origin)
end

-- Plugin factory
return {
  PRIORITY = CorsHandler.PRIORITY,
  VERSION = CorsHandler.VERSION,
  name = "cors",
  schema = schema,
  handler = CorsHandler
}