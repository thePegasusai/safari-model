// Package services provides business logic implementations for the sync service
package services

import (
    "context"
    "errors"
    "fmt"
    "time"
    "sync"

    "github.com/google/uuid"           // v1.3.0
    "github.com/sony/gobreaker"        // v0.5.0
    "go.uber.org/zap"                  // v1.24.0
    "golang.org/x/sync/semaphore"      // v0.3.0

    "wildlife-safari/sync-service/internal/models"
    "wildlife-safari/sync-service/internal/repositories"
)

// Default configuration values
const (
    defaultSyncTimeout       = time.Minute * 15
    maxBatchSize            = 1000
    maxConcurrentSyncs      = 50
    maxRetries              = 3
    retryBackoff            = time.Second * 2
    circuitBreakerTimeout   = time.Minute * 5
    metricsSampleRate       = 0.01
)

// Custom errors
var (
    ErrInvalidRecord     = errors.New("invalid sync record")
    ErrBatchSizeExceeded = errors.New("batch size exceeded maximum limit")
    ErrCircuitOpen       = errors.New("circuit breaker is open")
    ErrSyncTimeout       = errors.New("sync operation timed out")
)

// SyncService handles synchronization operations with enhanced reliability
type SyncService struct {
    repo      repositories.SyncRepository
    ctx       context.Context
    cancel    context.CancelFunc
    mu        *sync.RWMutex
    sem       *semaphore.Weighted
    cb        *gobreaker.CircuitBreaker
    logger    *zap.Logger
    metrics   metrics.Reporter
}

// NewSyncService creates a new instance of SyncService with initialized dependencies
func NewSyncService(repo repositories.SyncRepository, logger *zap.Logger, metrics metrics.Reporter) (*SyncService, error) {
    if repo == nil {
        return nil, errors.New("repository cannot be nil")
    }
    if logger == nil {
        return nil, errors.New("logger cannot be nil")
    }
    if metrics == nil {
        return nil, errors.New("metrics reporter cannot be nil")
    }

    ctx, cancel := context.WithCancel(context.Background())
    
    // Configure circuit breaker
    cbSettings := gobreaker.Settings{
        Name:        "sync-service",
        MaxRequests: uint32(maxConcurrentSyncs),
        Interval:    circuitBreakerTimeout,
        Timeout:     circuitBreakerTimeout,
        ReadyToTrip: func(counts gobreaker.Counts) bool {
            failureRatio := float64(counts.TotalFailures) / float64(counts.Requests)
            return counts.Requests >= 10 && failureRatio >= 0.5
        },
        OnStateChange: func(name string, from gobreaker.State, to gobreaker.State) {
            logger.Info("Circuit breaker state changed",
                zap.String("name", name),
                zap.String("from", from.String()),
                zap.String("to", to.String()))
        },
    }

    service := &SyncService{
        repo:     repo,
        ctx:      ctx,
        cancel:   cancel,
        mu:       &sync.RWMutex{},
        sem:      semaphore.NewWeighted(maxConcurrentSyncs),
        cb:       gobreaker.NewCircuitBreaker(cbSettings),
        logger:   logger,
        metrics:  metrics,
    }

    // Start background processor
    go service.ProcessPendingSyncs()

    return service, nil
}

// SyncDiscovery synchronizes a single wildlife or fossil discovery
func (s *SyncService) SyncDiscovery(ctx context.Context, record *models.SyncRecord) error {
    if err := s.sem.Acquire(ctx, 1); err != nil {
        return fmt.Errorf("failed to acquire semaphore: %w", err)
    }
    defer s.sem.Release(1)

    start := time.Now()
    defer func() {
        s.metrics.ObserveLatency("sync_duration_seconds", time.Since(start).Seconds())
    }()

    // Validate record
    if valid, err := record.IsValid(); !valid {
        return fmt.Errorf("%w: %v", ErrInvalidRecord, err)
    }

    // Execute sync through circuit breaker
    _, err := s.cb.Execute(func() (interface{}, error) {
        return nil, s.executeSyncWithRetry(ctx, record)
    })

    if err != nil {
        s.metrics.IncrementCounter("sync_failures_total", 1)
        s.logger.Error("Sync failed",
            zap.String("record_id", record.ID.String()),
            zap.Error(err))
        return err
    }

    s.metrics.IncrementCounter("sync_successes_total", 1)
    return nil
}

