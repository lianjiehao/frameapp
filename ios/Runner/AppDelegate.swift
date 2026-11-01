import Flutter
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FramePoseDetector") {
      FramePoseDetector.register(with: registrar)
    }
  }
}

/// Vision runs on a serial background queue and receives only upright preview RGB.
final class FramePoseDetector: NSObject, FlutterPlugin {
  private let queue = DispatchQueue(label: "studio.framecoach.pose", qos: .userInitiated)

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "frame/pose_detector", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(FramePoseDetector(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "close" { result(nil); return }
    guard call.method == "detect" else { result(FlutterMethodNotImplemented); return }
    guard let args = call.arguments as? [String: Any], let data = args["rgb"] as? FlutterStandardTypedData,
      let width = args["width"] as? Int, let height = args["height"] as? Int,
      width == 192, height == 256, data.data.count == width * height * 3 else {
      result(FlutterError(code: "invalid_pixels", message: "Expected normalized RGB preview", details: nil)); return
    }
    queue.async {
      do {
        guard let provider = CGDataProvider(data: data.data as CFData), let image = CGImage(
          width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
          bytesPerRow: width * 3, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
          decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
          throw NSError(domain: "FramePose", code: 1)
        }
        let request = VNDetectHumanBodyPoseRequest()
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        // Ambiguous multi-person input must not unlock the shutter.
        guard let observations = request.results, observations.count == 1, let body = observations.first else {
          DispatchQueue.main.async { result(nil) }; return
        }
        let names: [VNHumanBodyPoseObservation.JointName] = [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist, .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
        let points = try names.map { name -> [Double] in
          let p = try body.recognizedPoint(name)
          return [p.location.x, 1 - p.location.y, Double(p.confidence)]
        }
        DispatchQueue.main.async { result(points) }
      } catch {
        let nativeError = error as NSError
        DispatchQueue.main.async {
          result(FlutterError(code: "pose_unavailable", message: "Local pose detection failed",
            details: ["domain": nativeError.domain, "code": nativeError.code,
              "reason": nativeError.localizedDescription]))
        }
      }
    }
  }
}
