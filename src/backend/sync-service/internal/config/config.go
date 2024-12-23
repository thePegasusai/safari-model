// Package config provides configuration management for the sync service with
// enhanced security features and multi-region support.
// Version: 1.0.0
package config

import (
	"errors"
	"os"
	"strconv"
	"strings"
	"time"
)

// LogLevel represents the logging level configuration
type LogLevel string

const (
	// Default configuration values
	defaultDBPort         = 5432
	defaultQueuePort     = 5672
	defaultMaxRetries    = 3
	defaultTimeout       = time.Second * 30
	defaultShardCount    = 3
	defaultReplicaCount  = 2
	defaultHeartbeat     = time.Second * 10
	defaultMaxConns      = 100
	defaultPrefetchCount = 50
	defaultMinInstances  = 1
	defaultMaxInstances  = 10

	// LogLevel constants
	LogDebug   LogLevel = "DEBUG"
	LogInfo    LogLevel = "INFO"
	LogWarning LogLevel = "WARNING"
	LogError   LogLevel = "ERROR"
)

// Config represents the main configuration structure with enhanced security
// and multi-region support
type Config struct {
	DB      *DatabaseConfig
	Queue   *QueueConfig
	Service *ServiceConfig
}

// DatabaseConfig represents PostgreSQL configuration with sharding and replication
type DatabaseConfig struct {
	Host            string
	Port            int
	Database        string
	User            string
	Password        string
	MaxConnections  int
	ConnTimeout     time.Duration
	ShardCount      int
	ReplicaHosts    []string
	EnableSSL       bool
	SSLMode         string
	Region          string
	ShardingKeys    map[string]string
}

// QueueConfig represents RabbitMQ configuration with scaling and persistence
type QueueConfig struct {
	Host               string
	Port              int
	User              string
	Password          string
	Exchange          string
	Queue             string
	HeartbeatInterval time.Duration
	EnablePersistence bool
	MaxConcurrency    int
	DeadLetterExchange string
	PrefetchCount     int
	AutoScale         bool
	MinInstances      int
	MaxInstances      int
}

// ServiceConfig represents service configuration with monitoring and regions
type ServiceConfig struct {
	Environment     string
	MaxRetries      int
	RetryDelay      time.Duration
	ShutdownTimeout time.Duration
	Debug           bool
	Region          string
	AllowedRegions  []string
	EnableMetrics   bool
	MetricsEndpoint string
	LogLevel        LogLevel
	EnableTracing   bool
	TracingEndpoint string
}

// LoadConfig loads and validates configuration from environment variables
func LoadConfig() (*Config, error) {
	cfg := &Config{
		DB:      loadDatabaseConfig(),
		Queue:   loadQueueConfig(),
		Service: loadServiceConfig(),
	}

	if err := cfg.Validate(); err != nil {
		return nil, err
	}

	return cfg, nil
}

// Validate performs comprehensive validation of all configuration settings
func (c *Config) Validate() error {
	if err := c.validateDatabase(); err != nil {
		return errors.New("database config validation failed: " + err.Error())
	}

	if err := c.validateQueue(); err != nil {
		return errors.New("queue config validation failed: " + err.Error())
	}

	if err := c.validateService(); err != nil {
		return errors.New("service config validation failed: " + err.Error())
	}

	return c.validateMultiRegion()
}

func (c *Config) validateDatabase() error {
	if c.DB == nil {
		return errors.New("database configuration is required")
	}

	if c.DB.Host == "" {
		return errors.New("database host is required")
	}

	if c.DB.Database == "" {
		return errors.New("database name is required")
	}

	if c.DB.User == "" || c.DB.Password == "" {
		return errors.New("database credentials are required")
	}

	if c.DB.ShardCount < 1 {
		return errors.New("invalid shard count")
	}

	return nil
}

func (c *Config) validateQueue() error {
	if c.Queue == nil {
		return errors.New("queue configuration is required")
	}

	if c.Queue.Host == "" {
		return errors.New("queue host is required")
	}

	if c.Queue.User == "" || c.Queue.Password == "" {
		return errors.New("queue credentials are required")
	}

	if c.Queue.Exchange == "" || c.Queue.Queue == "" {
		return errors.New("queue exchange and name are required")
	}

	return nil
}

func (c *Config) validateService() error {
	if c.Service == nil {
		return errors.New("service configuration is required")
	}

	if c.Service.Environment == "" {
		return errors.New("environment is required")
	}

	if c.Service.Region == "" {
		return errors.New("region is required")
	}

	if len(c.Service.AllowedRegions) == 0 {
		return errors.New("allowed regions must be specified")
	}

	return nil
}

func (c *Config) validateMultiRegion() error {
	if !contains(c.Service.AllowedRegions, c.Service.Region) {
		return errors.New("service region not in allowed regions list")
	}

	if c.DB.Region != c.Service.Region {
		return errors.New("database region must match service region")
	}

	return nil
}