// SyncBatch handles batch synchronization of discoveries
func (s *SyncService) SyncBatch(ctx context.Context, batch *models.SyncBatch) error {
    if len(batch.Records) > maxBatchSize {
        return ErrBatchSizeExceeded
    }

    if err := s.sem.Acquire(ctx, int64(len(batch.Records))); err != nil {
        return fmt.Errorf("failed to acquire semaphore: %w", err)
    }
    defer s.sem.Release(int64(len(batch.Records)))

    start := time.Now()
    defer func() {
        s.metrics.ObserveLatency("batch_sync_duration_seconds", time.Since(start).Seconds())
    }()

    // Process batch atomically
    err := s.executeBatchSync(ctx, batch)
    if err != nil {
        s.metrics.IncrementCounter("batch_sync_failures_total", 1)
        s.logger.Error("Batch sync failed",
            zap.String("batch_id", batch.BatchID.String()),
            zap.Error(err))
        return err
    }

    s.metrics.IncrementCounter("batch_sync_successes_total", 1)
    return nil
}

// executeSyncWithRetry implements retry logic for sync operations
func (s *SyncService) executeSyncWithRetry(ctx context.Context, record *models.SyncRecord) error {
    var lastErr error
    for attempt := 0; attempt < maxRetries; attempt++ {
        select {
        case <-ctx.Done():
            return ctx.Err()
        default:
            err := s.repo.CreateSyncRecord(ctx, record)
            if err == nil {
                return nil
            }
            lastErr = err
            time.Sleep(retryBackoff << uint(attempt))
        }
    }
    return fmt.Errorf("sync failed after %d attempts: %w", maxRetries, lastErr)
}

// executeBatchSync processes a batch of records atomically
func (s *SyncService) executeBatchSync(ctx context.Context, batch *models.SyncBatch) error {
    err := s.repo.CreateSyncBatch(ctx, batch)
    if err != nil {
        return fmt.Errorf("failed to create sync batch: %w", err)
    }

    var wg sync.WaitGroup
    errChan := make(chan error, len(batch.Records))

    for _, record := range batch.Records {
        wg.Add(1)
        go func(r models.SyncRecord) {
            defer wg.Done()
            if err := s.executeSyncWithRetry(ctx, &r); err != nil {
                errChan <- err
            }
        }(record)
    }

    wg.Wait()
    close(errChan)

    // Collect errors
    var errors []error
    for err := range errChan {
        errors = append(errors, err)
    }

    if len(errors) > 0 {
        return fmt.Errorf("batch sync had %d failures", len(errors))
    }

    return nil
}

// ProcessPendingSyncs handles background processing of pending syncs
func (s *SyncService) ProcessPendingSyncs() error {
    ticker := time.NewTicker(time.Minute)
    defer ticker.Stop()

    for {
        select {
        case <-s.ctx.Done():
            return s.ctx.Err()
        case <-ticker.C:
            if err := s.repo.ProcessPendingSyncs(s.ctx); err != nil {
                s.logger.Error("Failed to process pending syncs", zap.Error(err))
                s.metrics.IncrementCounter("pending_sync_failures_total", 1)
            }
        }
    }
}

// Stop gracefully shuts down the sync service
func (s *SyncService) Stop() error {
    s.cancel()
    s.logger.Info("Stopping sync service")
    
    // Wait for semaphore to drain
    ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
    defer cancel()
    
    if err := s.sem.Acquire(ctx, maxConcurrentSyncs); err != nil {
        return fmt.Errorf("failed to acquire semaphore during shutdown: %w", err)
    }
    
    s.logger.Info("Sync service stopped successfully")
    return nil
}