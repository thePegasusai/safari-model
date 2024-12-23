/**
 * Jest Configuration for Wildlife Detection Safari Pokédex Backend Services
 * Version: 1.0.0
 * 
 * Dependencies:
 * - jest@29.7.0
 * - ts-jest@29.1.1
 * 
 * This configuration provides comprehensive test coverage settings for all microservices
 * including collection, detection, auth, and sync services with optimized performance
 * settings and strict coverage requirements to ensure 99.9% system availability.
 */

/** @type {import('@jest/types').Config.InitialOptions} */
const config = {
  // Use ts-jest preset for TypeScript support
  preset: 'ts-jest',

  // Set Node.js as the test environment
  testEnvironment: 'node',

  // Define root directories for all microservices
  roots: [
    '<rootDir>/auth-service/src',
    '<rootDir>/collection-service/src',
    '<rootDir>/detection-service/src',
    '<rootDir>/sync-service/src',
    '<rootDir>/api-gateway/src'
  ],

  // Test file patterns
  testMatch: [
    '**/__tests__/**/*.+(ts|tsx|js)',
    '**/?(*.)+(spec|test).+(ts|tsx|js)'
  ],

  // TypeScript transformation configuration
  transform: {
    '^.+\\.(ts|tsx)$': 'ts-jest'
  },

  // Supported file extensions
  moduleFileExtensions: ['ts', 'tsx', 'js', 'jsx', 'json', 'node'],

  // Coverage configuration
  collectCoverage: true,
  coverageDirectory: '<rootDir>/coverage',
  coverageReporters: ['json', 'lcov', 'text', 'clover'],

  // Strict coverage thresholds to ensure high quality
  coverageThreshold: {
    global: {
      branches: 80,
      functions: 85,
      lines: 90,
      statements: 90
    }
  },

  // Global test setup file
  setupFilesAfterEnv: ['<rootDir>/jest.setup.js'],

  // Module path aliases for clean imports
  moduleNameMapper: {
    '@auth/(.*)': '<rootDir>/auth-service/src/$1',
    '@collection/(.*)': '<rootDir>/collection-service/src/$1',
    '@detection/(.*)': '<rootDir>/detection-service/src/$1',
    '@sync/(.*)': '<rootDir>/sync-service/src/$1',
    '@gateway/(.*)': '<rootDir>/api-gateway/src/$1'
  },

  // Performance and execution settings
  testTimeout: 10000, // 10 second timeout for tests
  maxWorkers: '50%', // Optimize CPU usage for CI/CD pipeline
  verbose: true, // Detailed test output
  detectOpenHandles: true, // Help identify hanging tests
  forceExit: true, // Ensure test process exits

  // Global settings for all test suites
  globals: {
    'ts-jest': {
      tsconfig: '<rootDir>/tsconfig.json',
      diagnostics: {
        warnOnly: false // Fail on TypeScript errors
      }
    }
  },

  // Ignore patterns
  testPathIgnorePatterns: [
    '/node_modules/',
    '/dist/',
    '/build/',
    '/coverage/'
  ],

  // Clear mocks between tests
  clearMocks: true,
  
  // Reset modules between tests
  resetModules: true,

  // Error handling
  bail: 1, // Stop after first test failure in CI
  errorOnDeprecated: true // Catch deprecated feature usage
};

module.exports = config;