/**
 * Extensions.kt
 * Provides comprehensive Kotlin extension functions for Android components with focus on
 * performance, accessibility, and ML operations optimization.
 *
 * @version 1.0
 * @since 2023-10-01
 */

package com.wildlifesafari.app.utils

import android.animation.ObjectAnimator
import android.animation.PathInterpolator
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.provider.Settings
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import androidx.fragment.app.Fragment
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlin.math.min

/**
 * Accessibility priority levels for content announcements
 */
enum class AccessibilityPriority {
    IMMEDIATE,
    HIGH,
    MEDIUM,
    LOW
}

/**
 * Configuration for ML model input preparation
 */
data class ModelInputConfig(
    val inputSize: Int = 640,
    val normalizeValue: Float = 255f,
    val meanValues: FloatArray = floatArrayOf(0.485f, 0.456f, 0.406f),
    val stdValues: FloatArray = floatArrayOf(0.229f, 0.224f, 0.225f)
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false

        other as ModelInputConfig
        return inputSize == other.inputSize &&
                normalizeValue == other.normalizeValue &&
                meanValues.contentEquals(other.meanValues) &&
                stdValues.contentEquals(other.stdValues)
    }

    override fun hashCode(): Int {
        var result = inputSize
        result = 31 * result + normalizeValue.hashCode()
        result = 31 * result + meanValues.contentHashCode()
        result = 31 * result + stdValues.contentHashCode()
        return result
    }
}

/**
 * Fades in a View with natural easing and system animation respect
 *
 * @param duration Animation duration in milliseconds
 * @param respectAnimationSettings Whether to respect system animation settings
 */
fun View.fadeIn(
    duration: Long = 300,
    respectAnimationSettings: Boolean = true
) {
    // Check system animation settings if required
    if (respectAnimationSettings) {
        val animationScale = Settings.Global.getFloat(
            context.contentResolver,
            Settings.Global.ANIMATOR_DURATION_SCALE,
            1.0f
        )
        if (animationScale == 0f) {
            alpha = 1f
            visibility = View.VISIBLE
            return
        }
    }

    // Cancel any ongoing animations
    animate().cancel()

    // Configure and start fade in animation
    visibility = View.VISIBLE
    alpha = 0f

    ObjectAnimator.ofFloat(this, View.ALPHA, 0f, 1f).apply {
        this.duration = duration
        interpolator = PathInterpolator(0.4f, 0.0f, 0.2f, 1.0f) // Natural easing
        addListener(
            onEnd = { alpha = 1f },
            onCancel = { alpha = 1f }
        )
        start()
    }
}

/**
 * Fades out a View with natural easing and proper cleanup
 *
 * @param duration Animation duration in milliseconds
 * @param respectAnimationSettings Whether to respect system animation settings
 */
fun View.fadeOut(
    duration: Long = 300,
    respectAnimationSettings: Boolean = true
) {
    // Check system animation settings if required
    if (respectAnimationSettings) {
        val animationScale = Settings.Global.getFloat(
            context.contentResolver,
            Settings.Global.ANIMATOR_DURATION_SCALE,
            1.0f
        )
        if (animationScale == 0f) {
            alpha = 0f
            visibility = View.GONE
            return
        }
    }

    // Cancel any ongoing animations
    animate().cancel()

    ObjectAnimator.ofFloat(this, View.ALPHA, 1f, 0f).apply {
        this.duration = duration
        interpolator = PathInterpolator(0.4f, 0.0f, 0.2f, 1.0f) // Natural easing
        addListener(
            onEnd = {
                alpha = 0f
                visibility = View.GONE
            },
            onCancel = {
                alpha = 0f
                visibility = View.GONE
            }
        )
        start()
    }
}

/**
 * Sets accessibility text with WCAG 2.1 AA compliance
 *
 * @param text Accessibility description text
 * @param priority Announcement priority level
 */
