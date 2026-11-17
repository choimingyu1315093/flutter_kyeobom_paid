/// Portable, testable safety decisions for the phone acting as the camera.
/// The OS exposes thermal *severity*, not a Celsius temperature.
enum HealthLevel { normal, warning, reduced, critical }

class DeviceHealthSnapshot {
  const DeviceHealthSnapshot({
    required this.platform,
    required this.battery,
    required this.charging,
    required this.thermal,
    required this.network,
    required this.collectedAt,
  });

  factory DeviceHealthSnapshot.fromNative(
    Map<String, dynamic> raw, DateTime now,
  ) {
    final percent = (raw['battery'] as num?)?.toInt();
    return DeviceHealthSnapshot(
      platform: raw['platform'] == 'iOS' ? 'iOS' : 'android',
      battery: percent != null && percent >= 0 && percent <= 100
          ? percent : null,
      charging: raw['charging'] == true,
      thermal: (raw['thermal'] as num?)?.toInt() ?? -1,
      network: (raw['network'] as String?) ?? 'unknown',
      collectedAt: now,
    );
  }

  final String platform;
  final int? battery;
  final bool charging;
  final int thermal;
  final String network;
  final DateTime collectedAt;

  bool get networkOffline => network == 'offline';
  bool get lowBattery => battery != null && battery! <= 20 && !charging;
  bool get dangerouslyLowBattery =>
      battery != null && battery! <= 5 && !charging;

  // Android status 0..6: SEVERE=3, CRITICAL=4.
  // iOS status 0..3: SERIOUS=2, CRITICAL=3.
  bool get seriousHeat => thermal >= (platform == 'iOS' ? 2 : 3);
  bool get criticalHeat => thermal >= (platform == 'iOS' ? 3 : 4);
  bool get warming =>
      thermal >= (platform == 'iOS' ? 1 : 2);

  HealthLevel get level {
    if (criticalHeat || dangerouslyLowBattery) return HealthLevel.critical;
    if (seriousHeat || lowBattery) return HealthLevel.reduced;
    if (warming || networkOffline) return HealthLevel.warning;
    return HealthLevel.normal;
  }

  bool get shouldReduceVideo => seriousHeat || lowBattery;
  bool get shouldStopVideo => criticalHeat || dangerouslyLowBattery;
  bool get canStartVideo => !shouldStopVideo && !networkOffline;

  String get warning {
    if (criticalHeat) return '기기가 과열되어 카메라를 보호하기 위해 송출을 중지합니다.';
    if (dangerouslyLowBattery) {
      return '배터리가 5% 이하입니다. 충전 연결 전까지 송출을 제한합니다.';
    }
    if (seriousHeat) return '발열이 높아 영상 품질을 낮춥니다. 통풍 상태를 확인하세요.';
    if (lowBattery) return '배터리가 20% 이하입니다. 충전하거나 절전 모드로 송출합니다.';
    if (warming) return '기기 온도가 상승 중입니다. 통풍 상태를 확인하세요.';
    if (networkOffline) return '거치폰의 인터넷 연결을 확인해 주세요.';
    return '';
  }

  String get heatLabel {
    if (thermal < 0) return '측정 불가';
    if (criticalHeat) return '위험';
    if (seriousHeat) return '높음';
    if (warming) return '주의';
    return '정상';
  }

  String get networkLabel {
    switch (network) {
      case 'wifi': return 'Wi-Fi';
      case 'cellular': return '모바일 데이터';
      case 'ethernet': return '유선';
      case 'offline': return '인터넷 끊김';
      default: return '정보 없음';
    }
  }

  String get batteryLabel =>
      battery == null ? '정보 없음' : '${battery!}%${charging ? ' · 충전 중' : ''}';

  Map<String, Object?> toFirestore() => {
    'battery': battery ?? -1,
    'charging': charging,
    'thermal': thermal,
    'network': network,
    'platform': platform,
    'risk': level.name,
    // Prevent delayed offline write replays from appearing as fresh data.
    'collectedAt': collectedAt,
    'active': true,
  };
}
