// Root-level build.gradle.kts for Wildlife Detection Safari Pokédex
// Plugin Versions
buildscript {
    // Version constants for build configuration
    val androidGradlePluginVersion = "8.1.0" // Latest stable AGP version
    val kotlinVersion = "1.9.0" // Latest stable Kotlin version
    val hiltVersion = "2.47" // Latest stable Hilt version
    
    repositories {
        google() // Android build tools and dependencies
        mavenCentral() // Primary Maven repository
        gradlePluginPortal() // Gradle plugin repository
    }
    
    dependencies {
        classpath("com.android.tools.build:gradle:$androidGradlePluginVersion")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
        classpath("com.google.dagger:hilt-android-gradle-plugin:$hiltVersion")
        classpath("org.jetbrains.kotlin:kotlin-serialization:$kotlinVersion")
    }
}

// Plugin configuration with production optimizations
plugins {
    id("com.android.application") version "8.1.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.0" apply false
    id("org.jetbrains.kotlin.kapt") version "1.9.0" apply false
    id("com.google.dagger.hilt.android") version "2.47" apply false
}

// Configuration for all projects
allprojects {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        
        // Maven repository security configuration
        maven {
            url = uri("https://maven.google.com")
            content {
                // Restrict to only Android-related artifacts
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
    }

    // Java compatibility configuration
    tasks.withType<JavaCompile> {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
        
        options.apply {
            // Enable all compiler warnings
            compilerArgs.add("-Xlint:all")
            // Treat warnings as errors in production
            compilerArgs.add("-Werror")
        }
    }

    // Kotlin configuration with optimizations
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile> {
        kotlinOptions {
            jvmTarget = "17"
            // Enable advanced Kotlin features and optimizations
            freeCompilerArgs = listOf(
                "-Xopt-in=kotlin.RequiresOptIn",
                "-Xjvm-default=all",
                "-Xcontext-receivers",
                "-Xskip-prerelease-check",
                "-Xjvm-default=all-compatibility",
                "-opt-in=kotlin.ExperimentalCoroutinesApi",
                "-opt-in=kotlinx.coroutines.FlowPreview"
            )
            // Enable explicit API mode for better API documentation
            apiVersion = "1.9"
            languageVersion = "1.9"
        }
    }
}

// Global task configuration
tasks {
    // Clean task configuration
    register("clean", Delete::class) {
        delete(rootProject.buildDir)
    }

    // Build optimization configurations
    withType<Test> {
        // Enable parallel test execution
        maxParallelForks = (Runtime.getRuntime().availableProcessors() / 2).takeIf { it > 0 } ?: 1
        
        // Configure test JVM arguments
        jvmArgs = listOf(
            "-Xmx2048m",
            "-XX:MaxMetaspaceSize=512m",
            "-XX:+HeapDumpOnOutOfMemoryError"
        )
    }
}

// Build cache configuration for faster builds
buildCache {
    local {
        isEnabled = true
        directory = File(rootDir, "build-cache")
        removeUnusedEntriesAfterDays = 7
    }
}

// Project-wide Gradle properties
ext {
    set("compileSdkVersion", 34)
    set("targetSdkVersion", 34)
    set("minSdkVersion", 24)
    
    // ML configuration properties
    set("tensorflowVersion", "2.14.0")
    set("openCVVersion", "4.8.0")
    
    // Architecture component versions
    set("composeVersion", "1.5.0")
    set("coroutinesVersion", "1.7.3")
    set("lifecycleVersion", "2.6.2")
    
    // Testing versions
    set("junitVersion", "5.10.0")
    set("espressoVersion", "3.5.1")
}

// Enable Gradle Build Scan for analytics
gradleEnterprise {
    buildScan {
        termsOfServiceUrl = "https://gradle.com/terms-of-service"
        termsOfServiceAgree = "yes"
        publishAlways()
        
        // Add custom tags for better build analytics
        tag("CI")
        value("Git Branch", providers.exec {
            commandLine("git", "rev-parse", "--abbrev-ref", "HEAD")
        }.standardOutput.asText.get().trim())
    }
}

// Configure dependency verification
dependencyLocking {
    lockAllConfigurations()
}

// Security scanning configuration
configurations.all {
    resolutionStrategy {
        // Force specific versions for security patches
        force("org.jetbrains.kotlin:kotlin-stdlib:1.9.0")
        force("org.jetbrains.kotlin:kotlin-stdlib-common:1.9.0")
        
        // Cache dynamic versions for 0 hours in production
        cacheDynamicVersionsFor(0, "hours")
        
        // Cache changing modules for 0 hours in production
        cacheChangingModulesFor(0, "hours")
    }
}