// Package repositories provides data access layer implementations for the sync service
package repositories

import (
    "context"
    "encoding/json"
    "fmt"
    "time"
    "hash/fnv"
    "sync"

    "github.com/google/uuid"                           // v1.3.0
    "github.com/opentracing/opentracing-go"           // v1.2.0
    "github.com/prometheus/client_golang/prometheus"   // v1.11.0
    "github.com/cenkalti/backoff/v4"                  // v4.2.1
    "golang.org/x/sync/errgroup"                      // v0.3.0

    "wildlife-safari/sync-service/internal/models"
    "wildlife-safari/sync-service/internal/database"
    "wildlife-safari/sync-service/internal/queue"
    "wildlife-safari/sync-service/internal/metrics"
)

const (
    // Operation timeouts and limits
    defaultBatchTimeout       = 5 * time.Minute
    maxRetryAttempts         = 3
    defaultShardCount        = 256
    circuitBreakerThreshold  = 0.5

    // Metric names
    metricSyncCreated        = "sync_record_created_total"
    metricSyncProcessed      = "sync_record_processed_total"
    metricSyncFailed         = "sync_record_failed_total"
    metricProcessingDuration = "sync_processing_duration_seconds"
)

// SyncRepository handles data persistence and retrieval for sync operations
type SyncRepository struct {
    db          *database.PostgresClient
    queue       *queue.RabbitMQClient
    metrics     *metrics.Collector
    shardMutex  sync.RWMutex
    shardStatus map[int]bool // Track shard health
}

// NewSyncRepository creates a new instance of SyncRepository with dependencies
func NewSyncRepository(db *database.PostgresClient, queue *queue.RabbitMQClient, metrics *metrics.Collector) *SyncRepository {
    return &SyncRepository{
        db:          db,
        queue:       queue,
        metrics:     metrics,
        shardStatus: make(map[int]bool),
    }
}

// calculateShardKey generates a consistent shard key based on UserID
func (r *SyncRepository) calculateShardKey(userID uuid.UUID) int {
    h := fnv.New32a()
    h.Write([]byte(userID.String()))
    return int(h.Sum32() % defaultShardCount)
}

// CreateSyncRecord creates a new sync record with sharding support
func (r *SyncRepository) CreateSyncRecord(ctx context.Context, record *models.SyncRecord) error {
    span, ctx := opentracing.StartSpanFromContext(ctx, "SyncRepository.CreateSyncRecord")
    defer span.Finish()

    timer := prometheus.NewTimer(r.metrics.HistogramVec.WithLabelValues(metricProcessingDuration))
    defer timer.ObserveDuration()

    // Validate record
    if valid, err := record.IsValid(); !valid {
        return fmt.Errorf("invalid sync record: %w", err)
    }

    // Calculate shard key
    shardKey := r.calculateShardKey(record.UserID)
    span.SetTag("shard_key", shardKey)

    // Begin transaction
    tx, err := r.db.BeginTx(ctx, nil)
    if err != nil {
        return fmt.Errorf("failed to begin transaction: %w", err)
    }
    defer tx.Rollback()

    // Insert record into sharded table
    query := `
        INSERT INTO sync_records_shard_%d 
        (id, user_id, batch_id, entity_type, status, data, retry_count, created_at, updated_at, version)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
    `
    _, err = tx.ExecContext(ctx,
        fmt.Sprintf(query, shardKey),
        record.ID,
        record.UserID,
        record.BatchID,
        record.EntityType,
        record.Status,
        record.Data,
        record.RetryCount,
        record.CreatedAt,
        record.UpdatedAt,
        record.Version,
    )
    if err != nil {
        return fmt.Errorf("failed to insert sync record: %w", err)
    }

    // Publish to region-specific queue
    queueMsg := struct {
        RecordID uuid.UUID `json:"record_id"`
        ShardKey int       `json:"shard_key"`
    }{
        RecordID: record.ID,
        ShardKey: shardKey,
    }
    
    msgBytes, err := json.Marshal(queueMsg)
    if err != nil {
        return fmt.Errorf("failed to marshal queue message: %w", err)
    }

    err = r.queue.PublishWithContext(ctx, "sync.records", msgBytes)
    if err != nil {
        return fmt.Errorf("failed to publish to queue: %w", err)
    }

    // Commit transaction
    if err := tx.Commit(); err != nil {
        return fmt.Errorf("failed to commit transaction: %w", err)
    }

    // Record metrics
    r.metrics.CounterVec.WithLabelValues(metricSyncCreated).Inc()

    return nil
}