func loadDatabaseConfig() *DatabaseConfig {
	return &DatabaseConfig{
		Host:           getEnvOrDefault("DB_HOST", "localhost"),
		Port:           getEnvAsIntOrDefault("DB_PORT", defaultDBPort),
		Database:       getEnvOrDefault("DB_NAME", "wildlife_sync"),
		User:           getEnvOrDefault("DB_USER", ""),
		Password:       getEnvOrDefault("DB_PASSWORD", ""),
		MaxConnections: getEnvAsIntOrDefault("DB_MAX_CONNECTIONS", defaultMaxConns),
		ConnTimeout:    getEnvAsDurationOrDefault("DB_TIMEOUT", defaultTimeout),
		ShardCount:     getEnvAsIntOrDefault("DB_SHARD_COUNT", defaultShardCount),
		ReplicaHosts:   strings.Split(getEnvOrDefault("DB_REPLICA_HOSTS", ""), ","),
		EnableSSL:      getEnvAsBoolOrDefault("DB_ENABLE_SSL", true),
		SSLMode:        getEnvOrDefault("DB_SSL_MODE", "verify-full"),
		Region:         getEnvOrDefault("DB_REGION", ""),
		ShardingKeys:   parseShardingKeys(getEnvOrDefault("DB_SHARDING_KEYS", "")),
	}
}

func loadQueueConfig() *QueueConfig {
	return &QueueConfig{
		Host:               getEnvOrDefault("QUEUE_HOST", "localhost"),
		Port:               getEnvAsIntOrDefault("QUEUE_PORT", defaultQueuePort),
		User:               getEnvOrDefault("QUEUE_USER", ""),
		Password:           getEnvOrDefault("QUEUE_PASSWORD", ""),
		Exchange:           getEnvOrDefault("QUEUE_EXCHANGE", "wildlife_sync"),
		Queue:              getEnvOrDefault("QUEUE_NAME", "sync_tasks"),
		HeartbeatInterval:  getEnvAsDurationOrDefault("QUEUE_HEARTBEAT", defaultHeartbeat),
		EnablePersistence:  getEnvAsBoolOrDefault("QUEUE_PERSISTENCE", true),
		MaxConcurrency:     getEnvAsIntOrDefault("QUEUE_MAX_CONCURRENCY", defaultMaxConns),
		DeadLetterExchange: getEnvOrDefault("QUEUE_DLX", "wildlife_sync_dlx"),
		PrefetchCount:      getEnvAsIntOrDefault("QUEUE_PREFETCH", defaultPrefetchCount),
		AutoScale:          getEnvAsBoolOrDefault("QUEUE_AUTO_SCALE", true),
		MinInstances:       getEnvAsIntOrDefault("QUEUE_MIN_INSTANCES", defaultMinInstances),
		MaxInstances:       getEnvAsIntOrDefault("QUEUE_MAX_INSTANCES", defaultMaxInstances),
	}
}

func loadServiceConfig() *ServiceConfig {
	return &ServiceConfig{
		Environment:     getEnvOrDefault("SERVICE_ENV", "development"),
		MaxRetries:      getEnvAsIntOrDefault("SERVICE_MAX_RETRIES", defaultMaxRetries),
		RetryDelay:      getEnvAsDurationOrDefault("SERVICE_RETRY_DELAY", time.Second),
		ShutdownTimeout: getEnvAsDurationOrDefault("SERVICE_SHUTDOWN_TIMEOUT", defaultTimeout),
		Debug:           getEnvAsBoolOrDefault("SERVICE_DEBUG", false),
		Region:          getEnvOrDefault("SERVICE_REGION", ""),
		AllowedRegions:  strings.Split(getEnvOrDefault("SERVICE_ALLOWED_REGIONS", ""), ","),
		EnableMetrics:   getEnvAsBoolOrDefault("SERVICE_ENABLE_METRICS", true),
		MetricsEndpoint: getEnvOrDefault("SERVICE_METRICS_ENDPOINT", "/metrics"),
		LogLevel:        LogLevel(getEnvOrDefault("SERVICE_LOG_LEVEL", string(LogInfo))),
		EnableTracing:   getEnvAsBoolOrDefault("SERVICE_ENABLE_TRACING", true),
		TracingEndpoint: getEnvOrDefault("SERVICE_TRACING_ENDPOINT", ""),
	}
}

// Helper functions
func getEnvOrDefault(key, defaultValue string) string {
	if value, exists := os.LookupEnv(key); exists {
		return strings.TrimSpace(value)
	}
	return defaultValue
}

func getEnvAsIntOrDefault(key string, defaultValue int) int {
	strValue := getEnvOrDefault(key, "")
	if strValue == "" {
		return defaultValue
	}
	if value, err := strconv.Atoi(strValue); err == nil {
		return value
	}
	return defaultValue
}

func getEnvAsBoolOrDefault(key string, defaultValue bool) bool {
	strValue := getEnvOrDefault(key, "")
	if strValue == "" {
		return defaultValue
	}
	value, err := strconv.ParseBool(strValue)
	if err != nil {
		return defaultValue
	}
	return value
}

func getEnvAsDurationOrDefault(key string, defaultValue time.Duration) time.Duration {
	strValue := getEnvOrDefault(key, "")
	if strValue == "" {
		return defaultValue
	}
	if duration, err := time.ParseDuration(strValue); err == nil {
		return duration
	}
	return defaultValue
}

func parseShardingKeys(value string) map[string]string {
	result := make(map[string]string)
	if value == "" {
		return result
	}
	pairs := strings.Split(value, ",")
	for _, pair := range pairs {
		kv := strings.Split(pair, ":")
		if len(kv) == 2 {
			result[strings.TrimSpace(kv[0])] = strings.TrimSpace(kv[1])
		}
	}
	return result
}

func contains(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}