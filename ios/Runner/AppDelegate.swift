import Flutter
import UIKit
import Network
import AVFoundation
import UserNotifications
import firebase_messaging
import flutter_webrtc
import WebRTC
import CoreVideo

private final class BabyCryRtcRenderer: NSObject, RTCAudioRenderer {
  let receive: (AVAudioPCMBuffer) -> Void
  init(receive: @escaping (AVAudioPCMBuffer) -> Void) { self.receive = receive }
  func render(pcmBuffer: AVAudioPCMBuffer) { receive(pcmBuffer) }
}

// This code intentionally lives in the existing Swift target file to avoid
// modifying local Xcode project/signing settings.
private final class NightLumaPolicy {
  private(set) var active = false
  private var darkSamples = 0
  private var brightSamples = 0
  private var strengthStep = 0

  func observe(mean: Double, darkFraction: Double) {
    guard mean.isFinite, darkFraction.isFinite else { reset(); return }
    if mean >= 0.42 || darkFraction < 0.45 || mean < 0.012 {
      reset()
      return
    }
    let dark = mean <= 0.23 && darkFraction >= 0.80
    let bright = mean >= 0.32 || darkFraction < 0.65
    if !active {
      darkSamples = dark ? darkSamples + 1 : 0
      if darkSamples >= 3 { active = true; brightSamples = 0 }
    } else {
      brightSamples = bright ? brightSamples + 1 : 0
      if brightSamples >= 2 { reset() }
    }
  }

  func nextStrengthStep() -> Int {
    guard active else { strengthStep = 0; return 0 }
    strengthStep = min(8, strengthStep + 1)
    return strengthStep
  }

  func reset() {
    active = false
    darkSamples = 0
    brightSamples = 0
    strengthStep = 0
  }

  static func lut(step: Int, low: Int, high: Int) -> [UInt8] {
    let amount = Double(max(0, min(8, step))) / 8.0
    return (0...255).map { value in
      guard value > low, value < high, amount > 0 else { return UInt8(value) }
      let x = Double(value - low) / Double(high - low)
      let lift = min(0.18, max(0, (pow(x, 0.65) - x) * min(1, max(0, x / 0.035))))
      let taper = min(1, max(0, (0.72 - x) / 0.32))
      return UInt8(min(high, max(value, Int((Double(low) + (x + lift * taper * amount) * Double(high - low)).rounded()))))
    }
  }
}

private final class NightVideoProcessor: NSObject, ExternalVideoProcessingDelegate {
  private let policy = NightLumaPolicy()
  private let fullTables = (0...8).map { NightLumaPolicy.lut(step: $0, low: 0, high: 255) }
  private let videoTables = (0...8).map { NightLumaPolicy.lut(step: $0, low: 16, high: 235) }
  private var nextSample: TimeInterval = 0
  private var bypassUntil: TimeInterval = 0
  private var slowFrames = 0
  private var pool: CVPixelBufferPool?
  private var poolWidth = 0
  private var poolHeight = 0
  private var poolFormat: OSType = 0