// ProcessPendingSyncs processes pending sync records with retry mechanism
func (r *SyncRepository) ProcessPendingSyncs(ctx context.Context) error {
    span, ctx := opentracing.StartSpanFromContext(ctx, "SyncRepository.ProcessPendingSyncs")
    defer span.Finish()

    // Create error group for concurrent processing
    g, ctx := errgroup.WithContext(ctx)
    
    // Process each shard concurrently
    for shard := 0; shard < defaultShardCount; shard++ {
        shardID := shard // Capture for goroutine
        
        g.Go(func() error {
            return r.processShard(ctx, shardID)
        })
    }

    return g.Wait()
}

// processShard handles processing for a specific shard
func (r *SyncRepository) processShard(ctx context.Context, shardID int) error {
    // Check shard health
    r.shardMutex.RLock()
    if !r.shardStatus[shardID] {
        r.shardMutex.RUnlock()
        return fmt.Errorf("shard %d is unhealthy", shardID)
    }
    r.shardMutex.RUnlock()

    // Query pending records from shard
    query := `
        SELECT id, user_id, batch_id, entity_type, status, data, retry_count, error_message, version
        FROM sync_records_shard_%d
        WHERE status = $1 AND retry_count < $2
        LIMIT 1000
    `
    
    rows, err := r.db.QueryContext(ctx, 
        fmt.Sprintf(query, shardID),
        models.SyncStatusPending,
        maxRetryAttempts,
    )
    if err != nil {
        return fmt.Errorf("failed to query pending records: %w", err)
    }
    defer rows.Close()

    // Process records with exponential backoff
    backoffConfig := backoff.NewExponentialBackOff()
    backoffConfig.MaxElapsedTime = defaultBatchTimeout

    for rows.Next() {
        var record models.SyncRecord
        if err := rows.Scan(
            &record.ID,
            &record.UserID,
            &record.BatchID,
            &record.EntityType,
            &record.Status,
            &record.Data,
            &record.RetryCount,
            &record.ErrorMessage,
            &record.Version,
        ); err != nil {
            return fmt.Errorf("failed to scan record: %w", err)
        }

        // Process with retry
        err := backoff.Retry(func() error {
            return r.processRecord(ctx, &record, shardID)
        }, backoffConfig)

        if err != nil {
            // Record failure metrics
            r.metrics.CounterVec.WithLabelValues(metricSyncFailed).Inc()
            
            // Mark record as failed
            record.MarkFailed(err.Error())
            if updateErr := r.updateRecordStatus(ctx, &record, shardID); updateErr != nil {
                return fmt.Errorf("failed to update failed record: %w", updateErr)
            }
        } else {
            // Record success metrics
            r.metrics.CounterVec.WithLabelValues(metricSyncProcessed).Inc()
        }
    }

    return rows.Err()
}

// processRecord handles the processing of a single sync record
func (r *SyncRepository) processRecord(ctx context.Context, record *models.SyncRecord, shardID int) error {
    span, ctx := opentracing.StartSpanFromContext(ctx, "SyncRepository.processRecord")
    defer span.Finish()

    // Process based on entity type
    switch record.EntityType {
    case models.EntityTypeSpecies:
        return r.processSpeciesSync(ctx, record)
    case models.EntityTypeFossil:
        return r.processFossilSync(ctx, record)
    case models.EntityTypeCollection:
        return r.processCollectionSync(ctx, record)
    default:
        return fmt.Errorf("unknown entity type: %s", record.EntityType)
    }
}

// updateRecordStatus updates the status of a sync record
func (r *SyncRepository) updateRecordStatus(ctx context.Context, record *models.SyncRecord, shardID int) error {
    query := `
        UPDATE sync_records_shard_%d
        SET status = $1, retry_count = $2, error_message = $3, updated_at = $4, version = version + 1
        WHERE id = $5 AND version = $6
    `
    
    result, err := r.db.ExecContext(ctx,
        fmt.Sprintf(query, shardID),
        record.Status,
        record.RetryCount,
        record.ErrorMessage,
        time.Now().UTC(),
        record.ID,
        record.Version,
    )
    if err != nil {
        return fmt.Errorf("failed to update record status: %w", err)
    }

    rows, err := result.RowsAffected()
    if err != nil {
        return fmt.Errorf("failed to get rows affected: %w", err)
    }

    if rows == 0 {
        return fmt.Errorf("record version conflict detected")
    }

    return nil
}

// Entity-specific processing methods
func (r *SyncRepository) processSpeciesSync(ctx context.Context, record *models.SyncRecord) error {
    // Implementation for species sync
    return nil
}

func (r *SyncRepository) processFossilSync(ctx context.Context, record *models.SyncRecord) error {
    // Implementation for fossil sync
    return nil
}

func (r *SyncRepository) processCollectionSync(ctx context.Context, record *models.SyncRecord) error {
    // Implementation for collection sync
    return nil
}