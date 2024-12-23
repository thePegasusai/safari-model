package com.wildlifesafari.app.utils

import android.graphics.*
import android.renderscript.*
import android.util.Size
import androidx.camera.core.ImageProxy
import java.nio.ByteBuffer
import kotlinx.coroutines.*
import kotlin.math.roundToInt

/**
 * Utility class providing optimized image processing functions for ML operations and camera handling.
 * Implements memory-efficient processing with hardware acceleration support.
 *
 * @version 1.0
 * @since 2023-10-01
 */
object ImageUtils {
    // External library versions used:
    // androidx.camera.core:1.2.0
    // kotlinx.coroutines:1.7.0

    private const val MAX_BITMAP_SIZE = 1024 * 1024 * 4 // 4MB max bitmap size
    private const val DEFAULT_BUFFER_SIZE = 1024 * 1024 // 1MB default buffer size
    private var useHardwareAcceleration = true

    /**
     * Thread-safe bitmap pool for memory reuse
     */
    private val bitmapPool = object {
        private val pool = mutableListOf<Bitmap>()
        
        @Synchronized
        fun acquire(width: Int, height: Int, config: Bitmap.Config): Bitmap {
            val index = pool.indexOfFirst { 
                it.width == width && it.height == height && it.config == config 
            }
            return if (index != -1) {
                pool.removeAt(index)
            } else {
                Bitmap.createBitmap(width, height, config)
            }
        }

        @Synchronized
        fun release(bitmap: Bitmap) {
            if (pool.size < 10) { // Limit pool size
                bitmap.eraseColor(Color.TRANSPARENT)
                pool.add(bitmap)
            } else {
                bitmap.recycle()
            }
        }
    }

    /**
     * Thread-safe byte buffer pool for memory reuse
     */
    private val bufferPool = object {
        private val pool = mutableListOf<ByteBuffer>()

        @Synchronized
        fun acquire(size: Int): ByteBuffer {
            val index = pool.indexOfFirst { it.capacity() >= size }
            return if (index != -1) {
                pool.removeAt(index).apply { clear() }
            } else {
                ByteBuffer.allocateDirect(size)
            }
        }

        @Synchronized
        fun release(buffer: ByteBuffer) {
            if (pool.size < 5) { // Limit pool size
                pool.add(buffer)
            }
        }
    }

    /**
     * Prepares a bitmap for ML model input with optimized processing.
     *
     * @param inputBitmap The source bitmap to process
     * @param targetSize The desired output size for ML input
     * @param useHardwareAcceleration Whether to use hardware acceleration
     * @return Processed bitmap optimized for ML input
     * @throws OutOfMemoryError if memory allocation fails
     * @throws IllegalArgumentException if input parameters are invalid
     */
    @JvmStatic
    @Throws(OutOfMemoryError::class, IllegalArgumentException::class)
    suspend fun prepareBitmapForML(
        inputBitmap: Bitmap,
        targetSize: Int,
        useHardwareAcceleration: Boolean = true
    ): Bitmap = withContext(Dispatchers.Default) {
        require(targetSize > 0) { "Target size must be positive" }
        require(!inputBitmap.isRecycled) { "Input bitmap is recycled" }

        try {
            val scaledBitmap = resizeBitmap(
                inputBitmap,
                targetSize,
                targetSize,
                true
            )

            // Convert to ARGB_8888 if needed
            val processedBitmap = if (scaledBitmap.config != Bitmap.Config.ARGB_8888) {
                bitmapPool.acquire(
                    scaledBitmap.width,
                    scaledBitmap.height,
                    Bitmap.Config.ARGB_8888
                ).also { targetBitmap ->
                    Canvas(targetBitmap).drawBitmap(scaledBitmap, 0f, 0f, null)
                    if (scaledBitmap != inputBitmap) {
                        bitmapPool.release(scaledBitmap)
                    }
                }
            } else {
                scaledBitmap
            }

            return@withContext processedBitmap
        } catch (e: Exception) {
            throw IllegalStateException("Failed to prepare bitmap for ML", e)
        }
    }

