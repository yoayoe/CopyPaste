/// mDNS service type for CopyPaste discovery.
const kServiceType = '_copypaste._tcp';

/// Protocol version for binary messages.
const kProtocolVersion = 2;

/// Magic bytes for binary protocol header (0x43 = 'C', 0x50 = 'P').
const kMagicByte1 = 0x43;
const kMagicByte2 = 0x50;

/// Chunk size for file transfer (64KB).
const kChunkSize = 64 * 1024;

/// Maximum clipboard history items.
const kMaxClipboardHistory = 50;

/// Web server default port range.
const kWebPortMin = 8080;
const kWebPortMax = 8099;

/// QR token expiry duration.
const kQrTokenExpiry = Duration(minutes: 5);

/// Session token default duration.
const kSessionDuration = Duration(hours: 24);

/// Clipboard polling interval (for platforms without native listener).
const kClipboardPollInterval = Duration(milliseconds: 500);
