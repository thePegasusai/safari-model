# External imports with versions
import pytest  # version: 7.4.0
import pytest_asyncio  # version: 0.21.0
import numpy as np  # version: 1.24.0
import asyncio  # version: 3.11
from fastapi.testclient import TestClient  # version: 0.100.0
import os
import json
import time
from concurrent.futures import ThreadPoolExecutor
from typing import Dict, List, Optional

# Internal imports
from ..src.services.detection_service import DetectionService
from ..src.routes.detection import router
from ..src.config import MLConfig, APIConfig

# Test configuration constants
TEST_CONFIG = {
    'confidence_threshold': 0.85,
    'max_batch_size': 32,
    'processing_timeout': 100,
    'memory_limit_mb': 1024,
    'rate_limit_rpm': 60,
    'concurrent_requests': 10
}

TEST_DATA_DIR = 'test_data/detection'
BENCHMARK_DATASET = 'test_data/benchmark'

class TestDetectionService:
    """Comprehensive test suite for the Wildlife Detection Safari Pokédex detection service"""

    @pytest.fixture(autouse=True)
    async def setup(self):
        """Initialize test environment and resources"""
        # Configure test client
        self.client = TestClient(router)
        
        # Load test configuration
        self.config = MLConfig()
        self.api_config = APIConfig()
        
        # Initialize service with test configuration
        self.detection_service = DetectionService(
            config={'species_model_path': 'test_models/test_model.tflite'},
            cache_client=None,
            metrics=None
        )
        
        # Set up test data paths
        self.test_images = self._load_test_images()
        self.test_scans = self._load_test_scans()
        
        # Initialize performance metrics
        self.performance_metrics = {
            'latencies': [],
            'memory_usage': [],
            'accuracies': []
        }

    def _load_test_images(self) -> List[np.ndarray]:
        """Load test image dataset"""
        images = []
        test_image_dir = os.path.join(TEST_DATA_DIR, 'images')
        for filename in os.listdir(test_image_dir):
            if filename.endswith(('.jpg', '.png')):
                image_path = os.path.join(test_image_dir, filename)
                images.append(np.load(image_path))
        return images

    def _load_test_scans(self) -> List[np.ndarray]:
        """Load test 3D scan dataset"""
        scans = []
        test_scan_dir = os.path.join(TEST_DATA_DIR, 'scans')
        for filename in os.listdir(test_scan_dir):
            if filename.endswith('.npy'):
                scan_path = os.path.join(test_scan_dir, filename)
                scans.append(np.load(scan_path))
        return scans

    @pytest.mark.asyncio
    async def test_species_detection_accuracy(self):
        """Test species detection accuracy against 90% requirement"""
        correct_detections = 0
        total_samples = len(self.test_images)
        
        for image in self.test_images:
            try:
                result = await self.detection_service.detect_species(
                    image,
                    enhance_detection=False
                )
                if result['confidence'] >= TEST_CONFIG['confidence_threshold']:
                    correct_detections += 1
                    
                # Record metrics
                self.performance_metrics['accuracies'].append(
                    result['confidence']
                )
                
            except Exception as e:
                pytest.fail(f"Detection failed: {str(e)}")
                
        accuracy = correct_detections / total_samples
        assert accuracy >= 0.90, f"Accuracy {accuracy:.2f} below required 90%"

    @pytest.mark.asyncio
    async def test_processing_time_requirement(self):
        """Verify sub-100ms processing time requirement"""
        for image in self.test_images[:100]:  # Test with 100 samples
            start_time = time.perf_counter()
            
            await self.detection_service.detect_species(
                image,
                enhance_detection=False
            )
            
            processing_time = (time.perf_counter() - start_time) * 1000
            self.performance_metrics['latencies'].append(processing_time)
            
            assert processing_time < TEST_CONFIG['processing_timeout'], \
                f"Processing time {processing_time:.2f}ms exceeded 100ms limit"

    @pytest.mark.asyncio
    async def test_api_rate_limiting(self):
        """Test API rate limiting enforcement"""
        # Send requests at maximum rate
        requests_sent = 0
        start_time = time.perf_counter()
        
        async def send_request():
            response = await self.client.post(
                "/api/v1/detect/species",
                files={"image": ("test.jpg", self.test_images[0].tobytes())}
            )
            return response.status_code
            
        # Send requests concurrently
        tasks = []
        for _ in range(TEST_CONFIG['rate_limit_rpm'] + 5):  # Test overflow
            tasks.append(asyncio.create_task(send_request()))
            
        # Gather results
        status_codes = await asyncio.gather(*tasks)
        
        # Verify rate limiting
        success_count = sum(1 for code in status_codes if code == 200)
        rate_limited_count = sum(1 for code in status_codes if code == 429)
        
        assert success_count <= TEST_CONFIG['rate_limit_rpm'], \
            "Rate limit not enforced"
        assert rate_limited_count > 0, \
            "Rate limiting not triggered for overflow requests"

    @pytest.mark.asyncio
    async def test_batch_processing(self):
        """Test batch processing capabilities"""
        batch_size = TEST_CONFIG['max_batch_size']
        test_batch = self.test_images[:batch_size]
        
        # Test batch processing
        results = await self.detection_service.batch_process(
            test_batch,
            process_type='species'
        )
        
        assert len(results) == batch_size, \
            f"Batch processing failed to handle {batch_size} images"
            
        # Verify results format
        for result in results:
            assert 'species' in result, "Missing species in result"
            assert 'confidence' in result, "Missing confidence score"
            assert result['confidence'] >= 0.0, "Invalid confidence score"

    @pytest.mark.asyncio
    async def test_fossil_detection(self):
        """Test fossil detection accuracy and 3D model generation"""
        for scan in self.test_scans:
            result = await self.detection_service.detect_fossil(
                scan,
                generate_3d=True
            )
            
            # Verify result structure
            assert 'fossil_type' in result, "Missing fossil type"
            assert 'confidence' in result, "Missing confidence score"
            assert 'measurements' in result, "Missing measurements"
            assert '3d_model' in result, "Missing 3D model data"
            
            # Validate measurements
            measurements = result['measurements']
            assert all(key in measurements for key in ['length', 'width', 'height']), \
                "Missing required measurements"

    @pytest.mark.benchmark
    async def test_performance_metrics(self, benchmark):
        """Comprehensive performance benchmarking"""
        def run_detection():
            return asyncio.run(
                self.detection_service.detect_species(
                    self.test_images[0],
                    enhance_detection=False
                )
            )
            
        # Run benchmark
        benchmark(run_detection)
        
        # Calculate performance metrics
        latencies = np.array(self.performance_metrics['latencies'])
        p95_latency = np.percentile(latencies, 95)
        
        assert p95_latency < TEST_CONFIG['processing_timeout'], \
            f"P95 latency {p95_latency:.2f}ms exceeds requirement"

    @pytest.mark.asyncio
    async def test_error_handling(self):
        """Test error handling and recovery"""
        # Test invalid image
        with pytest.raises(ValueError):
            await self.detection_service.detect_species(
                np.zeros((10, 10)),  # Invalid image
                enhance_detection=False
            )
            
        # Test invalid scan data
        with pytest.raises(ValueError):
            await self.detection_service.detect_fossil(
                np.zeros(100),  # Invalid scan
                generate_3d=True
            )

    def teardown_method(self):
        """Clean up test resources"""
        # Clear test data
        self.test_images.clear()
        self.test_scans.clear()
        
        # Reset metrics
        self.performance_metrics = {
            'latencies': [],
            'memory_usage': [],
            'accuracies': []
        }