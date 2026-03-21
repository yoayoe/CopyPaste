import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import '../../utils/logger.dart';

const _tag = 'CertManager';

/// Manages self-signed TLS certificates for the embedded web server.
///
/// Generates certificates in pure Dart using pointycastle — no external
/// tools (openssl) required. Works on all platforms including Windows.
class CertificateManager {
  final String _storageDir;

  String get certPath => '$_storageDir/cert.pem';
  String get keyPath => '$_storageDir/key.pem';
  String get _metaPath => '$_storageDir/cert_meta.json';

  CertificateManager({required String storageDir}) : _storageDir = storageDir;

  /// Ensure a valid certificate exists. Returns true if ready.
  Future<bool> ensureCertificate({required String localIp}) async {
    await Directory(_storageDir).create(recursive: true);

    if (await _isValid(localIp)) {
      Log.i(_tag, 'Existing certificate is valid');
      return true;
    }

    Log.i(_tag, 'Generating new self-signed certificate for $localIp');
    return _generate(localIp);
  }

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

  /// Generate a self-signed certificate in pure Dart.
  Future<bool> _generate(String localIp) async {
    try {
      // 1. Generate RSA-2048 key pair.
      final keyPair = _generateRsaKeyPair();
      final publicKey = keyPair.publicKey as RSAPublicKey;
      final privateKey = keyPair.privateKey as RSAPrivateKey;

      // 2. Build self-signed X.509 v3 certificate.
      final now = DateTime.now().toUtc();
      final notAfter = now.add(const Duration(days: 365));
      final serialNumber = _randomSerial();

      final tbsCert = _buildTbsCertificate(
        serialNumber: serialNumber,
        notBefore: now,
        notAfter: notAfter,
        publicKey: publicKey,
        localIp: localIp,
      );

      // 3. Sign TBSCertificate with SHA-256/RSA.
      final signature = _sign(tbsCert, privateKey);

      // 4. Wrap in Certificate SEQUENCE.
      final cert = _asn1Sequence([
        tbsCert,
        _signatureAlgorithm(),
        _asn1BitString(signature),
      ]);

      // 5. Write PEM files.
      await File(certPath).writeAsString(_toPem(cert, 'CERTIFICATE'));
      await File(keyPath).writeAsString(_toPem(
        _encodePrivateKey(privateKey), 'RSA PRIVATE KEY'));

      // 6. Save metadata.
      await File(_metaPath).writeAsString(jsonEncode({
        'createdAt': DateTime.now().toIso8601String(),
        'ip': localIp,
      }));

      Log.i(_tag, 'Certificate generated successfully (pure Dart)');
      return true;
    } catch (e) {
      Log.e(_tag, 'Certificate generation failed', e);
      return false;
    }
  }

