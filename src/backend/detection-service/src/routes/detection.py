# External imports with versions
from fastapi import APIRouter, UploadFile, File, HTTPException, Depends, BackgroundTasks  # version: 0.100.0
from fastapi.responses import JSONResponse  # version: 0.100.0
from pydantic import BaseModel, Field, validator  # version: 2.0.0
import numpy as np  # version: 1.24.0
from PIL import Image  # version: 10.0.0
from opentelemetry import trace  # version: 1.20.0
from circuitbreaker import circuit  # version: 1.4.0
import logging
from typing import List, Optional, Dict, Any
import io
import time
import uuid

# Internal imports
from ..services.detection_service import DetectionService
from ..utils.image_processing import load_image, preprocess_for_detection
from ..config import MLConfig, APIConfig

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize router with prefix and tags
router = APIRouter(prefix="/api/v1/detect", tags=["detection"])

# Global constants
SUPPORTED_IMAGE_TYPES = ['.jpg', '.jpeg', '.png', '.heic']
MAX_BATCH_SIZE = 32
DETECTION_TIMEOUT = 100  # milliseconds
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10MB
CORRELATION_ID_HEADER = "X-Correlation-ID"

# Initialize tracer
tracer = trace.get_tracer(__name__)

# Pydantic models for request/response validation
class DetectionOptions(BaseModel):
    enhance_detection: bool = Field(default=False, description="Enable enhanced detection mode")
    generate_3d: bool = Field(default=False, description="Generate 3D model for fossils")
    confidence_threshold: float = Field(default=0.90, ge=0.0, le=1.0)
    correlation_id: Optional[str] = Field(default=None)
    
    @validator('confidence_threshold')
    def validate_confidence(cls, v):
        if not 0.0 <= v <= 1.0:
            raise ValueError("Confidence threshold must be between 0.0 and 1.0")
        return v

class BatchDetectionRequest(BaseModel):
    process_type: str = Field(..., description="Type of detection: 'species' or 'fossil'")
    options: DetectionOptions
    correlation_ids: List[str] = Field(default_factory=list)

    @validator('process_type')
    def validate_process_type(cls, v):
        if v not in ['species', 'fossil']:
            raise ValueError("Process type must be either 'species' or 'fossil'")
        return v

# Circuit breaker configuration
@circuit(failure_threshold=5, recovery_timeout=30)
async def protected_detect_species(
    detection_service: DetectionService,
    image_data: np.ndarray,
    options: DetectionOptions
) -> Dict:
    """Protected species detection with circuit breaker pattern"""
    return await detection_service.detect_species(
        image_data,
        enhance_detection=options.enhance_detection,
        trace_id=options.correlation_id
    )

@router.post("/species")
async def detect_species(
    image_file: UploadFile = File(...),
    options: DetectionOptions = Depends(),
    background_tasks: BackgroundTasks = None,
    detection_service: DetectionService = Depends()
) -> JSONResponse:
    """
    Enhanced endpoint for real-time species detection with comprehensive validation.
    
    Args:
        image_file: Input image file
        options: Detection configuration options
        background_tasks: FastAPI background tasks
        detection_service: Injected detection service
        
    Returns:
        JSONResponse containing detection results and metrics
    """
    try:
        with tracer.start_as_current_span("detect_species") as span:
            # Validate correlation ID
            correlation_id = options.correlation_id or str(uuid.uuid4())
            span.set_attribute("correlation_id", correlation_id)
            
            # Validate file size and format
            if await image_file.size() > MAX_FILE_SIZE:
                raise HTTPException(
                    status_code=413,
                    detail="File size exceeds maximum limit"
                )
                
            file_ext = image_file.filename.lower().split('.')[-1]
            if f'.{file_ext}' not in SUPPORTED_IMAGE_TYPES:
                raise HTTPException(
                    status_code=415,
                    detail="Unsupported image format"
                )
            
            # Load and preprocess image
            start_time = time.perf_counter()
            try:
                image_data = await image_file.read()
                image_array = load_image(image_data, validate_content=True)
                processed_image = preprocess_for_detection(
                    image_array,
                    augment=options.enhance_detection
                )
            except Exception as e:
                logger.error(f"Image processing error: {str(e)}")
                raise HTTPException(
                    status_code=400,
                    detail="Invalid image data"
                )
            
            # Perform detection with circuit breaker
            try:
                detection_result = await protected_detect_species(
                    detection_service,
                    processed_image,
                    options
                )
            except Exception as e:
                logger.error(f"Detection error: {str(e)}")
                raise HTTPException(
                    status_code=503,
                    detail="Detection service temporarily unavailable"
                )
            
            # Calculate processing time
            processing_time = (time.perf_counter() - start_time) * 1000
            
            # Prepare response
            response = {
                "correlation_id": correlation_id,
                "species": detection_result.get("species", "Unknown"),
                "confidence": detection_result.get("confidence", 0.0),
                "processing_time_ms": processing_time,
                "enhanced_detection": options.enhance_detection,
                "metrics": detection_result.get("metrics", {})
            }
            
            # Schedule cleanup in background
            if background_tasks:
                background_tasks.add_task(
                    detection_service.cleanup_resources,
                    correlation_id
                )
            
            return JSONResponse(
                content=response,
                headers={"X-Correlation-ID": correlation_id}
            )
            
    except Exception as e:
        logger.error(f"Endpoint error: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail="Internal server error"
        )

