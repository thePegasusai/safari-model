// Package models provides core data structures and operations for the sync service
package models

import (
    "encoding/json"
    "errors"
    "fmt"
    "time"

    "github.com/google/uuid" // v1.3.0
)

// Sync status constants
const (
    SyncStatusPending   = "pending"
    SyncStatusCompleted = "completed"
    SyncStatusFailed    = "failed"
)

// Entity type constants
const (
    EntityTypeSpecies    = "species"
    EntityTypeFossil     = "fossil"
    EntityTypeCollection = "collection"
)

// Operation constants
const (
    MaxRetryCount = 3
    MaxBatchSize  = 1000
)

// SyncRecord represents a single synchronization record with comprehensive tracking
type SyncRecord struct {
    ID           uuid.UUID       `json:"id" bson:"_id"`
    UserID       uuid.UUID       `json:"user_id" bson:"user_id"`
    BatchID      uuid.UUID       `json:"batch_id,omitempty" bson:"batch_id,omitempty"`
    EntityType   string         `json:"entity_type" bson:"entity_type"`
    Status       string         `json:"status" bson:"status"`
    Data         json.RawMessage `json:"data" bson:"data"`
    RetryCount   int            `json:"retry_count" bson:"retry_count"`
    ErrorMessage string         `json:"error_message,omitempty" bson:"error_message,omitempty"`
    CreatedAt    time.Time      `json:"created_at" bson:"created_at"`
    UpdatedAt    time.Time      `json:"updated_at" bson:"updated_at"`
    Version      int64          `json:"version" bson:"version"`
}

// SyncBatch manages a batch of sync records for atomic processing
type SyncBatch struct {
    BatchID     uuid.UUID    `json:"batch_id" bson:"_id"`
    Records     []SyncRecord `json:"records" bson:"records"`
    Status      string      `json:"status" bson:"status"`
    CreatedAt   time.Time   `json:"created_at" bson:"created_at"`
    CompletedAt time.Time   `json:"completed_at,omitempty" bson:"completed_at,omitempty"`
    FailedCount int         `json:"failed_count" bson:"failed_count"`
    Version     int64       `json:"version" bson:"version"`
}

// NewSyncRecord creates a new sync record with initialized values
func NewSyncRecord(userID uuid.UUID, entityType string, data json.RawMessage) (*SyncRecord, error) {
    if userID == uuid.Nil {
        return nil, errors.New("user ID cannot be nil")
    }
    if len(data) == 0 {
        return nil, errors.New("data cannot be empty")
    }

    // Validate entity type
    switch entityType {
    case EntityTypeSpecies, EntityTypeFossil, EntityTypeCollection:
        // Valid entity type
    default:
        return nil, fmt.Errorf("invalid entity type: %s", entityType)
    }

    now := time.Now().UTC()
    record := &SyncRecord{
        ID:         uuid.New(),
        UserID:     userID,
        EntityType: entityType,
        Status:     SyncStatusPending,
        Data:       data,
        RetryCount: 0,
        CreatedAt:  now,
        UpdatedAt:  now,
        Version:    1,
    }

    if valid, err := record.IsValid(); !valid {
        return nil, err
    }

    return record, nil
}

// NewSyncBatch creates a new batch of sync records with validation
func NewSyncBatch(records []SyncRecord) (*SyncBatch, error) {
    if len(records) == 0 {
        return nil, errors.New("batch must contain at least one record")
    }
    if len(records) > MaxBatchSize {
        return nil, fmt.Errorf("batch size exceeds maximum limit of %d", MaxBatchSize)
    }

    batchID := uuid.New()
    now := time.Now().UTC()

    // Associate records with batch
    for i := range records {
        records[i].BatchID = batchID
        if valid, err := records[i].IsValid(); !valid {
            return nil, fmt.Errorf("invalid record at index %d: %v", i, err)
        }
    }

    batch := &SyncBatch{
        BatchID:   batchID,
        Records:   records,
        Status:    SyncStatusPending,
        CreatedAt: now,
        Version:   1,
    }

    return batch, nil
}

// IsValid performs comprehensive validation of the sync record
func (r *SyncRecord) IsValid() (bool, error) {
    if r.ID == uuid.Nil {
        return false, errors.New("record ID cannot be nil")
    }
    if r.UserID == uuid.Nil {
        return false, errors.New("user ID cannot be nil")
    }

    switch r.EntityType {
    case EntityTypeSpecies, EntityTypeFossil, EntityTypeCollection:
        // Valid entity type
    default:
        return false, fmt.Errorf("invalid entity type: %s", r.EntityType)
    }

    switch r.Status {
    case SyncStatusPending, SyncStatusCompleted, SyncStatusFailed:
        // Valid status
    default:
        return false, fmt.Errorf("invalid status: %s", r.Status)
    }

    if len(r.Data) == 0 {
        return false, errors.New("data cannot be empty")
    }

    if r.RetryCount < 0 || r.RetryCount > MaxRetryCount {
        return false, fmt.Errorf("retry count must be between 0 and %d", MaxRetryCount)
    }

    if r.CreatedAt.IsZero() {
        return false, errors.New("created at timestamp cannot be zero")
    }
    if r.UpdatedAt.IsZero() {
        return false, errors.New("updated at timestamp cannot be zero")
    }

    return true, nil
}

// MarkCompleted updates record status to completed
func (r *SyncRecord) MarkCompleted() error {
    if r.Status != SyncStatusPending {
        return fmt.Errorf("cannot mark completed: current status is %s", r.Status)
    }

    r.Status = SyncStatusCompleted
    r.Version++
    r.UpdatedAt = time.Now().UTC()
    r.ErrorMessage = ""

    return nil
}

// MarkFailed marks record as failed with error tracking
func (r *SyncRecord) MarkFailed(errorMsg string) error {
    if errorMsg == "" {
        return errors.New("error message cannot be empty")
    }

    r.RetryCount++
    if r.RetryCount > MaxRetryCount {
        r.Status = SyncStatusFailed
    }
    r.ErrorMessage = errorMsg
    r.Version++
    r.UpdatedAt = time.Now().UTC()

    return nil
}

// IsComplete checks completion status of all records in batch
func (b *SyncBatch) IsComplete() (bool, error) {
    if len(b.Records) == 0 {
        return false, errors.New("batch contains no records")
    }

    completed := 0
    failed := 0

    for _, record := range b.Records {
        switch record.Status {
        case SyncStatusCompleted:
            completed++
        case SyncStatusFailed:
            failed++
        }
    }

    b.FailedCount = failed
    allProcessed := completed + failed == len(b.Records)

    if allProcessed && b.CompletedAt.IsZero() {
        b.CompletedAt = time.Now().UTC()
        b.Status = SyncStatusCompleted
        b.Version++
    }

    return allProcessed, nil
}