fun View.setAccessibilityText(
    text: String,
    priority: AccessibilityPriority = AccessibilityPriority.MEDIUM
) {
    // Validate input text
    if (text.isBlank()) return

    // Set minimum touch target size (48dp)
    val minTouchTarget = (48 * resources.displayMetrics.density).toInt()
    if (minimumHeight < minTouchTarget) {
        minimumHeight = minTouchTarget
    }
    if (minimumWidth < minTouchTarget) {
        minimumWidth = minTouchTarget
    }

    // Configure accessibility properties
    contentDescription = text
    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
    
    // Set role description based on view type
    ViewCompat.setAccessibilityDelegate(this, object : ViewCompat.AccessibilityDelegate() {
        override fun onInitializeAccessibilityNodeInfo(
            host: View,
            info: AccessibilityNodeInfoCompat
        ) {
            super.onInitializeAccessibilityNodeInfo(host, info)
            when (host) {
                is ImageView -> info.roleDescription = "Image"
                is ViewGroup -> info.roleDescription = "Group"
                else -> info.roleDescription = "Button"
            }
        }
    })

    // Handle announcement priority
    when (priority) {
        AccessibilityPriority.IMMEDIATE -> announceForAccessibility(text)
        AccessibilityPriority.HIGH -> postDelayed({ announceForAccessibility(text) }, 100)
        AccessibilityPriority.MEDIUM -> postDelayed({ announceForAccessibility(text) }, 300)
        AccessibilityPriority.LOW -> postDelayed({ announceForAccessibility(text) }, 500)
    }
}

/**
 * Converts ImageProxy to memory-optimized Bitmap for ML processing
 *
 * @param config Bitmap configuration for memory optimization
 * @return Optimized Bitmap instance
 */
fun android.media.Image.toBitmap(
    config: Bitmap.Config = Bitmap.Config.ARGB_8888
): Bitmap {
    val buffer = planes[0].buffer
    val pixelStride = planes[0].pixelStride
    val rowStride = planes[0].rowStride
    val rowPadding = rowStride - pixelStride * width

    // Create bitmap with efficient memory allocation
    val bitmap = Bitmap.createBitmap(
        width + rowPadding / pixelStride,
        height,
        config
    )

    buffer.rewind()
    bitmap.copyPixelsFromBuffer(buffer)

    // Handle EXIF orientation
    val matrix = Matrix()
    matrix.postRotate(imageInfo?.rotationDegrees?.toFloat() ?: 0f)
    
    return Bitmap.createBitmap(
        bitmap,
        0,
        0,
        width,
        height,
        matrix,
        true
    ).also {
        bitmap.recycle() // Properly recycle the intermediate bitmap
    }
}

/**
 * Prepares Bitmap for ML model input with optimization
 *
 * @param config Model input configuration
 * @return Normalized pixel data as FloatArray
 */
fun Bitmap.toMLInput(config: ModelInputConfig = ModelInputConfig()): FloatArray {
    // Calculate optimal scale for model input size
    val scale = min(
        config.inputSize.toFloat() / width,
        config.inputSize.toFloat() / height
    )
    
    // Create scaled bitmap using hardware acceleration when available
    val scaledBitmap = Bitmap.createScaledBitmap(
        this,
        (width * scale).toInt(),
        (height * scale).toInt(),
        true
    )

    // Prepare pixel array with proper size
    val pixels = IntArray(scaledBitmap.width * scaledBitmap.height)
    scaledBitmap.getPixels(
        pixels,
        0,
        scaledBitmap.width,
        0,
        0,
        scaledBitmap.width,
        scaledBitmap.height
    )

    // Convert and normalize pixels efficiently
    return FloatArray(pixels.size * 3) { i ->
        val pixel = pixels[i / 3]
        val channel = i % 3
        val value = when (channel) {
            0 -> (pixel shr 16 and 0xFF) / config.normalizeValue // R
            1 -> (pixel shr 8 and 0xFF) / config.normalizeValue  // G
            else -> (pixel and 0xFF) / config.normalizeValue     // B
        }
        (value - config.meanValues[channel]) / config.stdValues[channel]
    }.also {
        scaledBitmap.recycle() // Cleanup scaled bitmap
    }
}

/**
 * Utility function to add animation listener with proper cleanup
 */
private fun ObjectAnimator.addListener(
    onEnd: () -> Unit = {},
    onCancel: () -> Unit = {}
) {
    android.animation.AnimatorListenerAdapter().apply {
        addListener(object : android.animation.Animator.AnimatorListener {
            override fun onAnimationStart(animation: android.animation.Animator) {}
            override fun onAnimationEnd(animation: android.animation.Animator) {
                onEnd()
                removeAllListeners()
            }
            override fun onAnimationCancel(animation: android.animation.Animator) {
                onCancel()
                removeAllListeners()
            }
            override fun onAnimationRepeat(animation: android.animation.Animator) {}
        })
    }
}