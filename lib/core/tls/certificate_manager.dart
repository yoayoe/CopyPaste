import 'dart:convert';
import 'dart:io';
import '../../utils/logger.dart';

const _tag = 'CertManager';

/// Manages self-signed TLS certificates for the embedded web server.
///
/// Generates certificates using the system's openssl CLI tool.
/// Certificates are stored in the app's support directory and reused
/// across restarts. Regenerated when expired or when the local IP changes.
class CertificateManager {
  final String _storageDir;

  String get certPath => '$_storageDir/cert.pem';
  String get keyPath => '$_storageDir/key.pem';
  String get _metaPath => '$_storageDir/cert_meta.json';

  CertificateManager({required String storageDir}) : _storageDir = storageDir;

  /// Ensure a valid certificate exists. Returns true if ready, false if
  /// TLS cannot be used (e.g. openssl not available).
  Future<bool> ensureCertificate({required String localIp}) async {
    await Directory(_storageDir).create(recursive: true);

    // Check existing cert validity.
    if (await _isValid(localIp)) {
      Log.i(_tag, 'Existing certificate is valid');
      return true;
    }

    // Generate new certificate.
    Log.i(_tag, 'Generating new self-signed certificate for $localIp');
    return _generate(localIp);
  }

  /// Check if the existing certificate is still valid.
  Future<bool> _isValid(String localIp) async {
    final certFile = File(certPath);
    final keyFile = File(keyPath);
    final metaFile = File(_metaPath);

    if (!await certFile.exists() ||
        !await keyFile.exists() ||
        !await metaFile.exists()) {
      return false;
    }

    try {
      final meta = jsonDecode(await metaFile.readAsString());
      final createdAt = DateTime.parse(meta['createdAt'] as String);
      final certIp = meta['ip'] as String?;

      // Regenerate if IP changed or cert is older than 365 days.
      final age = DateTime.now().difference(createdAt);
      if (age.inDays > 350) {
        Log.i(_tag, 'Certificate nearing expiry (${age.inDays} days old)');
        return false;
      }
      if (certIp != localIp) {
        Log.i(_tag, 'IP changed ($certIp → $localIp), regenerating');
        return false;
      }

      return true;
    } catch (e) {
      Log.w(_tag, 'Failed to read cert metadata: $e');
      return false;
    }
  }

  /// Generate a new self-signed certificate using openssl.
  Future<bool> _generate(String localIp) async {
    final openssl = await _findOpenssl();
    if (openssl == null) {
      Log.w(_tag, 'openssl not found — TLS unavailable');
      return false;
    }

    Log.i(_tag, 'Using openssl: $openssl');

    try {
      // Write a temp config file for SAN (Windows openssl doesn't support -addext).
      final confPath = '$_storageDir/openssl.cnf';
      await File(confPath).writeAsString('''
[req]
default_bits = 2048
prompt = no
distinguished_name = dn
x509_extensions = v3_ext

[dn]
CN = CopyPaste Local

[v3_ext]
subjectAltName = IP:$localIp,IP:127.0.0.1
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
''');

      final result = await Process.run(openssl, [
        'req',
        '-x509',
        '-newkey', 'rsa:2048',
        '-keyout', keyPath,
        '-out', certPath,
        '-days', '365',
        '-nodes',
        '-config', confPath,
      ]);

      // Clean up temp config.
      try { await File(confPath).delete(); } catch (_) {}

      if (result.exitCode != 0) {
        Log.e(_tag, 'openssl failed: ${result.stderr}');
        return false;
      }

      // Save metadata.
      await File(_metaPath).writeAsString(jsonEncode({
        'createdAt': DateTime.now().toIso8601String(),
        'ip': localIp,
      }));

      Log.i(_tag, 'Certificate generated successfully');
      return true;
    } catch (e) {
      Log.e(_tag, 'Certificate generation failed', e);
      return false;
    }
  }

  /// Find the openssl executable. Checks PATH first, then common locations on Windows.
  Future<String?> _findOpenssl() async {
    // Try PATH first.
    if (await _tryOpenssl('openssl')) return 'openssl';

    // On Windows, check common installation paths.
    if (Platform.isWindows) {
      final candidates = [
        r'C:\Program Files\Git\usr\bin\openssl.exe',
        r'C:\Program Files\Git\mingw64\bin\openssl.exe',
        r'C:\Program Files (x86)\Git\usr\bin\openssl.exe',
        r'C:\msys64\usr\bin\openssl.exe',
        r'C:\tools\openssl\openssl.exe',
        r'C:\OpenSSL-Win64\bin\openssl.exe',
        r'C:\OpenSSL-Win32\bin\openssl.exe',
      ];
      for (final path in candidates) {
        if (await File(path).exists() && await _tryOpenssl(path)) {
          return path;
        }
      }
    }

    return null;
  }

  /// Test if an openssl executable works.
  Future<bool> _tryOpenssl(String path) async {
    try {
      final result = await Process.run(path, ['version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Create a SecurityContext from the stored certificate and key.
  /// Returns null if files don't exist.
  SecurityContext? createSecurityContext() {
    final certFile = File(certPath);
    final keyFile = File(keyPath);

    if (!certFile.existsSync() || !keyFile.existsSync()) {
      return null;
    }

    try {
      final context = SecurityContext();
      context.useCertificateChain(certPath);
      context.usePrivateKey(keyPath);
      return context;
    } catch (e) {
      Log.e(_tag, 'Failed to create SecurityContext', e);
      return null;
    }
  }

  /// Delete stored certificates (for cleanup or reset).
  Future<void> deleteCertificates() async {
    for (final path in [certPath, keyPath, _metaPath]) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    Log.i(_tag, 'Certificates deleted');
  }
}
