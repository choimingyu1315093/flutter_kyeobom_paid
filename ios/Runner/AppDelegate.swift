import Flutter
import UIKit
import Network
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let pathMonitor = NWPathMonitor()
  private let pathQueue = DispatchQueue(label: "kyeobom.health.network")
  private var networkType = "unknown"

  // Foreground-only, opt-in volume metering. Audio data is never retained,
  // sent over a network, or written to a temporary file.
  private var babyAudioEngine: AVAudioEngine?
  private let babySoundLock = NSLock()
  private var babySoundDb = -100.0

  private func readBabySoundLevel() -> Double {
    babySoundLock.lock()
    defer { babySoundLock.unlock() }
    return babySoundDb
  }

  private func startBabySoundMonitoring() throws {
    if babyAudioEngine != nil { return }
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.record, mode: .measurement)
    try session.setActive(true)
    let engine = AVAudioEngine()
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.channelCount > 0 && format.sampleRate > 0 else {
      try? session.setActive(false, options: .notifyOthersOnDeactivation)
      throw NSError(domain: "KyeobomBaby", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "마이크 입력 형식이 지원되지 않습니다"])
    }
    babySoundLock.lock()
    babySoundDb = -100.0
    babySoundLock.unlock()
    input.installTap(onBus: 0, bufferSize: 1024, format: format) {
      [weak self] buffer, _ in
      guard let self = self,
            let channels = buffer.floatChannelData else { return }
      let frames = Int(buffer.frameLength)
      if frames == 0 { return }
      var energy = 0.0
      for i in 0..<frames {
        let sample = Double(channels[0][i])
        energy += sample * sample
      }
      let rms = sqrt(energy / Double(frames))
      let db = min(0.0, max(-100.0, 20.0 * log10(max(rms, 0.00001))))
      self.babySoundLock.lock()
      self.babySoundDb = db
      self.babySoundLock.unlock()
    }
    do {
      engine.prepare()
      try engine.start()
      babyAudioEngine = engine
    } catch {
      input.removeTap(onBus: 0)
      engine.stop()
      try? session.setActive(false, options: .notifyOthersOnDeactivation)
      throw error
    }
  }

  private func stopBabySoundMonitoring() {
    guard let engine = babyAudioEngine else { return }
    babyAudioEngine = nil
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    babySoundLock.lock()
    babySoundDb = -100.0
    babySoundLock.unlock()
    try? AVAudioSession.sharedInstance().setActive(
      false, options: .notifyOthersOnDeactivation)
  }

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
      case "startBabySoundMonitoring":
        do {
          try self.startBabySoundMonitoring()
          result(nil)
        } catch {
          result(FlutterError(code: "BABY_SOUND_UNAVAILABLE",
                              message: error.localizedDescription, details: nil))
        }
      case "readBabySoundLevel":
        result(self.readBabySoundLevel())
      case "stopBabySoundMonitoring":
        self.stopBabySoundMonitoring()
        result(nil)
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
