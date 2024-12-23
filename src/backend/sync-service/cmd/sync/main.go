// Package main provides the entry point for the sync service with enhanced
// multi-region support and monitoring capabilities.
// Version: 1.0.0
package main

import (
    "context"
    "fmt"
    "net/http"
    "os"
    "os/signal"
    "sync"
    "syscall"
    "time"

    "github.com/gin-gonic/gin"         // v1.9.0
    "github.com/prometheus/client_golang/prometheus/promhttp" // v1.15.0
    "go.opentelemetry.io/otel"         // v1.14.0
    "go.opentelemetry.io/otel/trace"
    "go.uber.org/zap"                  // v1.24.0

    "wildlife-safari/sync-service/internal/config"
    "wildlife-safari/sync-service/internal/handlers"
    "wildlife-safari/sync-service/pkg/database"
)

const (
    defaultServerPort        = ":8080"
    defaultMetricsPort      = ":9090"
    defaultShutdownTimeout  = 30 * time.Second
    defaultHealthCheckInterval = 5 * time.Second
)

// Global variables for service management
var (
    logger *zap.Logger
    tracer trace.Tracer
    db     *database.PostgresClient
)

func main() {
    var err error

    // Initialize structured logging
    logger, err = zap.NewProduction()
    if err != nil {
        fmt.Printf("Failed to initialize logger: %v\n", err)
        os.Exit(1)
    }
    defer logger.Sync()

    // Load and validate configuration
    cfg, err := config.LoadConfig()
    if err != nil {
        logger.Fatal("Failed to load configuration", zap.Error(err))
    }

    // Validate multi-region configuration
    if err := validateMultiRegionConfig(cfg); err != nil {
        logger.Fatal("Invalid multi-region configuration", zap.Error(err))
    }

    // Initialize OpenTelemetry tracer
    tracer = initTracer(cfg)

    // Initialize database client with sharding support
    ctx := context.Background()
    db, err = database.NewPostgresClient(ctx, cfg.DB)
    if err != nil {
        logger.Fatal("Failed to initialize database client", zap.Error(err))
    }
    defer db.Close()

    // Initialize sync handler
    syncHandler := handlers.NewSyncHandler(nil) // TODO: Initialize with sync service

    // Set up HTTP server with middleware
    router := setupRouter(syncHandler)

    // Start metrics server
    go startMetricsServer()

    // Start main server
    srv := &http.Server{
        Addr:    getServerPort(),
        Handler: router,
    }

    // Start server in a goroutine
    go func() {
        logger.Info("Starting sync service",
            zap.String("port", srv.Addr),
            zap.String("region", cfg.Service.Region))
        
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            logger.Fatal("Failed to start server", zap.Error(err))
        }
    }()

    // Set up graceful shutdown
    setupGracefulShutdown(srv, db)
}

// setupRouter configures the HTTP router with all necessary middleware and routes
func setupRouter(syncHandler *handlers.SyncHandler) *gin.Engine {
    if gin.Mode() == gin.ReleaseMode {
        gin.SetMode(gin.ReleaseMode)
    }

    router := gin.New()

    // Add middleware
    router.Use(
        gin.Recovery(),
        requestTracing(),
        requestMetrics(),
        rateLimiter(),
    )

    // Health check endpoint
    router.GET("/health", healthCheck)

    // API routes
    v1 := router.Group("/api/v1")
    {
        v1.POST("/sync", syncHandler.HandleSyncDiscovery)
        v1.POST("/sync/batch", syncHandler.HandleBatchSync)
        v1.GET("/sync/:sync_id", syncHandler.HandleGetSyncStatus)
    }

    return router
}

// startMetricsServer starts a separate server for metrics collection
func startMetricsServer() {
    mux := http.NewServeMux()
    mux.Handle("/metrics", promhttp.Handler())

    metricsServer := &http.Server{
        Addr:    defaultMetricsPort,
        Handler: mux,
    }

    logger.Info("Starting metrics server", zap.String("port", defaultMetricsPort))
    if err := metricsServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
        logger.Error("Metrics server failed", zap.Error(err))
    }
}

// setupGracefulShutdown handles graceful shutdown of all components
func setupGracefulShutdown(srv *http.Server, db *database.PostgresClient) {
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    <-quit

    logger.Info("Shutting down server...")

    // Create shutdown context with timeout
    ctx, cancel := context.WithTimeout(context.Background(), defaultShutdownTimeout)
    defer cancel()

    // Create WaitGroup for coordinated shutdown
    var wg sync.WaitGroup

    // Shutdown HTTP server
    wg.Add(1)
    go func() {
        defer wg.Done()
        if err := srv.Shutdown(ctx); err != nil {
            logger.Error("Server shutdown error", zap.Error(err))
        }
    }()

    // Close database connections
    wg.Add(1)
    go func() {
        defer wg.Done()
        db.Close()
        logger.Info("Database connections closed")
    }()

    // Wait for all shutdown operations to complete
    waitChan := make(chan struct{})
    go func() {
        wg.Wait()
        close(waitChan)
    }()

    select {
    case <-ctx.Done():
        logger.Error("Shutdown timed out")
    case <-waitChan:
        logger.Info("Shutdown completed successfully")
    }
}

// Middleware functions
func requestTracing() gin.HandlerFunc {
    return func(c *gin.Context) {
        ctx, span := tracer.Start(c.Request.Context(), "http_request")
        defer span.End()
        c.Request = c.Request.WithContext(ctx)
        c.Next()
    }
}

func requestMetrics() gin.HandlerFunc {
    return func(c *gin.Context) {
        start := time.Now()
        c.Next()
        duration := time.Since(start)

        // Record request metrics
        // TODO: Implement metrics recording
        _ = duration
    }
}

func rateLimiter() gin.HandlerFunc {
    // TODO: Implement rate limiting
    return func(c *gin.Context) {
        c.Next()
    }
}

// Health check handler
func healthCheck(c *gin.Context) {
    c.JSON(http.StatusOK, gin.H{
        "status": "healthy",
        "time":   time.Now().UTC(),
    })
}

// Helper functions
func getServerPort() string {
    if port := os.Getenv("SERVER_PORT"); port != "" {
        return ":" + port
    }
    return defaultServerPort
}

func validateMultiRegionConfig(cfg *config.Config) error {
    if cfg.Service.Region == "" {
        return fmt.Errorf("service region must be specified")
    }
    if len(cfg.Service.AllowedRegions) == 0 {
        return fmt.Errorf("allowed regions must be specified")
    }
    return nil
}

func initTracer(cfg *config.Config) trace.Tracer {
    // TODO: Initialize OpenTelemetry tracer
    return otel.Tracer("sync-service")
}