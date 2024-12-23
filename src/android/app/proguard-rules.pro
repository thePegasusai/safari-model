# Wildlife Detection Safari Pokédex ProGuard Rules
# Version: 1.0
# Last Updated: 2024

####################################
# General Configuration
####################################
-optimizationpasses 5
-dontusemixedcaseclassnames
-dontskipnonpubliclibraryclasses
-verbose

# Keep important attributes
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exception
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keepattributes RuntimeVisibleAnnotations
-keepattributes RuntimeVisibleParameterAnnotations
-keepattributes RuntimeVisibleTypeAnnotations
-keepattributes RuntimeInvisibleAnnotations
-keepattributes RuntimeInvisibleParameterAnnotations
-keepattributes RuntimeInvisibleTypeAnnotations

####################################
# Android Framework Components
####################################
# Keep Android components
-keep class * extends androidx.appcompat.app.AppCompatActivity
-keep class * extends androidx.fragment.app.Fragment
-keep class * extends android.app.Application
-keep class * extends android.app.Service
-keep class * extends android.content.BroadcastReceiver
-keep class * extends android.content.ContentProvider

####################################
# Kotlin Specific Rules
####################################
# Keep Kotlin metadata
-keep class kotlin.Metadata { *; }
-keep class kotlin.reflect.** { *; }

# Coroutines
-keep class kotlinx.coroutines.** { *; }
-keepclassmembernames class kotlinx.** {
    volatile <fields>;
}
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}

####################################
# Machine Learning Components
####################################
# TensorFlow Lite
-keep class org.tensorflow.lite.** { *; }
-keep interface org.tensorflow.lite.** { *; }
-keep class org.tensorflow.lite.support.** { *; }

# Custom ML Components
-keep class com.wildlifesafari.app.data.ml.LNNExecutor { *; }
-keep class com.wildlifesafari.app.data.ml.ModelInterpreter { *; }
-keep class com.wildlifesafari.app.data.ml.model.** { *; }

####################################
# AR and Camera Components
####################################
# ARCore
-keep class com.google.ar.** { *; }
-keep class com.google.ar.core.** { *; }

# CameraX
-keep class androidx.camera.** { *; }
-keep class androidx.camera.core.** { *; }
-keep class androidx.camera.lifecycle.** { *; }
-keep class androidx.camera.view.** { *; }

# Custom Camera Implementation
-keepclassmembers class com.wildlifesafari.app.camera.** { *; }

####################################
# Data Persistence
####################################
# Room Database
-keep class androidx.room.** { *; }
-keep @androidx.room.* class *
-keepclassmembers class * {
    @androidx.room.* *;
}

# Local Database Entities
-keep class com.wildlifesafari.app.data.local.** { *; }
-keep class com.wildlifesafari.app.data.model.** { *; }

####################################
# Networking
####################################
# Retrofit
-keep class retrofit2.** { *; }
-keepclasseswithmembers class * {
    @retrofit2.http.* <methods>;
}
-keepattributes Signature
-keepattributes Exceptions

# OkHttp
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

####################################
# Dependency Injection
####################################
# Hilt
-keep class dagger.hilt.** { *; }
-keep class javax.inject.** { *; }
-keep class * extends dagger.hilt.android.internal.managers.ViewComponentManager.ViewWithFragmentComponentBuilder {
    <init>();
}

# Keep Hilt generated code
-keep,allowobfuscation @dagger.hilt.android.internal.GeneratedComponent class *
-keep,allowobfuscation @dagger.hilt.android.internal.GeneratedEntryPoint class *

####################################
# Optimization Configuration
####################################
# Enable optimizations
-optimizations !code/simplification/arithmetic,!code/simplification/cast,!field/*,!class/merging/*
-optimizations !method/inlining/*

# Preserve debugging information
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Preserve native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

####################################
# Miscellaneous
####################################
# Enums
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Parcelables
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Serializable
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# R8 full mode
-if class **.R$*
-keep class **.R$*