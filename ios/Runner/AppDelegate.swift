import Flutter
import UIKit
import Network
import AVFoundation
import UserNotifications
import firebase_messaging
import flutter_webrtc
import WebRTC

private final class BabyCryRtcRenderer: NSObject, RTCAudioRenderer {
  let receive: (AVAudioPCMBuffer) -> Void
  init(receive: @escaping (AVAudioPCMBuffer) -> Void) { self.receive = receive }
  func render(pcmBuffer: AVAudioPCMBuffer) { receive(pcmBuffer) }
}

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
  private var cryCapture = false
  private var cryRate = 0
  private var cryCount = 0
  private var cryWindow: [Float] = []
  private var babyRtcTrack: LocalAudioTrack?
  private var babyRtcRenderer: BabyCryRtcRenderer?

  private func disableBabyCryCapture() {
    babySoundLock.lock()
    cryCapture = false
    cryCount = 0
    cryWindow.removeAll()
    babySoundLock.unlock()
  }

  private func readBabyCryWindow() -> [String: Any]? {
    babySoundLock.lock()
    defer { babySoundLock.unlock() }
    guard cryCapture, !cryWindow.isEmpty, cryCount == cryWindow.count else { return nil }
    let bytes = cryWindow.withUnsafeBufferPointer { Data(buffer: $0) }
    for index in cryWindow.indices { cryWindow[index] = 0 }
    cryCount = 0
    return ["pcm": FlutterStandardTypedData(float32: bytes), "rate": cryRate]
  }

  private func readBabySoundLevel() -> Double {
    babySoundLock.lock()
    defer { babySoundLock.unlock() }
    return babySoundDb
  }

  private func startBabyRtcMonitoring(trackId: String) throws {
    guard babyAudioEngine == nil, babyRtcTrack == nil,
          let track = FlutterWebRTCPlugin.sharedSingleton()?.localTracks?[trackId] as? LocalAudioTrack else {
      throw NSError(domain: "KyeobomBaby", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "WebRTC 마이크를 사용할 수 없습니다"])
    }
    let renderer = BabyCryRtcRenderer { [weak self] buffer in
      guard let self = self, let samples = buffer.int16ChannelData,
            buffer.frameLength > 0 else { return }
      let rate = Int(buffer.format.sampleRate.rounded())
      let channels = Int(buffer.format.channelCount)
      guard rate >= 16000, rate <= 192000, channels > 0 else { return }
      self.babySoundLock.lock()
      defer { self.babySoundLock.unlock() }
      guard self.cryCapture else { return }
      if self.cryRate != rate {
        self.cryRate = rate
        self.cryCount = 0
        self.cryWindow = [Float](repeating: 0, count: Int((Double(rate) * 0.975).rounded()))
      }
      var power = 0.0
      for j in 0..<Int(buffer.frameLength) {
        var value: Float = 0
        for c in 0..<channels { value += Float(samples[c][j]) / 32768.0 }
        value /= Float(channels)
        power += Double(value) * Double(value)
        if self.cryCount < self.cryWindow.count {
          self.cryWindow[self.cryCount] = value
          self.cryCount += 1
        }
      }
      self.babySoundDb = min(0, max(-100, 20 * log10(max(sqrt(power / Double(buffer.frameLength)), 0.00001))))
    }
    babySoundLock.lock()
    cryCapture = true
    cryRate = 0
    cryCount = 0
    cryWindow.removeAll()
    babySoundLock.unlock()
    babyRtcTrack = track
    babyRtcRenderer = renderer
    track.add(renderer)
  }

  private func startBabySoundMonitoring(enableCryQa: Bool) throws {
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
    cryRate = Int(format.sampleRate.rounded())
    cryCapture = enableCryQa && cryRate >= 16000 && cryRate <= 192000
    cryCount = 0
    cryWindow = cryCapture
      ? [Float](repeating: 0, count: Int((Double(cryRate) * 0.975).rounded()))
      : []
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
      if self.cryCapture {
        let copied = min(frames, self.cryWindow.count - self.cryCount)
        if copied > 0 {
          for index in 0..<copied {
            self.cryWindow[self.cryCount + index] = channels[0][index]
          }
          self.cryCount += copied
        }
      }
      self.babySoundLock.unlock()
    }
    do {
      engine.prepare()
      try engine.start()
      babyAudioEngine = engine
    } catch {
      input.removeTap(onBus: 0)
      engine.stop()
      disableBabyCryCapture()
      try? session.setActive(false, options: .notifyOthersOnDeactivation)
      throw error
    }
  }

  private func stopBabySoundMonitoring() {
    disableBabyCryCapture()
    if let track = babyRtcTrack, let renderer = babyRtcRenderer {
      track.remove(renderer)
    }
    babyRtcRenderer = nil
    babyRtcTrack = nil
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
    UNUserNotificationCenter.current().delegate = self
    FLTFirebaseMessagingPlugin.configureNotificationCenterDelegate()
    pathMonitor.pathUpdateHandler = { [weak self] path in
      let value = path.status != .satisfied ? "offline" : path.usesInterfaceType(.wifi) ? "wifi" : path.usesInterfaceType(.cellular) ? "cellular" : "other"
      DispatchQueue.main.async { self?.networkType = value }
    }
    pathMonitor.start(queue: pathQueue)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    if notification.request.identifier.hasPrefix("kyeobom-baby-cry-") {
      if #available(iOS 14.0, *) { completionHandler([.banner, .list, .sound]) }
      else { completionHandler([.alert, .sound]) }
      return
    }
    super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void) {
    if response.notification.request.identifier.hasPrefix("kyeobom-baby-cry-") {
      completionHandler()
      return
    }
    super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
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
      case "startBabyRtcMonitoring":
        do {
          let args = call.arguments as? [String: Any]
          try self.startBabyRtcMonitoring(trackId: args?["trackId"] as? String ?? "")
          result(nil)
        } catch {
          result(FlutterError(code: "BABY_RTC_UNAVAILABLE", message: error.localizedDescription, details: nil))
        }
      case "showBabyCryNotification":
        let content = UNMutableNotificationContent()
        content.title = "아기 울음소리가 감지됐어요"
        content.body = "아기의 상태를 확인해 주세요."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
          identifier: "kyeobom-baby-cry-" + UUID().uuidString, content: content, trigger: nil)) { error in
          DispatchQueue.main.async {
            if let error = error {
              result(FlutterError(code: "BABY_NOTIFICATION_FAILED", message: error.localizedDescription, details: nil))
            } else { result(nil) }
          }
        }
      case "startBabySoundMonitoring":
        do {
          let args = call.arguments as? [String: Any]
          try self.startBabySoundMonitoring(enableCryQa: args?["cryQa"] as? Bool == true)
          result(nil)
        } catch {
          result(FlutterError(code: "BABY_SOUND_UNAVAILABLE",
                              message: error.localizedDescription, details: nil))
        }
      case "readBabySoundLevel":
        result(self.readBabySoundLevel())
      case "readBabyCryWindow":
        result(self.readBabyCryWindow())
      case "disableBabyCryCapture":
        self.disableBabyCryCapture()
        result(nil)
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
