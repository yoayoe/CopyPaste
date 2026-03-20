enum PairingState { discovered, pairing, paired, disconnected }

class Device {
  final String id;
  final String name;
  final String platform;
  final String ip;
  final int tcpPort;
  final int webPort;
  final int protocolVersion;
  final PairingState pairingState;

  const Device({
    required this.id,
    required this.name,
    required this.platform,
    required this.ip,
    required this.tcpPort,
    required this.webPort,
    required this.protocolVersion,
    this.pairingState = PairingState.discovered,
  });

  Device copyWith({
    String? id,
    String? name,
    String? platform,
    String? ip,
    int? tcpPort,
    int? webPort,
    int? protocolVersion,
    PairingState? pairingState,
  }) =>
      Device(
        id: id ?? this.id,
        name: name ?? this.name,
        platform: platform ?? this.platform,
        ip: ip ?? this.ip,
        tcpPort: tcpPort ?? this.tcpPort,
        webPort: webPort ?? this.webPort,
        protocolVersion: protocolVersion ?? this.protocolVersion,
        pairingState: pairingState ?? this.pairingState,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'platform': platform,
        'ip': ip,
        'tcpPort': tcpPort,
        'webPort': webPort,
        'protocolVersion': protocolVersion,
        'pairingState': pairingState.name,
      };

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        id: json['id'] as String,
        name: json['name'] as String,
        platform: json['platform'] as String,
        ip: json['ip'] as String,
        tcpPort: json['tcpPort'] as int,
        webPort: json['webPort'] as int,
        protocolVersion: json['protocolVersion'] as int,
        pairingState: PairingState.values.byName(
            json['pairingState'] as String? ?? 'discovered'),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Device && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Device($name, $platform, $ip:$tcpPort, $pairingState)';
}
