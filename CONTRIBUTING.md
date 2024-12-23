# Contributing to Wildlife Detection Safari Pokédex

## Table of Contents
- [Introduction](#introduction)
- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
  - [Development Environment](#development-environment)
  - [Project Structure](#project-structure)
  - [ML Environment](#ml-environment)
- [Development Workflow](#development-workflow)
  - [Branching Strategy](#branching-strategy)
  - [Commit Guidelines](#commit-guidelines)
  - [Pull Request Process](#pull-request-process)
- [Code Standards](#code-standards)
  - [Mobile Development](#mobile-development)
  - [Backend Development](#backend-development)
  - [ML Development](#ml-development)
  - [Security Standards](#security-standards)

## Introduction

Welcome to the Wildlife Detection Safari Pokédex project! We're excited to have you contribute to this innovative platform that combines wildlife detection, fossil recognition, and citizen science. This document provides comprehensive guidelines for contributing to our project.

### Who Can Contribute?

- **Nature Enthusiasts**: Help improve species identification accuracy and user experience
- **Researchers**: Contribute to ML model enhancement and biodiversity data validation
- **Educational Institutions**: Develop educational content and learning materials
- **Conservation Workers**: Provide expertise on species handling and ethical guidelines
- **Developers**: Enhance core functionality across mobile, backend, and ML components

## Code of Conduct

We are committed to providing a welcoming and inclusive environment for all contributors. Please read our [Code of Conduct](CODE_OF_CONDUCT.md) before participating in our community.

## Getting Started

### Development Environment

#### Mobile Development
- iOS Development:
  - Xcode 15+
  - Swift 5.9
  - CocoaPods
  - iOS 15.0+ deployment target

- Android Development:
  - Android Studio 2023.1+
  - Kotlin 1.9
  - Gradle 8.0+
  - Android SDK 33+ (API level)

#### Backend Development
- Python 3.11+
- Node.js 18 LTS
- Go 1.21+
- Docker 24.0+
- Kubernetes 1.27+

### Project Structure

```
wildlife-safari-pokedex/
├── mobile/
│   ├── ios/           # iOS native code
│   ├── android/       # Android native code
│   └── shared/        # Shared mobile components
├── backend/
│   ├── detection/     # Species detection service
│   ├── collection/    # Collection management service
│   └── sync/         # Data synchronization service
├── ml/
│   ├── models/       # LNN model definitions
│   ├── training/     # Training pipelines
│   └── evaluation/   # Model evaluation tools
└── docs/            # Documentation
```

### ML Environment

- TensorFlow 2.14+
- PyTorch 2.0+
- CUDA 11.8+
- cuDNN 8.9+
- Python ML dependencies:
  ```
  numpy>=1.24.0
  scipy>=1.10.0
  pandas>=2.0.0
  scikit-learn>=1.3.0
  ```

## Development Workflow

### Branching Strategy

```
main
├── develop
│   ├── feature/ABC-123-feature-description
│   ├── bugfix/ABC-124-bug-description
│   └── enhancement/ABC-125-enhancement-description
└── release/v1.x.x
```

- `main`: Production-ready code
- `develop`: Integration branch for features
- `feature/*`: New features
- `bugfix/*`: Bug fixes
- `release/*`: Release preparation

### Commit Guidelines

Follow the Conventional Commits specification:

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Formatting
- `refactor`: Code restructuring
- `test`: Adding tests
- `chore`: Maintenance

Scopes:
- `mobile`: Mobile app changes
- `backend`: Backend services
- `ml`: Machine learning components
- `docs`: Documentation
- `infra`: Infrastructure

Example:
```
feat(mobile): add real-time species detection overlay

- Implements camera preview with AR overlay
- Adds species confidence indicators
- Integrates with LNN model

Closes #123
```

### Pull Request Process

1. Create an issue describing the change
2. Fork the repository and create a feature branch
3. Implement changes following our code standards
4. Ensure all tests pass and coverage meets requirements
5. Submit PR with comprehensive description
6. Obtain required reviews (2 for core components)
7. Pass CI/CD checks
8. Squash and merge after approval

## Code Standards

### Mobile Development

#### iOS (Swift)
- Follow Swift API Design Guidelines
- Use SwiftLint for code style enforcement
- Implement UI with SwiftUI when possible
- Document public APIs with inline documentation

#### Android (Kotlin)
- Follow Kotlin Coding Conventions
- Use ktlint for code style enforcement
- Implement UI with Jetpack Compose
- Document public APIs with KDoc

### Backend Development

#### Python Services
- Follow PEP 8 style guide
- Use type hints and docstrings
- Implement async operations with FastAPI
- Document APIs with OpenAPI/Swagger

#### Node.js Services
- Follow Airbnb JavaScript Style Guide
- Use TypeScript for type safety
- Implement async operations with Promises
- Document APIs with JSDoc

#### Go Services
- Follow Go Code Review Comments
- Use go fmt for formatting
- Implement concurrent operations with goroutines
- Document public APIs with godoc

### ML Development

#### Model Development
- Document model architecture and parameters
- Include training and evaluation scripts
- Provide performance benchmarks
- Follow TensorFlow Model Garden style guide

#### Data Quality
- Include data validation pipelines
- Document preprocessing steps
- Provide data augmentation scripts
- Include privacy preservation methods

### Security Standards

- Follow OWASP Security Guidelines
- Implement proper data encryption
- Use secure communication protocols
- Handle sensitive species data appropriately
- Report security issues via [Security Policy](SECURITY.md)

## Additional Resources

- [Bug Report Template](.github/ISSUE_TEMPLATE/bug_report.md)
- [Feature Request Template](.github/ISSUE_TEMPLATE/feature_request.md)
- [Security Policy](SECURITY.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)

## Questions or Need Help?

- Create an issue for technical questions
- Join our community Discord for discussions
- Email maintainers for sensitive inquiries

Thank you for contributing to Wildlife Detection Safari Pokédex!