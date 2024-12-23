# External imports with versions
from fastapi import FastAPI, Request  # version: 0.100.0
from fastapi.middleware.cors import CORSMiddleware  # version: 0.100.0
from fastapi.middleware.gzip import GZipMiddleware  # version: 0.100.0
import uvicorn  # version: 0.23.0
from prometheus_fastapi_instrumentator import Instrumentator  # version: 6.1.0
import sentry_sdk  # version: 1.29.0
from sentry_sdk.integrations.asgi import SentryAsgiMiddleware
import logging
from typing import Dict
import time
import os

# Internal imports
from .routes.detection import router as detection_router
from .services.detection_service import DetectionService
from .config import load_config

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def init_monitoring(app: FastAPI) -> None:
    """
    Initialize comprehensive monitoring and error tracking systems.
    
    Args:
        app: FastAPI application instance
    """
    # Initialize Sentry for error tracking
    sentry_sdk.init(
        dsn=os.getenv('SENTRY_DSN'),
        environment=os.getenv('ENVIRONMENT', 'production'),
        traces_sample_rate=0.1,
        profiles_sample_rate=0.1,
        enable_tracing=True
    )
    app.add_middleware(SentryAsgiMiddleware)
    
    # Initialize Prometheus metrics
    Instrumentator(
        should_group_status_codes=True,
        should_ignore_untemplated=True,
        should_respect_env_var=True,
        should_instrument_requests_inprogress=True,
        excluded_handlers=["/health"],
        env_var_name="ENABLE_METRICS",
        inprogress_name="wildlife_detection_inprogress",
        inprogress_labels=True
    ).instrument(app).expose(app, include_in_schema=False)
    
    logger.info("Monitoring systems initialized successfully")

def create_app() -> FastAPI:
    """
    Create and configure FastAPI application with all necessary middleware
    and security measures.
    
    Returns:
        FastAPI: Configured FastAPI application instance
    """
    # Create FastAPI instance with OpenAPI documentation
    app = FastAPI(
        title="Wildlife Detection Service",
        description="LNN-powered wildlife and fossil detection service",
        version="1.0.0",
        docs_url="/api/docs",
        redoc_url="/api/redoc"
    )
    
    # Load configuration
    ml_config, api_config = load_config()
    
    # Initialize detection service
    detection_service = DetectionService(
        config=ml_config.__dict__,
        cache_client=None,  # Will be initialized by service
        metrics=None  # Will be initialized by service
    )
    
    # Add CORS middleware
    app.add_middleware(
        CORSMiddleware,
        allow_origins=api_config.security_settings.get('allowed_origins', ["*"]),
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"]
    )
    
    # Add compression middleware
    app.add_middleware(GZipMiddleware, minimum_size=1000)
    
    # Initialize monitoring
    init_monitoring(app)
    
    # Add request ID middleware
    @app.middleware("http")
    async def add_request_id(request: Request, call_next):
        request_id = request.headers.get('X-Request-ID', str(time.time()))
        request.state.request_id = request_id
        response = await call_next(request)
        response.headers['X-Request-ID'] = request_id
        return response
    
    # Add performance monitoring middleware
    @app.middleware("http")
    async def add_performance_metrics(request: Request, call_next):
        start_time = time.perf_counter()
        response = await call_next(request)
        process_time = (time.perf_counter() - start_time) * 1000
        response.headers['X-Process-Time'] = str(process_time)
        return response
    
    # Register routes
    app.include_router(
        detection_router,
        prefix="/api/v1",
        tags=["detection"]
    )
    
    # Health check endpoint
    @app.get("/health")
    async def health_check() -> Dict:
        """Health check endpoint with service status"""
        try:
            service_health = await detection_service.health_check()
            return {
                "status": "healthy" if service_health['status'] == 'healthy' else "degraded",
                "timestamp": time.time(),
                "service_status": service_health
            }
        except Exception as e:
            logger.error(f"Health check failed: {str(e)}")
            return {
                "status": "unhealthy",
                "timestamp": time.time(),
                "error": str(e)
            }
    
    # Startup event handler
    @app.on_event("startup")
    async def startup_event():
        """Initialize services on startup"""
        logger.info("Starting Wildlife Detection Service")
        # Additional startup initialization can be added here
    
    # Shutdown event handler
    @app.on_event("shutdown")
    async def shutdown_event():
        """Cleanup resources on shutdown"""
        logger.info("Shutting down Wildlife Detection Service")
        # Additional cleanup can be added here
    
    return app

def main():
    """Application entry point with server configuration"""
    app = create_app()
    
    # Configure uvicorn server
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8080,
        workers=4,
        loop="uvloop",
        http="httptools",
        log_level="info",
        access_log=True,
        ssl_keyfile=os.getenv('SSL_KEYFILE'),
        ssl_certfile=os.getenv('SSL_CERTFILE')
    )

if __name__ == "__main__":
    main()

# Export app instance for ASGI servers
app = create_app()