    /**
     * Resizes a bitmap while maintaining aspect ratio if requested.
     *
     * @param bitmap Source bitmap to resize
     * @param width Target width
     * @param height Target height
     * @param maintainAspectRatio Whether to maintain aspect ratio
     * @return Resized bitmap
     * @throws IllegalArgumentException if input parameters are invalid
     */
    @JvmStatic
    @Throws(IllegalArgumentException::class)
    fun resizeBitmap(
        bitmap: Bitmap,
        width: Int,
        height: Int,
        maintainAspectRatio: Boolean = true
    ): Bitmap {
        require(width > 0 && height > 0) { "Target dimensions must be positive" }
        require(!bitmap.isRecycled) { "Input bitmap is recycled" }

        val sourceWidth = bitmap.width
        val sourceHeight = bitmap.height

        if (sourceWidth == width && sourceHeight == height) {
            return bitmap
        }

        val targetWidth: Int
        val targetHeight: Int

        if (maintainAspectRatio) {
            val ratio = sourceWidth.toFloat() / sourceHeight.toFloat()
            if (width.toFloat() / height.toFloat() > ratio) {
                targetHeight = height
                targetWidth = (height * ratio).roundToInt()
            } else {
                targetWidth = width
                targetHeight = (width / ratio).roundToInt()
            }
        } else {
            targetWidth = width
            targetHeight = height
        }

        val matrix = Matrix()
        val scaleX = targetWidth.toFloat() / sourceWidth.toFloat()
        val scaleY = targetHeight.toFloat() / sourceHeight.toFloat()
        matrix.setScale(scaleX, scaleY)

        return bitmapPool.acquire(targetWidth, targetHeight, bitmap.config).also { targetBitmap ->
            Canvas(targetBitmap).drawBitmap(bitmap, matrix, Paint(Paint.FILTER_BITMAP_FLAG))
        }
    }

    /**
     * Converts CameraX ImageProxy to Bitmap with optimal processing.
     *
     * @param imageProxy Source ImageProxy from CameraX
     * @param useHardwareAcceleration Whether to use hardware acceleration
     * @return Converted bitmap
     * @throws IllegalStateException if conversion fails
     */
    @JvmStatic
    @Throws(IllegalStateException::class)
    fun convertImageProxyToBitmap(
        imageProxy: ImageProxy,
        useHardwareAcceleration: Boolean = true
    ): Bitmap {
        val image = imageProxy.image ?: throw IllegalStateException("Invalid image proxy")
        
        val yBuffer = image.planes[0].buffer
        val uBuffer = image.planes[1].buffer
        val vBuffer = image.planes[2].buffer

        val ySize = yBuffer.remaining()
        val uSize = uBuffer.remaining()
        val vSize = vBuffer.remaining()

        val nv21 = ByteArray(ySize + uSize + vSize)

        yBuffer.get(nv21, 0, ySize)
        vBuffer.get(nv21, ySize, vSize)
        uBuffer.get(nv21, ySize + vSize, uSize)

        val yuvImage = YuvImage(
            nv21,
            ImageFormat.NV21,
            image.width,
            image.height,
            null
        )

        return bitmapPool.acquire(image.width, image.height, Bitmap.Config.ARGB_8888).also { bitmap ->
            val outputStream = ByteArrayOutputStream()
            yuvImage.compressToJpeg(
                Rect(0, 0, image.width, image.height),
                100,
                outputStream
            )
            val jpegData = outputStream.toByteArray()
            BitmapFactory.decodeByteArray(jpegData, 0, jpegData.size)?.let { decoded ->
                Canvas(bitmap).drawBitmap(decoded, 0f, 0f, null)
                decoded.recycle()
            }
        }
    }

    /**
     * Converts bitmap to ByteBuffer for ML model input with normalization support.
     *
     * @param bitmap Source bitmap to convert
     * @param normalizeValues Whether to normalize pixel values
     * @param normalizationScale Scale factor for normalization
     * @return ByteBuffer containing processed pixel data
     * @throws OutOfMemoryError if memory allocation fails
     */
    @JvmStatic
    @Throws(OutOfMemoryError::class)
    fun bitmapToByteBuffer(
        bitmap: Bitmap,
        normalizeValues: Boolean = true,
        normalizationScale: Float = 255f
    ): ByteBuffer {
        require(!bitmap.isRecycled) { "Input bitmap is recycled" }

        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width * height)
        
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        
        val buffer = bufferPool.acquire(width * height * 4).apply { 
            order(java.nio.ByteOrder.nativeOrder())
        }

        pixels.forEach { pixel ->
            val r = (pixel shr 16 and 0xFF)
            val g = (pixel shr 8 and 0xFF)
            val b = (pixel and 0xFF)

            if (normalizeValues) {
                buffer.putFloat(r / normalizationScale)
                buffer.putFloat(g / normalizationScale)
                buffer.putFloat(b / normalizationScale)
            } else {
                buffer.putFloat(r.toFloat())
                buffer.putFloat(g.toFloat())
                buffer.putFloat(b.toFloat())
            }
        }

        buffer.rewind()
        return buffer
    }

    /**
     * Checks if hardware acceleration is available on the device.
     *
     * @return true if hardware acceleration is supported
     */
    private fun isHardwareAccelerationAvailable(): Boolean {
        return try {
            RenderScript.create(null)
            true
        } catch (e: RSRuntimeException) {
            false
        }
    }
}