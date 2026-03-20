import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import '../core/network/peer_connection.dart';
import '../core/protocol/message.dart';
import '../models/transfer_task.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

const _tag = 'FileTransfer';

/// Incoming file reassembly state.
class _IncomingFile {
  final String id;
  final String filename;
  final int totalSize;
  final int totalChunks;
  final String expectedChecksum;
  final String senderId;
  final String senderName;
  final Map<int, Uint8List> chunks = {};
  int receivedBytes = 0;

  _IncomingFile({
    required this.id,
    required this.filename,
    required this.totalSize,
    required this.totalChunks,
    required this.expectedChecksum,
    required this.senderId,
    required this.senderName,
  });

  bool get isComplete => chunks.length == totalChunks;

  Uint8List reassemble() {
    final builder = BytesBuilder(copy: false);
    for (var i = 0; i < totalChunks; i++) {
      builder.add(chunks[i]!);
    }
    return builder.toBytes();
  }
}

/// Handles file transfer between paired desktops via TCP.
class FileTransferService {
  final String _downloadDir;
  final Map<String, _IncomingFile> _incoming = {};

  /// Called when transfer progress updates.
  void Function(TransferTask task)? onTransferProgress;

  /// Called when a file transfer completes (received).
  void Function(TransferTask task, String filePath)? onTransferComplete;

  /// Called when a file transfer fails.
  void Function(TransferTask task, String error)? onTransferFailed;

  FileTransferService({String? downloadDir})
      : _downloadDir = downloadDir ??
            '${Directory.systemTemp.path}/copypaste_files';

  Future<void> init() async {
    await Directory(_downloadDir).create(recursive: true);
  }

  /// Send a file to a paired peer in chunks.
  Future<TransferTask?> sendFile(
    String filePath,
    PeerConnection peer, {
    required String senderId,
    String? senderName,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      Log.e(_tag, 'File not found: $filePath');
      return null;
    }

    final stat = await file.stat();
    final filename = filePath.split(Platform.pathSeparator).last;
    final totalSize = stat.size;
    final transferId = const Uuid().v4();

    // Compute checksum.
    final bytes = await file.readAsBytes();
    final hash = await Sha256().hash(bytes);
    final checksum = base64Encode(hash.bytes);

    final totalChunks = (totalSize / kChunkSize).ceil();

    final task = TransferTask(
      id: transferId,
      filename: filename,
      mimeType: 'application/octet-stream',
      totalBytes: totalSize,
      status: TransferStatus.inProgress,
      direction: TransferDirection.send,
      deviceId: peer.deviceId,
      deviceName: peer.deviceName,
      startedAt: DateTime.now(),
    );
    onTransferProgress?.call(task);

    Log.i(_tag, 'Sending $filename ($totalSize bytes, $totalChunks chunks) to ${peer.deviceName}');

    for (var i = 0; i < totalChunks; i++) {
      final start = i * kChunkSize;
      final end = (start + kChunkSize > totalSize) ? totalSize : start + kChunkSize;
      final chunkData = Uint8List.fromList(bytes.sublist(start, end));

      final msg = Message.file(
        id: transferId,
        senderId: senderId,
        filename: filename,
        totalSize: totalSize,
        chunkIndex: i,
        totalChunks: totalChunks,
        checksum: checksum,
        chunkData: chunkData,
        senderName: senderName,
      );

      final sent = await peer.send(msg);
      if (!sent) {
        final failed = task.copyWith(status: TransferStatus.failed, error: 'Send failed');
        onTransferFailed?.call(failed, 'Connection lost');
        return failed;
      }

      final transferred = end;
      onTransferProgress?.call(task.copyWith(transferredBytes: transferred));
    }

    final completed = task.copyWith(
      transferredBytes: totalSize,
      status: TransferStatus.completed,
      filePath: filePath,
    );
    onTransferComplete?.call(completed, filePath);
    Log.i(_tag, 'Sent $filename to ${peer.deviceName}');
    return completed;
  }

  /// Handle incoming file chunk from a paired peer.
  Future<void> handleFileMessage(Message message) async {
    final meta = message.meta;
    final transferId = meta['id'] as String;
    final filename = meta['filename'] as String;
    final totalSize = meta['totalSize'] as int;
    final chunkIndex = meta['chunkIndex'] as int;
    final totalChunks = meta['totalChunks'] as int;
    final checksum = meta['checksum'] as String;
    final senderId = meta['sender'] as String? ?? 'unknown';
    final senderName = meta['senderName'] as String? ?? 'Unknown';

    // Get or create incoming file state.
    final incoming = _incoming.putIfAbsent(
      transferId,
      () => _IncomingFile(
        id: transferId,
        filename: filename,
        totalSize: totalSize,
        totalChunks: totalChunks,
        expectedChecksum: checksum,
        senderId: senderId,
        senderName: senderName,
      ),
    );

    incoming.chunks[chunkIndex] = message.payload;
    incoming.receivedBytes += message.payload.length;

    final task = TransferTask(
      id: transferId,
      filename: filename,
      mimeType: 'application/octet-stream',
      totalBytes: totalSize,
      transferredBytes: incoming.receivedBytes,
      status: TransferStatus.inProgress,
      direction: TransferDirection.receive,
      deviceId: senderId,
      deviceName: senderName,
      startedAt: DateTime.now(),
    );
    onTransferProgress?.call(task);

    Log.d(_tag, 'Chunk $chunkIndex/$totalChunks for $filename '
        '(${incoming.receivedBytes}/$totalSize)');

    if (incoming.isComplete) {
      await _finalizeFile(incoming);
    }
  }

  Future<void> _finalizeFile(_IncomingFile incoming) async {
    _incoming.remove(incoming.id);

    final data = incoming.reassemble();

    // Verify checksum.
    final hash = await Sha256().hash(data);
    final actualChecksum = base64Encode(hash.bytes);

    if (actualChecksum != incoming.expectedChecksum) {
      Log.e(_tag, 'Checksum mismatch for ${incoming.filename}');
      final task = TransferTask(
        id: incoming.id,
        filename: incoming.filename,
        mimeType: 'application/octet-stream',
        totalBytes: incoming.totalSize,
        transferredBytes: incoming.receivedBytes,
        status: TransferStatus.failed,
        direction: TransferDirection.receive,
        deviceId: incoming.senderId,
        deviceName: incoming.senderName,
        startedAt: DateTime.now(),
        error: 'Checksum mismatch',
      );
      onTransferFailed?.call(task, 'Checksum mismatch');
      return;
    }

    // Save file.
    final savePath = '$_downloadDir/${incoming.id}-${incoming.filename}';
    final file = File(savePath);
    await file.writeAsBytes(data);

    final task = TransferTask(
      id: incoming.id,
      filename: incoming.filename,
      mimeType: 'application/octet-stream',
      totalBytes: incoming.totalSize,
      transferredBytes: incoming.totalSize,
      status: TransferStatus.completed,
      direction: TransferDirection.receive,
      deviceId: incoming.senderId,
      deviceName: incoming.senderName,
      startedAt: DateTime.now(),
      filePath: savePath,
    );

    onTransferComplete?.call(task, savePath);
    Log.i(_tag, 'Received ${incoming.filename} (${incoming.totalSize} bytes, checksum OK)');
  }

  void dispose() {
    _incoming.clear();
  }
}