@router.post("/fossil")
async def detect_fossil(
    scan_data: UploadFile = File(...),
    options: DetectionOptions = Depends(),
    background_tasks: BackgroundTasks = None,
    detection_service: DetectionService = Depends()
) -> JSONResponse:
    """
    Enhanced endpoint for fossil detection with 3D scan support.
    
    Args:
        scan_data: Input 3D scan data
        options: Detection configuration options
        background_tasks: FastAPI background tasks
        detection_service: Injected detection service
        
    Returns:
        JSONResponse containing fossil detection results and 3D model if requested
    """
    try:
        with tracer.start_as_current_span("detect_fossil") as span:
            # Validate correlation ID
            correlation_id = options.correlation_id or str(uuid.uuid4())
            span.set_attribute("correlation_id", correlation_id)
            
            # Validate file size
            if await scan_data.size() > MAX_FILE_SIZE:
                raise HTTPException(
                    status_code=413,
                    detail="Scan data size exceeds maximum limit"
                )
            
            # Process scan data
            start_time = time.perf_counter()
            try:
                scan_array = await scan_data.read()
                scan_array = np.frombuffer(scan_array, dtype=np.float32)
            except Exception as e:
                logger.error(f"Scan processing error: {str(e)}")
                raise HTTPException(
                    status_code=400,
                    detail="Invalid scan data format"
                )
            
            # Perform fossil detection
            try:
                detection_result = await detection_service.detect_fossil(
                    scan_array,
                    generate_3d=options.generate_3d
                )
            except Exception as e:
                logger.error(f"Fossil detection error: {str(e)}")
                raise HTTPException(
                    status_code=503,
                    detail="Detection service temporarily unavailable"
                )
            
            # Calculate processing time
            processing_time = (time.perf_counter() - start_time) * 1000
            
            # Prepare response
            response = {
                "correlation_id": correlation_id,
                "fossil_type": detection_result.get("fossil_type", "Unknown"),
                "confidence": detection_result.get("confidence", 0.0),
                "measurements": detection_result.get("measurements", {}),
                "processing_time_ms": processing_time
            }
            
            # Include 3D model if requested
            if options.generate_3d and "3d_model" in detection_result:
                response["3d_model"] = detection_result["3d_model"]
            
            # Schedule cleanup in background
            if background_tasks:
                background_tasks.add_task(
                    detection_service.cleanup_resources,
                    correlation_id
                )
            
            return JSONResponse(
                content=response,
                headers={"X-Correlation-ID": correlation_id}
            )
            
    except Exception as e:
        logger.error(f"Endpoint error: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail="Internal server error"
        )

@router.post("/batch")
async def batch_detect(
    files: List[UploadFile] = File(...),
    request: BatchDetectionRequest = Depends(),
    background_tasks: BackgroundTasks = None,
    detection_service: DetectionService = Depends()
) -> JSONResponse:
    """
    Batch processing endpoint for multiple images or scans.
    
    Args:
        files: List of input files
        request: Batch detection configuration
        background_tasks: FastAPI background tasks
        detection_service: Injected detection service
        
    Returns:
        JSONResponse containing batch processing results
    """
    try:
        with tracer.start_as_current_span("batch_detect") as span:
            # Validate batch size
            if len(files) > MAX_BATCH_SIZE:
                raise HTTPException(
                    status_code=400,
                    detail=f"Batch size exceeds maximum: {MAX_BATCH_SIZE}"
                )
            
            # Process files in batch
            start_time = time.perf_counter()
            processed_data = []
            
            for idx, file in enumerate(files):
                try:
                    file_data = await file.read()
                    if request.process_type == 'species':
                        image_array = load_image(file_data, validate_content=True)
                        processed_data.append(
                            preprocess_for_detection(
                                image_array,
                                augment=request.options.enhance_detection
                            )
                        )
                    else:
                        scan_array = np.frombuffer(file_data, dtype=np.float32)
                        processed_data.append(scan_array)
                except Exception as e:
                    logger.error(f"File processing error: {str(e)}")
                    continue
            
            # Perform batch detection
            try:
                batch_results = await detection_service.batch_process(
                    processed_data,
                    process_type=request.process_type
                )
            except Exception as e:
                logger.error(f"Batch processing error: {str(e)}")
                raise HTTPException(
                    status_code=503,
                    detail="Detection service temporarily unavailable"
                )
            
            # Calculate processing time
            processing_time = (time.perf_counter() - start_time) * 1000
            
            # Prepare response
            response = {
                "batch_size": len(files),
                "successful_detections": len(batch_results),
                "processing_time_ms": processing_time,
                "results": batch_results
            }
            
            # Schedule cleanup in background
            if background_tasks:
                background_tasks.add_task(
                    detection_service.cleanup_batch_resources,
                    request.correlation_ids
                )
            
            return JSONResponse(content=response)
            
    except Exception as e:
        logger.error(f"Endpoint error: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail="Internal server error"
        )

# Export router
__all__ = ['router']