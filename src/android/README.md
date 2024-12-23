# Wildlife Detection Safari Pokédex - Android App

A cutting-edge mobile application leveraging Liquid Neural Networks (LNN) for real-time wildlife detection and 3D fossil scanning. This application provides an innovative platform for nature enthusiasts, researchers, and educational institutions to identify and catalog wildlife species with state-of-the-art accuracy.

## Features

- Real-time wildlife detection with 90% accuracy using LNN technology
- 3D fossil scanning and visualization with ARCore integration
- Offline-capable collection management
- Location-based discovery mapping
- Multi-language support (top 10 languages)
- Background synchronization
- Advanced camera integration with CameraX
- Optimized ML model processing

## Prerequisites

| Requirement | Version/Specification |
|------------|----------------------|
| Android Studio | 2023.1 or newer |
| Kotlin Plugin | 1.9.0+ |
| JDK | 17 or newer |
| Android SDK | 34 (build tools 34.0.0) |
| Minimum API | 26 (Android 8.0) |
| NDK | 25.2.9519653 |
| CMake | 3.22.1 |

## Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| Android Version | 8.0 (API 26) | 12.0 or newer |
| RAM | 4GB | 8GB |
| Storage | 64GB | 128GB |
| Camera | 12MP with autofocus | 48MP with LiDAR |
| GPU | OpenGL ES 3.1 | Vulkan 1.1 |
| Additional | ARCore compatibility | Neural Engine/AI Accelerator |

## Setup Instructions

1. **Clone the Repository**
   ```bash
   git clone https://github.com/your-org/wildlife-detection-safari
   cd wildlife-detection-safari/android
   ```

2. **Android Studio Configuration**
   - Open Android Studio 2023.1 or newer
   - Go to `File -> Open` and select the android directory
   - Wait for Gradle sync to complete
   - Install any missing SDK components when prompted

3. **SDK Configuration**
   - Open `SDK Manager` in Android Studio
   - Install Android SDK 34
   - Install NDK 25.2.9519653
   - Install CMake 3.22.1

4. **API Key Configuration**
   Create a `local.properties` file in the android directory:
   ```properties
   maps.api.key=your_google_maps_key
   ml.api.key=your_ml_service_key
   ```

5. **Build Configuration**
   - Select build variant: `debug` or `release`
   - Sync project with Gradle files
   - Build project (`Build -> Make Project`)

## Architecture Overview

The application follows Clean Architecture principles with MVVM pattern:

### Layer Structure
```
app/
├── presentation/    # UI Components, ViewModels
├── domain/         # Use Cases, Domain Models
├── data/           # Repositories, Data Sources
├── di/             # Dependency Injection
└── ml/             # ML Model Integration
```

### Key Components
- **Presentation Layer**: Jetpack Compose UI
- **Domain Layer**: Business Logic
- **Data Layer**: Repository Pattern
- **ML Layer**: LNN Implementation

## Development Guidelines

### Code Style
- Follow Kotlin coding conventions
- Use Kotlin coroutines for asynchronous operations
- Implement dependency injection with Hilt
- Follow SOLID principles
- Use Kotlin Flow for reactive programming

### Testing Requirements
- Unit tests: Minimum 80% coverage
- UI tests: Critical user flows
- Integration tests: API interactions
- Performance tests: ML model efficiency

## Build & Deploy

### Debug Build
```bash
./gradlew assembleDebug
```

### Release Build
```bash
./gradlew assembleRelease
```

### ProGuard Configuration
- ProGuard rules are defined in `proguard-rules.pro`
- Specific rules for ML models and AR components

## Testing

### Unit Tests
```bash
./gradlew test
```

### Instrumented Tests
```bash
./gradlew connectedAndroidTest
```

### Performance Tests
```bash
./gradlew benchmarkTest
```

## Troubleshooting

### Common Issues

1. **Gradle Sync Failed**
   - Clean project
   - Delete `.gradle` folder
   - Invalidate caches and restart

2. **ML Model Loading Issues**
   - Verify TensorFlow Lite dependencies
   - Check model file placement
   - Validate quantization settings

3. **AR Features Not Working**
   - Verify ARCore compatibility
   - Check Google Play Services for AR
   - Validate camera permissions

## Contributing

1. Fork the repository
2. Create feature branch
3. Commit changes
4. Push to branch
5. Create Pull Request

## License

Copyright © 2024 Wildlife Detection Safari Pokédex

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2024-01 | Initial release |
| 1.1.0 | 2024-02 | LNN optimization |
| 1.2.0 | 2024-03 | AR improvements |

## Contact

For technical support or queries:
- Email: support@wildlife-detection.com
- Issue Tracker: GitHub Issues