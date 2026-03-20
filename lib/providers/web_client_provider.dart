import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Info about a connected mobile web client.
class WebClientState {
  final String name;
  final String ip;

  const WebClientState({required this.name, required this.ip});
}

/// Tracks connected mobile web clients.
final webClientsProvider =
    StateProvider<List<WebClientState>>((ref) => []);