  /// Create a SecurityContext from the stored certificate and key.
  SecurityContext? createSecurityContext() {
    final certFile = File(certPath);
    final keyFile = File(keyPath);

    if (!certFile.existsSync() || !keyFile.existsSync()) return null;

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

  /// Delete stored certificates.
  Future<void> deleteCertificates() async {
    for (final path in [certPath, keyPath, _metaPath]) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    Log.i(_tag, 'Certificates deleted');
  }

  // ---------------------------------------------------------------
  // RSA Key Generation
  // ---------------------------------------------------------------

  AsymmetricKeyPair<PublicKey, PrivateKey> _generateRsaKeyPair() {
    final secureRandom = FortunaRandom();
    final seedSource = Random.secure();
    final seeds = List<int>.generate(32, (_) => seedSource.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));

    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
        secureRandom,
      ));

    return keyGen.generateKeyPair();
  }

  BigInt _randomSerial() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[0] &= 0x7F; // Ensure positive.
    return BigInt.parse(
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(), radix: 16);
  }

  // ---------------------------------------------------------------
  // X.509 Certificate Building (ASN.1 DER)
  // ---------------------------------------------------------------

  Uint8List _buildTbsCertificate({
    required BigInt serialNumber,
    required DateTime notBefore,
    required DateTime notAfter,
    required RSAPublicKey publicKey,
    required String localIp,
  }) {
    return _asn1Sequence([
      // version [0] EXPLICIT INTEGER v3 (2)
      _asn1ContextTag(0, _asn1Integer(BigInt.two)),
      // serialNumber
      _asn1Integer(serialNumber),
      // signature algorithm
      _signatureAlgorithm(),
      // issuer: CN=CopyPaste Local
      _rdnSequence('CopyPaste Local'),
      // validity
      _asn1Sequence([
        _asn1UtcTime(notBefore),
        _asn1UtcTime(notAfter),
      ]),
      // subject (same as issuer for self-signed)
      _rdnSequence('CopyPaste Local'),
      // subjectPublicKeyInfo
      _subjectPublicKeyInfo(publicKey),
      // extensions [3]
      _asn1ContextTag(3, _extensions(localIp)),
    ]);
  }

  Uint8List _signatureAlgorithm() {
    // SHA256withRSA: 1.2.840.113549.1.1.11
    return _asn1Sequence([
      _asn1Oid([1, 2, 840, 113549, 1, 1, 11]),
      _asn1Null(),
    ]);
  }

  Uint8List _rdnSequence(String commonName) {
    return _asn1Sequence([
      _asn1Set([
        _asn1Sequence([
          _asn1Oid([2, 5, 4, 3]), // OID for commonName
          _asn1Utf8String(commonName),
        ]),
      ]),
    ]);
  }

  Uint8List _subjectPublicKeyInfo(RSAPublicKey key) {
    final pubKeyDer = _asn1Sequence([
      _asn1Integer(key.modulus!),
      _asn1Integer(key.exponent!),
    ]);

    return _asn1Sequence([
      _asn1Sequence([
        _asn1Oid([1, 2, 840, 113549, 1, 1, 1]), // rsaEncryption
        _asn1Null(),
      ]),
      _asn1BitString(pubKeyDer),
    ]);
  }

  Uint8List _extensions(String localIp) {
    return _asn1Sequence([
      // Basic Constraints: CA=FALSE
      _asn1Sequence([
        _asn1Oid([2, 5, 29, 19]),
        _asn1Boolean(true), // critical
        _asn1OctetString(_asn1Sequence([])), // empty = CA:FALSE
      ]),
      // Key Usage: digitalSignature, keyEncipherment
      _asn1Sequence([
        _asn1Oid([2, 5, 29, 15]),
        _asn1Boolean(true), // critical
        _asn1OctetString(
          _asn1BitStringRaw(Uint8List.fromList([0x05, 0xa0])),
        ),
      ]),
      // Subject Alternative Name: IP addresses
      _asn1Sequence([
        _asn1Oid([2, 5, 29, 17]),
        _asn1OctetString(_asn1Sequence([
          _sanIpAddress(localIp),
          _sanIpAddress('127.0.0.1'),
        ])),
      ]),
    ]);
  }

  Uint8List _sanIpAddress(String ip) {
    // Context tag [7] for iPAddress in GeneralName.
    final bytes = ip.split('.').map(int.parse).toList();
    return _asn1ContextImplicit(7, Uint8List.fromList(bytes));
  }

  // ---------------------------------------------------------------
  // Signing
  // ---------------------------------------------------------------

  Uint8List _sign(Uint8List data, RSAPrivateKey privateKey) {
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201');
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    final sig = signer.generateSignature(data);
    return sig.bytes;
  }

  // ---------------------------------------------------------------
  // Private Key Encoding (PKCS#1)
  // ---------------------------------------------------------------

  Uint8List _encodePrivateKey(RSAPrivateKey key) {
    return _asn1Sequence([
      _asn1Integer(BigInt.zero), // version
      _asn1Integer(key.modulus!),
      _asn1Integer(key.publicExponent!),
      _asn1Integer(key.privateExponent!),
      _asn1Integer(key.p!),
      _asn1Integer(key.q!),
      _asn1Integer(key.privateExponent! % (key.p! - BigInt.one)), // d mod (p-1)
      _asn1Integer(key.privateExponent! % (key.q! - BigInt.one)), // d mod (q-1)
      _asn1Integer(key.q!.modInverse(key.p!)), // q^-1 mod p
    ]);
  }

  // ---------------------------------------------------------------
  // ASN.1 DER Encoding Primitives
  // ---------------------------------------------------------------

  Uint8List _asn1Sequence(List<Uint8List> children) =>
      _asn1Constructed(0x30, children);

  Uint8List _asn1Set(List<Uint8List> children) =>
      _asn1Constructed(0x31, children);

  Uint8List _asn1Constructed(int tag, List<Uint8List> children) {
    final content = _concat(children);
    return _tlv(tag, content);
  }

  Uint8List _asn1Integer(BigInt value) {
    var bytes = _bigIntToBytes(value);
    // Ensure positive encoding (prepend 0x00 if high bit set).
    if (bytes.isNotEmpty && bytes[0] & 0x80 != 0) {
      bytes = Uint8List.fromList([0x00, ...bytes]);
    }
    return _tlv(0x02, bytes);
  }

  Uint8List _asn1BitString(Uint8List data) {
    // Prepend unused-bits byte (0).
    return _tlv(0x03, Uint8List.fromList([0x00, ...data]));
  }

  Uint8List _asn1BitStringRaw(Uint8List data) {
    return _tlv(0x03, data);
  }

  Uint8List _asn1OctetString(Uint8List data) => _tlv(0x04, data);

  Uint8List _asn1Null() => Uint8List.fromList([0x05, 0x00]);

  Uint8List _asn1Boolean(bool value) =>
      _tlv(0x01, Uint8List.fromList([value ? 0xFF : 0x00]));

  Uint8List _asn1Utf8String(String s) => _tlv(0x0C, Uint8List.fromList(utf8.encode(s)));

  Uint8List _asn1Oid(List<int> components) {
    final bytes = <int>[];
    bytes.add(components[0] * 40 + components[1]);
    for (var i = 2; i < components.length; i++) {
      _encodeOidComponent(bytes, components[i]);
    }
    return _tlv(0x06, Uint8List.fromList(bytes));
  }

  void _encodeOidComponent(List<int> bytes, int value) {
    if (value < 128) {
      bytes.add(value);
      return;
    }
    final parts = <int>[];
    var v = value;
    parts.add(v & 0x7F);
    v >>= 7;
    while (v > 0) {
      parts.add((v & 0x7F) | 0x80);
      v >>= 7;
    }
    bytes.addAll(parts.reversed);
  }

  Uint8List _asn1UtcTime(DateTime dt) {
    final s = '${_pad(dt.year % 100)}${_pad(dt.month)}${_pad(dt.day)}'
        '${_pad(dt.hour)}${_pad(dt.minute)}${_pad(dt.second)}Z';
    return _tlv(0x17, Uint8List.fromList(s.codeUnits));
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  Uint8List _asn1ContextTag(int tag, Uint8List content) =>
      _tlv(0xA0 | tag, content);

  Uint8List _asn1ContextImplicit(int tag, Uint8List content) =>
      _tlv(0x80 | tag, content);

  // ---------------------------------------------------------------
  // TLV and helpers
  // ---------------------------------------------------------------

  Uint8List _tlv(int tag, Uint8List value) {
    final len = _derLength(value.length);
    final result = Uint8List(1 + len.length + value.length);
    result[0] = tag;
    result.setRange(1, 1 + len.length, len);
    result.setRange(1 + len.length, result.length, value);
    return result;
  }

  Uint8List _derLength(int length) {
    if (length < 128) return Uint8List.fromList([length]);
    if (length < 256) return Uint8List.fromList([0x81, length]);
    if (length < 65536) {
      return Uint8List.fromList([0x82, (length >> 8) & 0xFF, length & 0xFF]);
    }
    return Uint8List.fromList([
      0x83,
      (length >> 16) & 0xFF,
      (length >> 8) & 0xFF,
      length & 0xFF,
    ]);
  }

  Uint8List _bigIntToBytes(BigInt value) {
    if (value == BigInt.zero) return Uint8List.fromList([0]);
    final hex = value.toRadixString(16);
    final padded = hex.length.isOdd ? '0$hex' : hex;
    final bytes = <int>[];
    for (var i = 0; i < padded.length; i += 2) {
      bytes.add(int.parse(padded.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  Uint8List _concat(List<Uint8List> parts) {
    final total = parts.fold<int>(0, (sum, p) => sum + p.length);
    final result = Uint8List(total);
    var offset = 0;
    for (final part in parts) {
      result.setRange(offset, offset + part.length, part);
      offset += part.length;
    }
    return result;
  }

  String _toPem(Uint8List der, String label) {
    final b64 = base64Encode(der);
    final lines = <String>['-----BEGIN $label-----'];
    for (var i = 0; i < b64.length; i += 64) {
      lines.add(b64.substring(i, i + 64 > b64.length ? b64.length : i + 64));
    }
    lines.add('-----END $label-----');
    lines.add('');
    return lines.join('\n');
  }
}
