enum TransferStatus { pending, inProgress, completed, failed, rejected }

enum TransferDirection { send, receive }

class TransferTask {
  final String id;
  final String filename;
  final String mimeType;
  final int totalBytes;
  final int transferredBytes;
  final TransferStatus status;
  final TransferDirection direction;
  final String deviceId;
  final String deviceName;
  final DateTime startedAt;
  final String? error;
  final String? filePath;

  const TransferTask({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.totalBytes,
    this.transferredBytes = 0,
    this.status = TransferStatus.pending,
    required this.direction,
    required this.deviceId,
    required this.deviceName,
    required this.startedAt,
    this.error,
    this.filePath,
  });

  double get progress =>
      totalBytes > 0 ? transferredBytes / totalBytes : 0.0;

  TransferTask copyWith({
    int? transferredBytes,
    TransferStatus? status,
    String? error,
    String? filePath,
  }) =>
      TransferTask(
        id: id,
        filename: filename,
        mimeType: mimeType,
        totalBytes: totalBytes,
        transferredBytes: transferredBytes ?? this.transferredBytes,
        status: status ?? this.status,
        direction: direction,
        deviceId: deviceId,
        deviceName: deviceName,
        startedAt: startedAt,
        error: error ?? this.error,
        filePath: filePath ?? this.filePath,
      );
}
