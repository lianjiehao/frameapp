package studio.framecoach.framecoach

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var poseDetector: PoseDetectorChannel? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        poseDetector = PoseDetectorChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        poseDetector?.close()
        poseDetector = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
