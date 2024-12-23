# External imports
import os  # version: system
import yaml  # version: 6.0.1
from dataclasses import dataclass, field  # version: system
from typing import Dict, Tuple, Optional, Any  # version: system
import logging  # version: system
from functools import wraps  # version: system

# Global constants
DEFAULT_CONFIG_PATH = '/etc/detection-service/config.yml'
ENVIRONMENT_VARIABLE_PREFIX = 'DETECTION_SERVICE_'
CONFIG_VERSION = '1.0.0'
ALLOWED_ENVIRONMENTS = ['development', 'staging', 'production']
DEFAULT_ENVIRONMENT = 'development'

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def validate_config(cls):
    """Decorator to validate configuration dataclasses"""
    def validate_instance(instance):
        for field_name, field_value in instance.__dict__.items():
            validator_name = f'validate_{field_name}'
            if hasattr(instance, validator_name):
                validator = getattr(instance, validator_name)
                if not validator(field_value):
                    raise ValueError(f"Invalid configuration for {field_name}: {field_value}")
        return True

    def wrap(init):
        @wraps(init)
        def validated_init(self, *args, **kwargs):
            init(self, *args, **kwargs)
            validate_instance(self)
        return validated_init

    setattr(cls, '__post_init__', wrap(cls.__post_init__ if hasattr(cls, '__post_init__') else lambda self: None))
    return cls

@dataclass(frozen=True)
@validate_config
class MLConfig:
    """Machine Learning model configuration settings"""
    model_path: str = field(default='/models/detection_model.tflite')
    input_size: int = field(default=640)
    confidence_threshold: float = field(default=0.90)
    layer_size: int = field(default=1024)
    time_constants_range: Tuple[int, int] = field(default=(10, 100))
    batch_size: int = field(default=32)
    learning_rate: float = field(default=0.001)
    processing_timeout_ms: int = field(default=100)
    model_quantization: Dict[str, Any] = field(default_factory=lambda: {
        'type': 'INT8',
        'calibration_steps': 100,
        'optimization_level': 3
    })
    performance_metrics: Dict[str, Any] = field(default_factory=lambda: {
        'accuracy_threshold': 0.90,
        'latency_threshold_ms': 100,
        'memory_limit_mb': 512
    })

    def validate_model_path(self, value: str) -> bool:
        """Validate model path exists and is accessible"""
        if not os.path.exists(value):
            logger.error(f"Model path does not exist: {value}")
            return False
        return True

    def validate_input_size(self, value: int) -> bool:
        """Validate input resolution"""
        return 224 <= value <= 1024 and value % 32 == 0

    def validate_confidence_threshold(self, value: float) -> bool:
        """Validate confidence threshold"""
        return 0.0 <= value <= 1.0

    def validate_layer_size(self, value: int) -> bool:
        """Validate LNN layer size"""
        return 256 <= value <= 2048 and value % 128 == 0

    def validate_time_constants_range(self, value: Tuple[int, int]) -> bool:
        """Validate time constants range"""
        return 1 <= value[0] < value[1] <= 1000

@dataclass(frozen=True)
@validate_config
class APIConfig:
    """API and service configuration settings"""
    host: str = field(default='0.0.0.0')
    port: int = field(default=8080)
    api_version: str = field(default='v1')
    timeout: int = field(default=5000)
    max_retries: int = field(default=3)
    rate_limits: Dict[str, Any] = field(default_factory=lambda: {
        'default': {'requests': 60, 'period': 60},
        '/detect': {'requests': 30, 'period': 60}
    })
    security_settings: Dict[str, Any] = field(default_factory=lambda: {
        'tls_enabled': True,
        'min_tls_version': 'TLSv1.2',
        'cipher_suites': ['TLS_AES_256_GCM_SHA384', 'TLS_CHACHA20_POLY1305_SHA256'],
        'client_cert_required': True
    })
    monitoring_config: Dict[str, Any] = field(default_factory=lambda: {
        'metrics_enabled': True,
        'tracing_enabled': True,
        'logging_level': 'INFO',
        'performance_monitoring': True
    })
    health_check_config: Dict[str, Any] = field(default_factory=lambda: {
        'enabled': True,
        'interval_seconds': 30,
        'timeout_seconds': 5,
        'unhealthy_threshold': 3
    })
    circuit_breaker_config: Dict[str, Any] = field(default_factory=lambda: {
        'failure_threshold': 5,
        'recovery_timeout': 30,
        'half_open_timeout': 5
    })

    def validate_port(self, value: int) -> bool:
        """Validate port number"""
        return 1024 <= value <= 65535

    def validate_api_version(self, value: str) -> bool:
        """Validate API version format"""
        return value.startswith('v') and value[1:].isdigit()

def get_environment() -> str:
    """Get current deployment environment"""
    env = os.getenv('DETECTION_SERVICE_ENV', DEFAULT_ENVIRONMENT)
    if env not in ALLOWED_ENVIRONMENTS:
        logger.warning(f"Invalid environment {env}, using default: {DEFAULT_ENVIRONMENT}")
        return DEFAULT_ENVIRONMENT
    return env

def load_config(config_path: str = DEFAULT_CONFIG_PATH, validate_strict: bool = True) -> Tuple[MLConfig, APIConfig]:
    """Load and validate configuration from YAML and environment"""
    try:
        # Load YAML configuration
        if os.path.exists(config_path):
            with open(config_path, 'r') as f:
                config_data = yaml.safe_load(f)
        else:
            logger.warning(f"Config file not found at {config_path}, using defaults")
            config_data = {}

        # Override with environment variables
        env_prefix = ENVIRONMENT_VARIABLE_PREFIX
        for key, value in os.environ.items():
            if key.startswith(env_prefix):
                config_key = key[len(env_prefix):].lower()
                config_data[config_key] = value

        # Create and validate configurations
        ml_config = MLConfig(**config_data.get('ml_config', {}))
        api_config = APIConfig(**config_data.get('api_config', {}))

        # Log configuration state
        logger.info(f"Configuration loaded successfully for environment: {get_environment()}")
        
        return ml_config, api_config

    except Exception as e:
        logger.error(f"Error loading configuration: {str(e)}")
        if validate_strict:
            raise
        return MLConfig(), APIConfig()