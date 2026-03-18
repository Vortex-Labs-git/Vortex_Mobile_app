class ValveDevice {
  final String id;
  final String name;
  final ValveStatus status;
  final int position;
  final bool isConnected;
  final DateTime? lastUpdated;
  final String? macAddress;

  ValveDevice({
    required this.id,
    required this.name,
    this.status = ValveStatus.offline,
    this.position = 0,
    this.isConnected = false,
    this.lastUpdated,
    this.macAddress,
  });

  ValveDevice copyWith({
    String? id,
    String? name,
    ValveStatus? status,
    int? position,
    bool? isConnected,
    DateTime? lastUpdated,
    String? macAddress,
  }) {
    return ValveDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      position: position ?? this.position,
      isConnected: isConnected ?? this.isConnected,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      macAddress: macAddress ?? this.macAddress,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'status': status.name,
      'position': position,
      'isConnected': isConnected,
      'lastUpdated': lastUpdated?.toIso8601String(),
      'macAddress': macAddress,
    };
  }

  factory ValveDevice.fromJson(Map<String, dynamic> json) {
    return ValveDevice(
      id: json['id'],
      name: json['name'],
      status: ValveStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ValveStatus.offline,
      ),
      position: json['position'] ?? 0,
      isConnected: json['isConnected'] ?? false,
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.parse(json['lastUpdated'])
          : null,
      macAddress: json['macAddress'],
    );
  }
}

enum ValveStatus { open, closed, partial, offline, error }

extension ValveStatusExtension on ValveStatus {
  String get displayName {
    switch (this) {
      case ValveStatus.open: return 'Open';
      case ValveStatus.closed: return 'Closed';
      case ValveStatus.partial: return 'Partial';
      case ValveStatus.offline: return 'Offline';
      case ValveStatus.error: return 'Error';
    }
  }
}
