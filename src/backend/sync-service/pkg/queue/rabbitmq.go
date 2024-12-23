// Package queue provides message queue implementations for the sync service
// Version: 1.0.0
package queue

import (
    "context"
    "encoding/json"
    "fmt"
    "sync"
    "time"

    "github.com/opentracing/opentracing-go"
    "github.com/prometheus/client_golang/prometheus"
    amqp "github.com/rabbitmq/amqp091-go"
    "github.com/sony/gobreaker"

    "internal/config"
    "internal/models"
)

// Global constants for queue configuration
const (
    defaultReconnectDelay = time.Second * 5
    defaultPublishTimeout = time.Second * 10
    defaultConsumerTag    = "sync-service-consumer"
    defaultBatchSize      = 100
    defaultPrefetchCount  = 50
)

// Metric names
const (
    metricPublishTotal   = "sync_rabbitmq_publish_total"
    metricPublishErrors  = "sync_rabbitmq_publish_errors"
    metricConsumeTotal   = "sync_rabbitmq_consume_total"
    metricConsumeErrors  = "sync_rabbitmq_consume_errors"
    metricReconnects     = "sync_rabbitmq_reconnects_total"
    metricProcessingTime = "sync_rabbitmq_processing_seconds"
)

// RabbitMQClient implements a robust RabbitMQ client with monitoring and circuit breaker
type RabbitMQClient struct {
    conn             *amqp.Connection
    channel          *amqp.Channel
    config           *config.QueueConfig
    closed          bool
    breaker         *gobreaker.CircuitBreaker
    channelPool     *sync.Pool
    mu              sync.RWMutex
    metrics         *queueMetrics
    tracer          opentracing.Tracer
}

// queueMetrics holds Prometheus metrics for monitoring
type queueMetrics struct {
    publishTotal   prometheus.Counter
    publishErrors  prometheus.Counter
    consumeTotal   prometheus.Counter
    consumeErrors  prometheus.Counter
    reconnects     prometheus.Counter
    processingTime prometheus.Histogram
}

// NewRabbitMQClient creates a new RabbitMQ client with the given configuration
func NewRabbitMQClient(cfg *config.QueueConfig, tracer opentracing.Tracer) (*RabbitMQClient, error) {
    if cfg == nil {
        return nil, fmt.Errorf("queue configuration is required")
    }

    metrics := initializeMetrics()
    breaker := gobreaker.NewCircuitBreaker(gobreaker.Settings{
        Name:        "rabbitmq-circuit",
        MaxRequests: uint32(cfg.CircuitBreakerThreshold),
        Timeout:     time.Minute,
        OnStateChange: func(name string, from, to gobreaker.State) {
            if to == gobreaker.StateOpen {
                // Log circuit breaker opening
                fmt.Printf("Circuit breaker opened for %s\n", name)
            }
        },
    })

    client := &RabbitMQClient{
        config:   cfg,
        breaker:  breaker,
        metrics:  metrics,
        tracer:   tracer,
        channelPool: &sync.Pool{
            New: func() interface{} {
                return nil // Channels will be created on demand
            },
        },
    }

    if err := client.connect(); err != nil {
        return nil, fmt.Errorf("failed to connect to RabbitMQ: %w", err)
    }

    return client, nil
}

// PublishSyncMessage publishes a sync record to the queue with tracing and metrics
func (c *RabbitMQClient) PublishSyncMessage(ctx context.Context, record *models.SyncRecord) error {
    span, ctx := opentracing.StartSpanFromContext(ctx, "PublishSyncMessage")
    defer span.Finish()

    // Execute through circuit breaker
    _, err := c.breaker.Execute(func() (interface{}, error) {
        return nil, c.publishWithRetry(ctx, record)
    })

    if err != nil {
        c.metrics.publishErrors.Inc()
        return fmt.Errorf("failed to publish message: %w", err)
    }

    c.metrics.publishTotal.Inc()
    return nil
}

// ConsumeSyncMessages starts consuming messages from the queue
func (c *RabbitMQClient) ConsumeSyncMessages(ctx context.Context, handler func(*models.SyncRecord) error) error {
    span, ctx := opentracing.StartSpanFromContext(ctx, "ConsumeSyncMessages")
    defer span.Finish()

    // Set up channel with prefetch
    ch, err := c.getChannel()
    if err != nil {
        return fmt.Errorf("failed to get channel: %w", err)
    }

    if err := ch.Qos(defaultPrefetchCount, 0, false); err != nil {
        return fmt.Errorf("failed to set QoS: %w", err)
    }

    msgs, err := ch.Consume(
        c.config.Queue,
        defaultConsumerTag,
        false, // auto-ack
        false, // exclusive
        false, // no-local
        false, // no-wait
        nil,   // args
    )
    if err != nil {
        return fmt.Errorf("failed to start consuming: %w", err)
    }

    go func() {
        batch := make([]*models.SyncRecord, 0, defaultBatchSize)
        timer := time.NewTimer(time.Second)
        defer timer.Stop()

        for {
            select {
            case <-ctx.Done():
                return
            case msg, ok := <-msgs:
                if !ok {
                    return
                }

                start := time.Now()
                record := &models.SyncRecord{}
                if err := json.Unmarshal(msg.Body, record); err != nil {
                    c.metrics.consumeErrors.Inc()
                    msg.Nack(false, true) // Requeue message
                    continue
                }

                batch = append(batch, record)
                
                // Process batch if full or timer expired
                if len(batch) >= defaultBatchSize {
                    c.processBatch(ctx, batch, handler)
                    batch = batch[:0]
                    timer.Reset(time.Second)
                }

                c.metrics.processingTime.Observe(time.Since(start).Seconds())
                msg.Ack(false)
                c.metrics.consumeTotal.Inc()
            case <-timer.C:
                if len(batch) > 0 {
                    c.processBatch(ctx, batch, handler)
                    batch = batch[:0]
                }
                timer.Reset(time.Second)
            }
        }
    }()

    return nil
}

