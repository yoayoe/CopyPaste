import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Info about a connected mobile web client.
class WebClientState {
  final String name;
  final String ip;
  final String? sessionToken;
  final DateTime? connectedAt;
  final DateTime? lastSeenAt;

  const WebClientState({
    required this.name,
    required this.ip,
    this.sessionToken,
    this.connectedAt,
    this.lastSeenAt,
  });
}

/// Tracks connected mobile web clients.
final webClientsProvider =
    StateProvider<List<WebClientState>>((ref) => []);
