package com.wildlifesafari.app.data.ml

import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import com.wildlifesafari.app.utils.ImageUtils
import com.wildlifesafari.app.utils.MLConstants
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.gpu.CompatibilityList
import org.tensorflow.lite.gpu.GpuDelegate
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import kotlin.math.exp

/**
 * Executor class for Liquid Neural Network (LNN) model operations with temporal processing
 * and GPU acceleration support.
 *
 * @property context Application context for resource access
 * @property modelPath Path to the LNN model file
 * @version 2.14.0 - TensorFlow Lite
 * @since 2023-10-01
 */
class LNNModelExecutor(
    private val context: Context,
    private val modelPath: String
) {
    private var interpreter: Interpreter? = null
    private var gpuDelegate: GpuDelegate? = null
    private var inputBuffer: ByteBuffer? = null
    private var lnnState: ByteBuffer? = null
    
    private val inputSize = MLConstants.ML_MODEL_INPUT_SIZE
    private val timeConstant = 0.1f // 100ms time constant for neural dynamics
    private val numNeurons = 1024 // Number of neurons in liquid layer
    private val stateSize = numNeurons * 4 // Float32 state per neuron
    
    companion object {
        private const val TAG = "LNNModelExecutor"
        private const val PIXEL_SIZE = 3 // RGB channels
        private const val BATCH_SIZE = 1
        private const val FLOAT_BYTES = 4
    }

    /**
     * Detection result data class containing species information and temporal metrics
     */
    data class DetectionResult(
        val speciesId: String,
        val confidence: Float,
        val temporalConsistency: Float,
        val processingTimeMs: Long
    )

    init {
        setupInterpreter()
        initializeBuffers()
    }

    /**
     * Sets up the TFLite interpreter with GPU acceleration if available
     */
    private fun setupInterpreter() {
        try {
            val options = Interpreter.Options().apply {
                setNumThreads(MLConstants.getOptimalThreadCount())
                
                if (CompatibilityList().isDelegateSupportedOnThisDevice) {
                    gpuDelegate = GpuDelegate(
                        GpuDelegate.Options().apply {
                            setPrecisionLossAllowed(true)
                            setQuantizedModelsAllowed(true)
                        }
                    )
                    addDelegate(gpuDelegate)
                }
            }

            val modelBuffer = loadModelFile()
            interpreter = Interpreter(modelBuffer, options)
            
            Log.d(TAG, "LNN Model initialized with GPU acceleration: ${gpuDelegate != null}")
        } catch (e: Exception) {
            Log.e(TAG, "Error setting up interpreter: ${e.message}")
            throw IllegalStateException("Failed to initialize LNN model", e)
        }
    }

    /**
     * Initializes input and state buffers for the LNN model
     */
    private fun initializeBuffers() {
        inputBuffer = ByteBuffer.allocateDirect(
            BATCH_SIZE * inputSize * inputSize * PIXEL_SIZE * FLOAT_BYTES
        ).apply {
            order(ByteOrder.nativeOrder())
        }

        lnnState = ByteBuffer.allocateDirect(stateSize * FLOAT_BYTES).apply {
            order(ByteOrder.nativeOrder())
            // Initialize with small random values for stability
            repeat(numNeurons) {
                putFloat((Math.random() * 0.01f).toFloat())
            }
        }
    }

    /**
     * Loads the LNN model file from assets
     */
    private fun loadModelFile(): MappedByteBuffer {
        val modelFile = File(context.getExternalFilesDir(null), modelPath)
        return modelFile.inputStream().channel.map(
            FileChannel.MapMode.READ_ONLY,
            0,
            modelFile.length()
        )
    }

    /**
     * Executes LNN model inference on input image with temporal processing
     *
     * @param inputImage Input bitmap for species detection
     * @return List of detection results with temporal consistency
     */
    suspend fun executeInference(inputImage: Bitmap): List<DetectionResult> = 
        withContext(Dispatchers.Default) {
            val startTime = System.currentTimeMillis()
            
            try {
                // Prepare input image
                val processedBitmap = ImageUtils.prepareBitmapForML(
                    inputImage,
                    inputSize,
                    MLConstants.SUPPORTS_HARDWARE_ACCELERATION
                )
                
                // Convert to input buffer
                inputBuffer = ImageUtils.bitmapToByteBuffer(
                    processedBitmap,
                    normalizeValues = true,
                    normalizationScale = 255f
                )

                // Prepare output buffers
                val outputBuffer = ByteBuffer.allocateDirect(
                    BATCH_SIZE * MLConstants.MAX_DETECTIONS * FLOAT_BYTES * 2
                ).apply {
                    order(ByteOrder.nativeOrder())
                }
                
                // Execute temporal processing steps
                repeat(5) { // Multiple timesteps for temporal consistency
                    updateLNNState(timeConstant)
                    
                    val inputs = mapOf(
                        0 to inputBuffer,
                        1 to lnnState
                    )
                    
                    val outputs = mapOf(
                        0 to outputBuffer,
                        1 to lnnState
                    )
                    
                    interpreter?.runForMultipleInputsOutputs(inputs, outputs)
                }

                // Process results
                val results = mutableListOf<DetectionResult>()
                outputBuffer.rewind()
                
                repeat(MLConstants.MAX_DETECTIONS) {
                    val confidence = outputBuffer.float
                    val speciesId = outputBuffer.float.toInt().toString()
                    
                    if (confidence > MLConstants.DETECTION_THRESHOLD) {
                        results.add(
                            DetectionResult(
                                speciesId = speciesId,
                                confidence = confidence,
                                temporalConsistency = calculateTemporalConsistency(),
                                processingTimeMs = System.currentTimeMillis() - startTime
                            )
                        )
                    }
                }

                results
            } catch (e: Exception) {
                Log.e(TAG, "Error during inference: ${e.message}")
                emptyList()
            }
        }

    /**
     * Updates LNN state based on temporal dynamics
     *
     * @param timeConstant Time constant for neural dynamics
     */
    private fun updateLNNState(timeConstant: Float) {
        lnnState?.apply {
            rewind()
            val stateArray = FloatArray(numNeurons)
            
            // Read current state
            repeat(numNeurons) {
                stateArray[it] = float
            }
            
            // Apply temporal dynamics
            rewind()
            stateArray.forEach { state ->
                val newState = state + timeConstant * (
                    -state + // Decay term
                    tanh(state) + // Non-linear activation
                    0.01f * (Math.random() * 2 - 1).toFloat() // Noise term
                )
                putFloat(newState.coerceIn(-1f, 1f)) // Stability constraints
            }
        }
    }

    /**
     * Calculates temporal consistency of detections
     */
    private fun calculateTemporalConsistency(): Float {
        var consistency = 0f
        lnnState?.apply {
            rewind()
            repeat(numNeurons) {
                consistency += abs(float)
            }
        }
        return (consistency / numNeurons).coerceIn(0f, 1f)
    }

    /**
     * Hyperbolic tangent activation function
     */
    private fun tanh(x: Float): Float {
        val ex = exp(2 * x)
        return ((ex - 1) / (ex + 1)).toFloat()
    }

    /**
     * Cleans up resources when executor is no longer needed
     */
    fun close() {
        interpreter?.close()
        gpuDelegate?.close()
        inputBuffer = null
        lnnState = null
    }
}