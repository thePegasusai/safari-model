// Package handlers provides HTTP handlers for the sync service API endpoints
package handlers

import (
    "context"
    "encoding/json"
    "errors"
    "fmt"
    "net/http"
    "time"

    "github.com/gin-gonic/gin"                    // v1.9.0
    "github.com/google/uuid"                      // v1.3.0
    "go.opentelemetry.io/otel"                   // v1.19.0
    "go.opentelemetry.io/otel/trace"             // v1.19.0
    "go.opentelemetry.io/otel/attribute"         // v1.19.0

    "wildlife-safari/sync-service/internal/models"
    "wildlife-safari/sync-service/internal/services"
)

// Constants for request handling
const (
    maxBatchSize         = 1000
    defaultTimeout       = 30 * time.Second
    maxConcurrentBatches = 5
    statusCacheDuration  = 5 * time.Minute
)

// Custom errors
var (
    ErrInvalidUserID     = errors.New("invalid user ID")
    ErrInvalidBatchSize  = errors.New("batch size exceeds maximum limit")
    ErrInvalidSyncID     = errors.New("invalid sync record ID")
    ErrRequestTimeout    = errors.New("request timeout")
    ErrBatchProcessing   = errors.New("batch processing failed")
)

// SyncHandler handles sync-related HTTP requests
type SyncHandler struct {
    syncService services.SyncService
    tracer      trace.Tracer
}

// NewSyncHandler creates a new instance of SyncHandler
func NewSyncHandler(syncService services.SyncService) *SyncHandler {
    return &SyncHandler{
        syncService: syncService,
        tracer:      otel.GetTracerProvider().Tracer("sync-handler"),
    }
}

// HandleSyncDiscovery handles single discovery sync requests
func (h *SyncHandler) HandleSyncDiscovery(c *gin.Context) {
    ctx, span := h.tracer.Start(c.Request.Context(), "HandleSyncDiscovery")
    defer span.End()

    // Set request timeout
    ctx, cancel := context.WithTimeout(ctx, defaultTimeout)
    defer cancel()

    // Extract and validate user ID from context
    userID, err := uuid.Parse(c.GetString("user_id"))
    if err != nil {
        span.SetAttributes(attribute.String("error", "invalid_user_id"))
        c.JSON(http.StatusBadRequest, gin.H{
            "error": ErrInvalidUserID.Error(),
        })
        return
    }

    // Parse request body
    var request struct {
        EntityType string          `json:"entity_type"`
        Data      json.RawMessage `json:"data"`
    }

    if err := c.ShouldBindJSON(&request); err != nil {
        span.SetAttributes(attribute.String("error", "invalid_request"))
        c.JSON(http.StatusBadRequest, gin.H{
            "error": fmt.Sprintf("invalid request format: %v", err),
        })
        return
    }

    // Create sync record
    record, err := models.NewSyncRecord(userID, request.EntityType, request.Data)
    if err != nil {
        span.SetAttributes(attribute.String("error", "invalid_record"))
        c.JSON(http.StatusBadRequest, gin.H{
            "error": fmt.Sprintf("invalid sync record: %v", err),
        })
        return
    }

    // Process sync request
    err = h.syncService.SyncDiscovery(ctx, record)
    if err != nil {
        span.SetAttributes(attribute.String("error", "sync_failed"))
        status := http.StatusInternalServerError
        if errors.Is(err, context.DeadlineExceeded) {
            status = http.StatusRequestTimeout
        }
        c.JSON(status, gin.H{
            "error": fmt.Sprintf("sync failed: %v", err),
        })
        return
    }

    // Return success response
    c.JSON(http.StatusAccepted, gin.H{
        "sync_id": record.ID,
        "status": record.Status,
        "message": "Sync request accepted",
    })
}