// Close gracefully shuts down the client
func (c *RabbitMQClient) Close() error {
    c.mu.Lock()
    defer c.mu.Unlock()

    if c.closed {
        return nil
    }

    if c.channel != nil {
        if err := c.channel.Close(); err != nil {
            return fmt.Errorf("failed to close channel: %w", err)
        }
    }

    if c.conn != nil {
        if err := c.conn.Close(); err != nil {
            return fmt.Errorf("failed to close connection: %w", err)
        }
    }

    c.closed = true
    return nil
}

// Helper functions

func (c *RabbitMQClient) connect() error {
    c.mu.Lock()
    defer c.mu.Unlock()

    url := fmt.Sprintf("amqp://%s:%s@%s:%d/", c.config.User, c.config.Password, c.config.Host, c.config.Port)
    conn, err := amqp.Dial(url)
    if err != nil {
        return err
    }

    ch, err := conn.Channel()
    if err != nil {
        conn.Close()
        return err
    }

    // Declare exchange and queue
    if err := ch.ExchangeDeclare(
        c.config.Exchange,
        "topic",
        true,  // durable
        false, // auto-delete
        false, // internal
        false, // no-wait
        nil,   // arguments
    ); err != nil {
        ch.Close()
        conn.Close()
        return err
    }

    if _, err := ch.QueueDeclare(
        c.config.Queue,
        true,  // durable
        false, // auto-delete
        false, // exclusive
        false, // no-wait
        nil,   // arguments
    ); err != nil {
        ch.Close()
        conn.Close()
        return err
    }

    c.conn = conn
    c.channel = ch
    c.closed = false

    // Monitor connection status
    go c.monitorConnection()

    return nil
}

func (c *RabbitMQClient) monitorConnection() {
    for {
        reason, ok := <-c.conn.NotifyClose(make(chan *amqp.Error))
        if !ok {
            // Connection closed normally
            return
        }

        c.metrics.reconnects.Inc()
        fmt.Printf("Connection closed: %s, reconnecting...\n", reason)

        // Reconnection loop
        for {
            time.Sleep(defaultReconnectDelay)
            if err := c.connect(); err == nil {
                break
            }
        }
    }
}

func (c *RabbitMQClient) getChannel() (*amqp.Channel, error) {
    if ch := c.channelPool.Get(); ch != nil {
        return ch.(*amqp.Channel), nil
    }

    ch, err := c.conn.Channel()
    if err != nil {
        return nil, err
    }

    c.channelPool.Put(ch)
    return ch, nil
}

func (c *RabbitMQClient) publishWithRetry(ctx context.Context, record *models.SyncRecord) error {
    data, err := json.Marshal(record)
    if err != nil {
        return err
    }

    msg := amqp.Publishing{
        DeliveryMode: amqp.Persistent,
        Timestamp:    time.Now(),
        ContentType:  "application/json",
        Body:        data,
        Headers: amqp.Table{
            "region":      c.config.Region,
            "entity_type": record.EntityType,
            "version":     record.Version,
        },
    }

    ctx, cancel := context.WithTimeout(ctx, defaultPublishTimeout)
    defer cancel()

    return c.channel.PublishWithContext(ctx,
        c.config.Exchange,
        fmt.Sprintf("%s.%s", record.EntityType, c.config.Region),
        false, // mandatory
        false, // immediate
        msg,
    )
}

func (c *RabbitMQClient) processBatch(ctx context.Context, batch []*models.SyncRecord, handler func(*models.SyncRecord) error) {
    span, _ := opentracing.StartSpanFromContext(ctx, "ProcessBatch")
    defer span.Finish()

    for _, record := range batch {
        if err := handler(record); err != nil {
            c.metrics.consumeErrors.Inc()
            // Handle error (could implement retry logic here)
            fmt.Printf("Error processing record %s: %v\n", record.ID, err)
        }
    }
}

func initializeMetrics() *queueMetrics {
    return &queueMetrics{
        publishTotal: prometheus.NewCounter(prometheus.CounterOpts{
            Name: metricPublishTotal,
            Help: "Total number of messages published",
        }),
        publishErrors: prometheus.NewCounter(prometheus.CounterOpts{
            Name: metricPublishErrors,
            Help: "Total number of publish errors",
        }),
        consumeTotal: prometheus.NewCounter(prometheus.CounterOpts{
            Name: metricConsumeTotal,
            Help: "Total number of messages consumed",
        }),
        consumeErrors: prometheus.NewCounter(prometheus.CounterOpts{
            Name: metricConsumeErrors,
            Help: "Total number of consume errors",
        }),
        reconnects: prometheus.NewCounter(prometheus.CounterOpts{
            Name: metricReconnects,
            Help: "Total number of reconnection attempts",
        }),
        processingTime: prometheus.NewHistogram(prometheus.HistogramOpts{
            Name:    metricProcessingTime,
            Help:    "Time spent processing messages",
            Buckets: prometheus.DefBuckets,
        }),
    }
}