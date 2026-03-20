import 'dart:io';

/// Get the primary local IP address of this device.
Future<String> getLocalIpAddress() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );

  for (final interface in interfaces) {
    for (final addr in interface.addresses) {
      if (!addr.isLoopback && !addr.address.startsWith('169.254')) {
        return addr.address;
      }
    }
  }

  return '127.0.0.1';
}

/// Find an available port in the given range.
Future<int> findAvailablePort(int start, int end) async {
  for (var port = start; port <= end; port++) {
    try {
      final server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      await server.close();
      return port;
    } catch (_) {
      continue;
    }
  }
  // Fallback: let the OS pick a port.
  final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
  final port = server.port;
  await server.close();
  return port;
}