// HandleBatchSync handles batch sync requests
func (h *SyncHandler) HandleBatchSync(c *gin.Context) {
    ctx, span := h.tracer.Start(c.Request.Context(), "HandleBatchSync")
    defer span.End()

    // Set extended timeout for batch processing
    ctx, cancel := context.WithTimeout(ctx, defaultTimeout*2)
    defer cancel()

    // Extract and validate user ID
    userID, err := uuid.Parse(c.GetString("user_id"))
    if err != nil {
        span.SetAttributes(attribute.String("error", "invalid_user_id"))
        c.JSON(http.StatusBadRequest, gin.H{
            "error": ErrInvalidUserID.Error(),
        })
        return
    }

    // Parse batch request
    var request struct {
        Records []struct {
            EntityType string          `json:"entity_type"`
            Data      json.RawMessage `json:"data"`
        } `json:"records"`
    }

    if err := c.ShouldBindJSON(&request); err != nil {
        span.SetAttributes(attribute.String("error", "invalid_request"))
        c.JSON(http.StatusBadRequest, gin.H{
            "error": fmt.Sprintf("invalid batch format: %v", err),
        })
        return
    }

    // Validate batch size
    if len(request.Records) > maxBatchSize {
        span.SetAttributes(attribute.String("error", "batch_size_exceeded"))
        c.JSON(http.StatusBadRequest, gin.H{
            "error": ErrInvalidBatchSize.Error(),
        })
        return
    }

    // Create sync records
    var syncRecords []models.SyncRecord
    for _, rec := range request.Records {
        record, err := models.NewSyncRecord(userID, rec.EntityType, rec.Data)
        if err != nil {
            span.SetAttributes(attribute.String("error", "invalid_record"))
            c.JSON(http.StatusBadRequest, gin.H{
                "error": fmt.Sprintf("invalid record in batch: %v", err),
            })
            return
        }
        syncRecords = append(syncRecords, *record)
    }

    // Create and process batch
    batch, err := models.NewSyncBatch(syncRecords)
    if err != nil {
        span.SetAttributes(attribute.String("error", "invalid_batch"))
        c.JSON(http.StatusBadRequest, gin.H{
            "error": fmt.Sprintf("invalid batch: %v", err),
        })
        return
    }

    // Process batch
    err = h.syncService.SyncBatch(ctx, batch)
    if err != nil {
        span.SetAttributes(attribute.String("error", "batch_sync_failed"))
        status := http.StatusInternalServerError
        if errors.Is(err, context.DeadlineExceeded) {
            status = http.StatusRequestTimeout
        }
        c.JSON(status, gin.H{
            "error": fmt.Sprintf("batch sync failed: %v", err),
        })
        return
    }

    // Return success response
    c.JSON(http.StatusAccepted, gin.H{
        "batch_id": batch.BatchID,
        "status": batch.Status,
        "message": "Batch sync request accepted",
        "record_count": len(batch.Records),
    })
}

// HandleGetSyncStatus handles sync status retrieval requests
func (h *SyncHandler) HandleGetSyncStatus(c *gin.Context) {
    ctx, span := h.tracer.Start(c.Request.Context(), "HandleGetSyncStatus")
    defer span.End()

    // Parse sync record ID
    syncID, err := uuid.Parse(c.Param("sync_id"))
    if err != nil {
        span.SetAttributes(attribute.String("error", "invalid_sync_id"))
        c.JSON(http.StatusBadRequest, gin.H{
            "error": ErrInvalidSyncID.Error(),
        })
        return
    }

    // Get sync status
    record, err := h.syncService.GetSyncStatus(ctx, syncID)
    if err != nil {
        span.SetAttributes(attribute.String("error", "status_retrieval_failed"))
        status := http.StatusInternalServerError
        if errors.Is(err, services.ErrRecordNotFound) {
            status = http.StatusNotFound
        }
        c.JSON(status, gin.H{
            "error": fmt.Sprintf("failed to retrieve sync status: %v", err),
        })
        return
    }

    // Return status response
    c.JSON(http.StatusOK, gin.H{
        "sync_id": record.ID,
        "status": record.Status,
        "entity_type": record.EntityType,
        "created_at": record.CreatedAt,
        "updated_at": record.UpdatedAt,
        "retry_count": record.RetryCount,
        "error_message": record.ErrorMessage,
    })
}