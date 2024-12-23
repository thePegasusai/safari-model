// Gradle version: 8.0
// Purpose: Project structure and repository configuration for Wildlife Detection Safari Pokédex

pluginManagement {
    repositories {
        google() // Android build tools and dependencies
        mavenCentral() // Primary Maven repository
        gradlePluginPortal() // Gradle plugin repository
    }
    
    // Plugin version management and resolution strategy
    resolutionStrategy {
        eachPlugin {
            when (requested.id.id) {
                // Android Gradle Plugin - Core build tools
                "com.android.application" -> {
                    useModule("com.android.tools.build:gradle:8.1.0")
                }
                // Kotlin Android Plugin - Kotlin language support
                "org.jetbrains.kotlin.android" -> {
                    useModule("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.0")
                }
                // Hilt Plugin - Dependency injection
                "com.google.dagger.hilt.android" -> {
                    useModule("com.google.dagger:hilt-android-gradle-plugin:2.47")
                }
                // TensorFlow Lite Plugin - ML model deployment
                "org.tensorflow.lite" -> {
                    useModule("org.tensorflow:tensorflow-lite-gradle-plugin:2.14.0")
                }
                // Sceneform Plugin - AR capabilities
                "com.google.ar.sceneform" -> {
                    useModule("com.google.ar.sceneform:plugin:1.17.1")
                }
            }
        }
    }
}

// Dependency resolution management configuration
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google() // Android dependencies
        mavenCentral() // Maven Central dependencies
    }
}

// Root project name configuration
rootProject.name = "WildlifeSafari"

// Include application module
include(":app")