package com.wildlifesafari.app.data.ml

import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import com.wildlifesafari.app.utils.ImageUtils
import com.wildlifesafari.app.utils.Constants.MLConstants
import kotlinx.coroutines.*
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.gpu.GpuDelegate
import java.io.File
import java.nio.ByteBuffer
import java.nio.MappedByteBuffer
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.system.measureTimeMillis

/**
 * Enhanced TensorFlow Lite model executor optimized for mobile devices with hardware acceleration
 * and memory management capabilities.
 *
 * @version 2.14.0 - TensorFlow Lite
 * @since 2023-10-01
 */
class TFLiteModelExecutor(
    private val context: Context,
    private val modelConfig: ModelConfig
) : AutoCloseable {

    private var interpreter: Interpreter? = null
    private var gpuDelegate: GpuDelegate? = null
    private val isGpuEnabled = AtomicBoolean(false)
    private val bufferPool = ByteBufferPool()
    private val executionMetrics = ExecutionMetrics()

    /**
     * Configuration class for model execution parameters
     */
    data class ModelConfig(
        val modelFileName: String = "lnn_model.tflite",
        val numThreads: Int = MLConstants.NUM_THREADS,
        val useGpu: Boolean = MLConstants.SUPPORTS_HARDWARE_ACCELERATION,
        val batchSize: Int = MLConstants.MODEL_BATCH_SIZE,
        val quantizationBits: Int = MLConstants.MODEL_QUANTIZATION_BITS
    )

    /**
     * Detection result data class with comprehensive metadata
     */
    data class DetectionResult(
        val label: String,
        val confidence: Float,
        val boundingBox: RectF,
        val inferenceTime: Long,
        val processingTime: Long
    )

    /**
     * Metrics tracking for model execution performance
     */
    data class ExecutionMetrics(
        var averageInferenceTime: Float = 0f,
        var totalExecutions: Long = 0,
        var gpuAccelerationUsed: Boolean = false,
        var memoryUsage: Long = 0
    )

    init {
        initializeInterpreter()
    }

    /**
     * Initializes TFLite interpreter with optimal settings and hardware acceleration
     */
    private fun initializeInterpreter() {
        try {
            val options = Interpreter.Options().apply {
                setNumThreads(modelConfig.numThreads)
                setUseXNNPACK(true)
                
                if (modelConfig.useGpu) {
                    gpuDelegate = GpuDelegate(GpuDelegate.Options().apply {
                        setPrecisionLossAllowed(true)
                        setQuantizedModelsAllowed(true)
                    })
                    addDelegate(gpuDelegate)
                    isGpuEnabled.set(true)
                }
            }

            val modelBuffer = loadModelFile()
            interpreter = Interpreter(modelBuffer, options)
            
            Log.d(TAG, "Interpreter initialized with GPU: ${isGpuEnabled.get()}")
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing interpreter", e)
            cleanupGpu()
            throw RuntimeException("Failed to initialize TFLite interpreter", e)
        }
    }

    /**
     * Executes model inference with optimized processing and hardware acceleration
     */
    @OptIn(ExperimentalCoroutinesApi::class)
    suspend fun executeInference(
        inputImage: Bitmap,
        options: ExecutionOptions = ExecutionOptions()
    ): List<DetectionResult> = withContext(Dispatchers.Default) {
        try {
            val processingTime = measureTimeMillis {
                // Validate input
                ImageUtils.validateInputImage(inputImage)
                
                // Prepare input buffer
                val inputBuffer = preprocessImage(inputImage)
                
                // Prepare output buffer
                val outputBuffer = createOutputBuffer()
                
                // Execute inference
                val inferenceTime = measureTimeMillis {
                    interpreter?.run(inputBuffer, outputBuffer)
                }

                // Process results
                val results = processResults(outputBuffer, inferenceTime)
                
                // Update metrics
                updateExecutionMetrics(inferenceTime, results.size)
                
                // Cleanup
                bufferPool.release(inputBuffer)
                
                return@withContext results
            }
            
            Log.d(TAG, "Total processing time: $processingTime ms")
            emptyList()
        } catch (e: Exception) {
            Log.e(TAG, "Error during inference execution", e)
            throw InferenceException("Failed to execute inference", e)
        }
    }

    /**
     * Preprocesses image for model input with hardware acceleration when available
     */
    private suspend fun preprocessImage(bitmap: Bitmap): ByteBuffer = withContext(Dispatchers.Default) {
        try {
            val resizedBitmap = ImageUtils.prepareBitmapForML(
                bitmap,
                MLConstants.ML_MODEL_INPUT_SIZE,
                isGpuEnabled.get()
            )
            
            val buffer = ImageUtils.bitmapToByteBuffer(
                resizedBitmap,
                normalizeValues = true,
                normalizationScale = 255f
            )
            
            if (resizedBitmap != bitmap) {
                resizedBitmap.recycle()
            }
            
            buffer
        } catch (e: Exception) {
            throw PreprocessingException("Failed to preprocess image", e)
        }
    }

    /**
     * Creates and manages output buffers with memory optimization
     */
    private fun createOutputBuffer(): Array<Array<FloatArray>> {
        return Array(modelConfig.batchSize) {
            Array(MLConstants.MAX_DETECTIONS) {
                FloatArray(OUTPUT_CLASSES + 4) // 4 for bounding box coordinates
            }
        }
    }

    /**
     * Processes model output with confidence thresholding and result formatting
     */
    private fun processResults(
        outputBuffer: Array<Array<FloatArray>>,
        inferenceTime: Long
    ): List<DetectionResult> {
        return outputBuffer[0].filter { detection ->
            detection[OUTPUT_CLASSES + 0] >= MLConstants.DETECTION_THRESHOLD
        }.map { detection ->
            DetectionResult(
                label = labelMap[detection[OUTPUT_CLASSES + 0].toInt()],
                confidence = detection[OUTPUT_CLASSES + 1],
                boundingBox = RectF(
                    detection[OUTPUT_CLASSES + 2],
                    detection[OUTPUT_CLASSES + 3],
                    detection[OUTPUT_CLASSES + 4],
                    detection[OUTPUT_CLASSES + 5]
                ),
                inferenceTime = inferenceTime,
                processingTime = 0 // Updated later
            )
        }
    }

    /**
     * Updates execution metrics for performance monitoring
     */
    private fun updateExecutionMetrics(inferenceTime: Long, detectionCount: Int) {
        executionMetrics.apply {
            totalExecutions++
            averageInferenceTime = (averageInferenceTime * (totalExecutions - 1) + inferenceTime) / totalExecutions
            gpuAccelerationUsed = isGpuEnabled.get()
            memoryUsage = Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory()
        }
    }

    /**
     * Loads model file with memory mapping for efficient loading
     */
    private fun loadModelFile(): MappedByteBuffer {
        val modelFile = File(context.getExternalFilesDir(null), modelConfig.modelFileName)
        return modelFile.inputStream().channel.map(
            FileChannel.MapMode.READ_ONLY,
            0,
            modelFile.length()
        )
    }

    /**
     * Cleans up GPU resources safely
     */
    private fun cleanupGpu() {
        gpuDelegate?.close()
        gpuDelegate = null
        isGpuEnabled.set(false)
    }

    override fun close() {
        interpreter?.close()
        cleanupGpu()
        bufferPool.clear()
    }

    companion object {
        private const val TAG = "TFLiteModelExecutor"
        private const val OUTPUT_CLASSES = 1000 // Number of classes in the model
        
        private val labelMap: Map<Int, String> = mapOf(
            // Initialize with model labels
        )
    }

    /**
     * Custom exceptions for better error handling
     */
    class InferenceException(message: String, cause: Throwable? = null) : Exception(message, cause)
    class PreprocessingException(message: String, cause: Throwable? = null) : Exception(message, cause)
}

/**
 * Thread-safe ByteBuffer pool for memory optimization
 */
private class ByteBufferPool {
    private val pool = mutableListOf<ByteBuffer>()
    
    @Synchronized
    fun acquire(size: Int): ByteBuffer {
        val buffer = pool.firstOrNull { it.capacity() >= size }
        return if (buffer != null) {
            pool.remove(buffer)
            buffer.clear()
            buffer
        } else {
            ByteBuffer.allocateDirect(size)
        }
    }

    @Synchronized
    fun release(buffer: ByteBuffer) {
        if (pool.size < MAX_POOL_SIZE) {
            pool.add(buffer)
        }
    }

    @Synchronized
    fun clear() {
        pool.clear()
    }

    companion object {
        private const val MAX_POOL_SIZE = 3
    }
}