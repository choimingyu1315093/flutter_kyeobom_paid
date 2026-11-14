import Flutter
import UIKit

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
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HomeCameraWaitingMode") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "home_camera/screen",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "enableWaitingMode":
        UIApplication.shared.isIdleTimerDisabled = true
        result(nil)
      case "disableWaitingMode":
        UIApplication.shared.isIdleTimerDisabled = false
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
