import Flutter
import UIKit
import Network

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let pathMonitor = NWPathMonitor()
  private let pathQueue = DispatchQueue(label: "kyeobom.health.network")
  private var networkType = "unknown"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    pathMonitor.pathUpdateHandler = { [weak self] path in
      let value = path.status != .satisfied ? "offline" : path.usesInterfaceType(.wifi) ? "wifi" : path.usesInterfaceType(.cellular) ? "cellular" : "other"
      DispatchQueue.main.async { self?.networkType = value }
    }
    pathMonitor.start(queue: pathQueue)
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
      case "getDeviceHealth":
        UIDevice.current.isBatteryMonitoringEnabled = true
        let device = UIDevice.current
        let battery = device.batteryLevel < 0 ? -1 : Int((device.batteryLevel * 100).rounded())
        let charging = device.batteryState == .charging || device.batteryState == .full
        let thermal: Int
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = 0
        case .fair: thermal = 1
        case .serious: thermal = 2
        case .critical: thermal = 3
        @unknown default: thermal = -1
        }
        result(["battery": battery, "charging": charging, "thermal": thermal, "network": self.networkType, "platform": "iOS"])
      case "enableWaitingMode":
        UIApplication.shared.isIdleTimerDisabled = true
        result(nil)
      case "disableWaitingMode":
        UIApplication.shared.isIdleTimerDisabled = false
        result(nil)
      case "getViewerLandscapeSide":
        // Query the UI's actual orientation so a 180-degree phone turn
        // updates both controls and the remote video's correction.
        let scenes = UIApplication.shared.connectedScenes.compactMap {
          $0 as? UIWindowScene
        }
        let activeScene = scenes.first(where: {
          $0.activationState == .foregroundActive
        }) ?? scenes.first
        switch activeScene?.interfaceOrientation {
        case .landscapeLeft:
          result("left")
        case .landscapeRight:
          result("right")
        default:
          result("unknown")
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
