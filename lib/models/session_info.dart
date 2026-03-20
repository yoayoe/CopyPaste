/// Metadata for a mobile web client session.
class SessionInfo {
  final String token;
  final String clientName;
  final String clientIp;
  final DateTime createdAt;
  DateTime lastSeenAt;

  SessionInfo({
    required this.token,
    required this.clientName,
    required this.clientIp,
    required this.createdAt,
    DateTime? lastSeenAt,
  }) : lastSeenAt = lastSeenAt ?? createdAt;

  bool isExpired(Duration maxAge) =>
      DateTime.now().difference(createdAt) > maxAge;

  /// Truncated token for display (first 8 chars).
  String get displayToken => token.length > 8 ? '${token.substring(0, 8)}...' : token;
}
