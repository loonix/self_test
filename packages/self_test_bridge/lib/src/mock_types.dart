// The value types the mocking commands take and return.
//
// These describe a notification, a location, a permission or a
// biometric attempt. They lived in bridge_commands.dart, which is a
// catalogue of command names and not the place for them.

/// Mock notification data for push notification testing
class MockNotification {
  final String id;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  String action;

  MockNotification({
    required this.id,
    required this.title,
    required this.body,
    Map<String, dynamic>? data,
    DateTime? timestamp,
    this.action = 'received',
  }) : data = data ?? {},
       timestamp = timestamp ?? DateTime.now();

  factory MockNotification.fromJson(Map<String, dynamic> json) {
    return MockNotification(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      data: (json['data'] as Map<String, dynamic>?) ?? {},
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : DateTime.now(),
      action: json['action'] as String? ?? 'received',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'data': data,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'action': action,
  };

  @override
  String toString() =>
      'MockNotification(id: $id, title: $title, action: $action)';

  /// Create a copy with updated values
  MockNotification copyWith({
    String? id,
    String? title,
    String? body,
    Map<String, dynamic>? data,
    DateTime? timestamp,
    String? action,
  }) {
    return MockNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      data: data ?? this.data,
      timestamp: timestamp ?? this.timestamp,
      action: action ?? this.action,
    );
  }
}

/// Mock location data for geolocation testing
class MockLocation {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double? altitude;
  final double? speed;
  final double? heading;
  final DateTime timestamp;

  MockLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy = 10.0,
    this.altitude,
    this.speed,
    this.heading,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory MockLocation.fromJson(Map<String, dynamic> json) {
    return MockLocation(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 10.0,
      altitude: (json['altitude'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    if (altitude != null) 'altitude': altitude,
    if (speed != null) 'speed': speed,
    if (heading != null) 'heading': heading,
    'timestamp': timestamp.millisecondsSinceEpoch,
  };

  @override
  String toString() =>
      'MockLocation(lat: $latitude, lng: $longitude, accuracy: $accuracy)';

  /// Create a copy with updated values
  MockLocation copyWith({
    double? latitude,
    double? longitude,
    double? accuracy,
    double? altitude,
    double? speed,
    double? heading,
    DateTime? timestamp,
  }) {
    return MockLocation(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      altitude: altitude ?? this.altitude,
      speed: speed ?? this.speed,
      heading: heading ?? this.heading,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// Permission types that can be mocked
enum MockPermissionType {
  camera,
  microphone,
  location,
  locationAlways,
  locationWhenInUse,
  photos,
  storage,
  contacts,
  calendar,
  reminders,
  notifications,
  bluetooth,
  sensors,
  speech,
  mediaLibrary;

  static MockPermissionType fromString(String value) {
    switch (value) {
      case 'camera':
        return MockPermissionType.camera;
      case 'microphone':
        return MockPermissionType.microphone;
      case 'location':
        return MockPermissionType.location;
      case 'location_always':
        return MockPermissionType.locationAlways;
      case 'location_when_in_use':
        return MockPermissionType.locationWhenInUse;
      case 'photos':
        return MockPermissionType.photos;
      case 'storage':
        return MockPermissionType.storage;
      case 'contacts':
        return MockPermissionType.contacts;
      case 'calendar':
        return MockPermissionType.calendar;
      case 'reminders':
        return MockPermissionType.reminders;
      case 'notifications':
        return MockPermissionType.notifications;
      case 'bluetooth':
        return MockPermissionType.bluetooth;
      case 'sensors':
        return MockPermissionType.sensors;
      case 'speech':
        return MockPermissionType.speech;
      case 'media_library':
        return MockPermissionType.mediaLibrary;
      default:
        throw ArgumentError('Unknown permission type: $value');
    }
  }
}

/// Permission states that can be mocked
enum MockPermissionState {
  granted,
  denied,
  restricted,
  limited,
  permanentDenied,
  provisional;

  static MockPermissionState fromString(String value) {
    switch (value) {
      case 'granted':
        return MockPermissionState.granted;
      case 'denied':
        return MockPermissionState.denied;
      case 'restricted':
        return MockPermissionState.restricted;
      case 'limited':
        return MockPermissionState.limited;
      case 'permanent_denied':
        return MockPermissionState.permanentDenied;
      case 'provisional':
        return MockPermissionState.provisional;
      default:
        throw ArgumentError('Unknown permission state: $value');
    }
  }
}

/// Connectivity states that can be mocked
enum MockConnectivityState {
  wifi,
  mobile,
  ethernet,
  bluetooth,
  vpn,
  none;

  static MockConnectivityState fromString(String value) {
    switch (value) {
      case 'wifi':
        return MockConnectivityState.wifi;
      case 'mobile':
        return MockConnectivityState.mobile;
      case 'ethernet':
        return MockConnectivityState.ethernet;
      case 'bluetooth':
        return MockConnectivityState.bluetooth;
      case 'vpn':
        return MockConnectivityState.vpn;
      case 'none':
        return MockConnectivityState.none;
      default:
        throw ArgumentError('Unknown connectivity state: $value');
    }
  }
}

/// Mock connectivity data
class MockConnectivity {
  final MockConnectivityState state;
  final bool isConnected;

  const MockConnectivity({required this.state, required this.isConnected});

  factory MockConnectivity.fromJson(Map<String, dynamic> json) {
    final state = MockConnectivityState.fromString(json['state'] as String);
    return MockConnectivity(
      state: state,
      isConnected:
          json['isConnected'] as bool? ?? (state != MockConnectivityState.none),
    );
  }

  Map<String, dynamic> toJson() => {
    'state': state.name,
    'isConnected': isConnected,
  };

  @override
  String toString() => 'MockConnectivity($state, connected: $isConnected)';
}

// =====================================================================
// BIOMETRIC MOCK DATA TYPES
// =====================================================================

/// Biometric types that can be mocked
enum MockBiometricType {
  faceId,
  touchId,
  fingerprint,
  iris,
  deviceCredential;

  static MockBiometricType fromString(String value) {
    switch (value) {
      case 'faceId':
        return MockBiometricType.faceId;
      case 'touchId':
        return MockBiometricType.touchId;
      case 'fingerprint':
        return MockBiometricType.fingerprint;
      case 'iris':
        return MockBiometricType.iris;
      case 'deviceCredential':
        return MockBiometricType.deviceCredential;
      default:
        throw ArgumentError('Unknown biometric type: $value');
    }
  }
}

/// Biometric authentication result types
enum MockBiometricResult {
  success,
  failed,
  cancelled,
  notAvailable,
  notEnrolled,
  lockedOut;

  static MockBiometricResult fromString(String value) {
    switch (value) {
      case 'success':
        return MockBiometricResult.success;
      case 'failed':
        return MockBiometricResult.failed;
      case 'cancelled':
        return MockBiometricResult.cancelled;
      case 'notAvailable':
        return MockBiometricResult.notAvailable;
      case 'notEnrolled':
        return MockBiometricResult.notEnrolled;
      case 'lockedOut':
        return MockBiometricResult.lockedOut;
      default:
        throw ArgumentError('Unknown biometric result: $value');
    }
  }
}

/// Record of a biometric authentication attempt
class BiometricAttempt {
  final DateTime timestamp;
  final String type;
  final String result;
  final String? reason;

  BiometricAttempt({
    required this.timestamp,
    required this.type,
    required this.result,
    this.reason,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.millisecondsSinceEpoch,
    'type': type,
    'result': result,
    if (reason != null) 'reason': reason,
  };

  factory BiometricAttempt.fromJson(Map<String, dynamic> json) {
    return BiometricAttempt(
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      type: json['type'] as String,
      result: json['result'] as String,
      reason: json['reason'] as String?,
    );
  }

  @override
  String toString() =>
      'BiometricAttempt($type, $result at $timestamp${reason != null ? ', reason: $reason' : ''})';
}