  func onFrame(_ frame: RTCVideoFrame) -> RTCVideoFrame {
    let started = ProcessInfo.processInfo.systemUptime
    guard started >= bypassUntil, policy.active || started >= nextSample,
          let source = frame.buffer as? RTCCVPixelBuffer else { return frame }
    let src = source.pixelBuffer
    let format = CVPixelBufferGetPixelFormatType(src)
    let full = format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    guard full || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
          CVPixelBufferGetPlaneCount(src) == 2 else { return frame }
    let w = CVPixelBufferGetWidth(src), h = CVPixelBufferGetHeight(src)
    guard w > 0, h > 0, w * h <= 2_100_000 else { return frame }
    guard CVPixelBufferLockBaseAddress(src, .readOnly) == kCVReturnSuccess else { return frame }
    defer {
      CVPixelBufferUnlockBaseAddress(src, .readOnly)
      if ProcessInfo.processInfo.systemUptime - started > 0.035 {
        slowFrames += 1
        if slowFrames >= 3 {
          policy.reset()
          bypassUntil = ProcessInfo.processInfo.systemUptime + 10
          slowFrames = 0
        }
      } else { slowFrames = 0 }
    }
    guard let yBase = CVPixelBufferGetBaseAddressOfPlane(src, 0)?.assumingMemoryBound(to: UInt8.self) else { return frame }
    let yStride = CVPixelBufferGetBytesPerRowOfPlane(src, 0)
    let low = full ? 0.0 : 16.0, range = full ? 255.0 : 219.0
    var sum = 0.0, dark = 0
    let cropX = max(0, Int(source.cropX)), cropY = max(0, Int(source.cropY))
    let cropW = min(w - cropX, Int(source.cropWidth))
    let cropH = min(h - cropY, Int(source.cropHeight))
    guard cropW > 0, cropH > 0 else { return frame }
    for gy in 0..<12 {
      let py = cropY + min(cropH - 1, (gy * 2 + 1) * cropH / 24)
      for gx in 0..<16 {
        let px = cropX + min(cropW - 1, (gx * 2 + 1) * cropW / 32)
        let v = min(1, max(0, (Double(yBase[py * yStride + px]) - low) / range))
        sum += v
        if v < 0.30 { dark += 1 }
      }
    }
    let mean = sum / 192.0, fraction = Double(dark) / 192.0
    if started >= nextSample {
      policy.observe(mean: mean, darkFraction: fraction)
      nextSample = started + 0.4
    } else if mean >= 0.42 || fraction < 0.45 || mean < 0.012 {
      policy.reset()
    }
    guard policy.active else { return frame }
    let step = policy.nextStrengthStep()
    let table = full ? fullTables[step] : videoTables[step]
    guard let dst = makeBuffer(width: w, height: h, format: format) else { return frame }
    CVBufferPropagateAttachments(src, dst)
    guard CVPixelBufferLockBaseAddress(dst, []) == kCVReturnSuccess else { return frame }
    defer { CVPixelBufferUnlockBaseAddress(dst, []) }
    guard let outY = CVPixelBufferGetBaseAddressOfPlane(dst, 0)?.assumingMemoryBound(to: UInt8.self),
          let srcUV = CVPixelBufferGetBaseAddressOfPlane(src, 1),
          let outUV = CVPixelBufferGetBaseAddressOfPlane(dst, 1) else { return frame }
    let outStride = CVPixelBufferGetBytesPerRowOfPlane(dst, 0)
    for r in 0..<h {
      let a = yBase.advanced(by: r * yStride)
      let b = outY.advanced(by: r * outStride)
      for c in 0..<w { b[c] = table[Int(a[c])] }
    }
    let srcUVStride = CVPixelBufferGetBytesPerRowOfPlane(src, 1)
    let outUVStride = CVPixelBufferGetBytesPerRowOfPlane(dst, 1)
    let uvBytes = CVPixelBufferGetWidthOfPlane(src, 1) * 2
    let uvRows = CVPixelBufferGetHeightOfPlane(src, 1)
    guard uvBytes <= srcUVStride, uvBytes <= outUVStride else { return frame }
    for r in 0..<uvRows {
      memcpy(outUV.advanced(by: r * outUVStride), srcUV.advanced(by: r * srcUVStride), uvBytes)
    }
    let wrapped = RTCCVPixelBuffer(pixelBuffer: dst,
      adaptedWidth: source.width, adaptedHeight: source.height,
      cropWidth: source.cropWidth, cropHeight: source.cropHeight,
      cropX: source.cropX, cropY: source.cropY)
    return RTCVideoFrame(buffer: wrapped, rotation: frame.rotation, timeStampNs: frame.timeStampNs)
  }

  private func makeBuffer(width: Int, height: Int, format: OSType) -> CVPixelBuffer? {
    if pool == nil || poolWidth != width || poolHeight != height || poolFormat != format {
      pool = nil
      let attributes: [String: Any] = [
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferPixelFormatTypeKey as String: format,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
      ]
      var created: CVPixelBufferPool?
      guard CVPixelBufferPoolCreate(kCFAllocatorDefault, nil,
        attributes as CFDictionary, &created) == kCVReturnSuccess else { return nil }
      pool = created
      poolWidth = width; poolHeight = height; poolFormat = format
    }
    guard let pool = pool else { return nil }
    var output: CVPixelBuffer?
    // Bounded allocation; if the encoder holds too many buffers, bypass.
    let limits = [kCVPixelBufferPoolAllocationThresholdKey as String: 4] as CFDictionary
    guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault,
      pool, limits, &output) == kCVReturnSuccess else { return nil }
    return output
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var nightTrack: LocalVideoTrack?
  private var nightProcessor: NightVideoProcessor?
  private var nightTrackId: String?

  private func detachNightVideo(trackId: String? = nil) {
    if let trackId = trackId, trackId != nightTrackId { return }
    if let track = nightTrack, let processor = nightProcessor {
      track.removeProcessing(processor)
    }
    nightTrack = nil
    nightProcessor = nil
    nightTrackId = nil
  }

  private func attachNightVideo(trackId: String) -> Bool {
    if nightTrackId == trackId, nightProcessor != nil { return true }
    detachNightVideo()
    guard let track = FlutterWebRTCPlugin.sharedSingleton()?.localTracks?[trackId] as? LocalVideoTrack else { return false }
    let processor = NightVideoProcessor()
    track.addProcessing(processor)
    nightTrack = track
    nightProcessor = processor
    nightTrackId = trackId
    return true
  }

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
      case "attachNightVideo":
        let args = call.arguments as? [String: Any]
        result(self.attachNightVideo(trackId: args?["trackId"] as? String ?? ""))
      case "detachNightVideo":
        let args = call.arguments as? [String: Any]
        self.detachNightVideo(trackId: args?["trackId"] as? String)
        result(nil)
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
