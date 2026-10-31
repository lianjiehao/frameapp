package studio.framecoach.framecoach

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.tensorflow.lite.Interpreter
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import android.os.Handler
import android.os.Looper

/** Serial background inference; Dart submits at most one request at a time. */
class PoseDetectorChannel(context: Context, messenger: BinaryMessenger) {
    private val appContext = context.applicationContext
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "frame/pose_detector")
    private var interpreter: Interpreter? = null

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "close") {
                executor.execute { interpreter?.close(); interpreter = null; main.post { result.success(null) } }
            } else if (call.method == "detect") {
                val bytes = call.argument<ByteArray>("rgb")
                val width = call.argument<Int>("width") ?: 0
                val height = call.argument<Int>("height") ?: 0
                if (bytes == null || width != 192 || height != 256 || bytes.size != width * height * 3) {
                    result.error("invalid_pixels", "Expected normalized RGB preview", null)
                } else executor.execute {
                    try {
                        val engine = interpreter ?: run {
                            val model = appContext.assets.open("flutter_assets/assets/models/movenet_singlepose_lightning.tflite").use { it.readBytes() }
                            val buffer = ByteBuffer.allocateDirect(model.size).order(ByteOrder.nativeOrder())
                            buffer.put(model).rewind()
                            Interpreter(buffer, Interpreter.Options().setNumThreads(2)).also { interpreter = it }
                        }
                        // Fit the 192x256 preview into 192 square with symmetric
                        // horizontal padding; undo this padding for joint coordinates.
                        val input = ByteBuffer.allocateDirect(192 * 192 * 3).order(ByteOrder.nativeOrder())
                        for (y in 0 until 192) for (x in 0 until 192) {
                            if (x < 24 || x >= 168) { input.put(0); input.put(0); input.put(0) }
                            else {
                                val sx = ((x - 24 + .5) * width / 144).toInt().coerceIn(0, width - 1)
                                val sy = ((y + .5) * height / 192).toInt().coerceIn(0, height - 1)
                                val i = (sy * width + sx) * 3
                                input.put(bytes[i]); input.put(bytes[i + 1]); input.put(bytes[i + 2])
                            }
                        }
                        input.rewind()
                        val output = Array(1) { Array(1) { Array(17) { FloatArray(3) } } }
                        engine.run(input, output)
                        val joints = (5..16).map { i ->
                            val p = output[0][0][i]
                            listOf((p[1].toDouble() - .125) / .75, p[0].toDouble(), p[2].toDouble())
                        }
                        main.post { result.success(joints) }
                    } catch (error: Exception) {
                        main.post { result.error("pose_unavailable", "Local pose detection failed", null) }
                    }
                }
            } else result.notImplemented()
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        executor.execute { interpreter?.close(); interpreter = null }
        executor.shutdown()
    }
}
