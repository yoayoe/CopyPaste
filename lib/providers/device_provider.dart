import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/device.dart';

/// Manages the list of discovered desktop devices.
class DeviceNotifier extends StateNotifier<List<Device>> {
  DeviceNotifier() : super([]);

  void addOrUpdate(Device device) {
    state = [
      ...state.where((d) => d.id != device.id),
      device,
    ];
  }

  void remove(String deviceId) {
    state = state.where((d) => d.id != deviceId).toList();
  }

  void clear() {
    state = [];
  }
}

final deviceProvider =
    StateNotifierProvider<DeviceNotifier, List<Device>>((ref) {
  return DeviceNotifier();
});
