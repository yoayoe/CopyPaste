import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:nsd/nsd.dart';
import '../../models/device.dart';
import '../../utils/constants.dart';
import '../../utils/logger.dart';

const _tag = 'Discovery';

Uint8List _encode(String s) => Uint8List.fromList(utf8.encode(s));
String _decode(Uint8List? b) => b != null ? utf8.decode(b) : '';

/// Handles mDNS service advertisement and browsing for desktop devices.
class DiscoveryService {
  Registration? _registration;
  Discovery? _discovery;

  final void Function(Device device)? onDeviceFound;
  final void Function(String deviceId)? onDeviceLost;

  DiscoveryService({this.onDeviceFound, this.onDeviceLost});

  /// Advertise this device on the local network via mDNS.
  Future<void> advertise({
    required String deviceId,
    required String deviceName,
    required int tcpPort,
    required int webPort,
  }) async {
    final platform = Platform.operatingSystem;

    final service = Service(
      name: deviceName,
      type: kServiceType,
      port: tcpPort,
      txt: {
        'id': _encode(deviceId),
        'name': _encode(deviceName),
        'platform': _encode(platform),
        'version': _encode(kProtocolVersion.toString()),
        'web_port': _encode(webPort.toString()),
      },
    );

    _registration = await register(service);
    Log.i(_tag, 'Advertising: $deviceName on port $tcpPort (web: $webPort)');
  }

  /// Browse for other CopyPaste devices on the local network.
  Future<void> startBrowsing(String selfId) async {
    _discovery = await startDiscovery(kServiceType);
    _discovery!.addServiceListener((service, status) {
      _handleServiceUpdate(service, status, selfId);
    });
    Log.i(_tag, 'Browsing for devices...');
  }

  void _handleServiceUpdate(
    Service service,
    ServiceStatus status,
    String selfId,
  ) {
    final txt = service.txt ?? {};
    final id = _decode(txt['id']);

    // Ignore our own service.
    if (id == selfId || id.isEmpty) return;

    if (status == ServiceStatus.found) {
      final host = service.addresses?.firstOrNull?.address;
      if (host == null) {
        Log.w(_tag, 'Found service without address: ${service.name}');
        return;
      }

      final device = Device(
        id: id,
        name: _decode(txt['name']).isNotEmpty
            ? _decode(txt['name'])
            : service.name ?? 'Unknown',
        platform: _decode(txt['platform']),
        ip: host,
        tcpPort: service.port ?? 0,
        webPort: int.tryParse(_decode(txt['web_port'])) ?? 0,
        protocolVersion: int.tryParse(_decode(txt['version'])) ?? 1,
      );

      Log.i(_tag, 'Found: $device');
      onDeviceFound?.call(device);
    } else if (status == ServiceStatus.lost) {
      Log.i(_tag, 'Lost: $id');
      onDeviceLost?.call(id);
    }
  }

  /// Stop advertising and browsing.
  Future<void> dispose() async {
    if (_registration != null) {
      await unregister(_registration!);
      _registration = null;
    }
    if (_discovery != null) {
      await stopDiscovery(_discovery!);
      _discovery = null;
    }
    Log.i(_tag, 'Stopped');
  }
}
