/// Utility for calculating SMS character segments (GSM-7 vs Unicode / Tamil)
/// and masking mobile numbers for privacy protection.

class SmsCalculationResult {
  final String encoding; // 'GSM-7' or 'Unicode (UCS-2)'
  final bool isUnicode;
  final int charCount;
  final int segments;
  final int remainingInSegment;
  final int segmentLimit;

  const SmsCalculationResult({
    required this.encoding,
    required this.isUnicode,
    required this.charCount,
    required this.segments,
    required this.remainingInSegment,
    required this.segmentLimit,
  });

  int totalSms(int recipientCount) => recipientCount * segments;
}

class SmsCalculator {
  // Standard GSM-7 7-bit character set (including basic Greek and extension chars)
  static const String _gsm7BasicChars =
      '@£\$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ '
      '!"#¤%&\'()*+,-./0123456789:;<=>?'
      '¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§'
      '¿abcdefghijklmnopqrstuvwxyzäöñüà'
      '^{}\\[~]|€';

  /// Calculate SMS segment count and encoding.
  /// GSM-7:
  ///   - 1 segment: up to 160 characters
  ///   - 2+ segments: 153 characters per segment
  /// Unicode (UCS-2 / Tamil / Emojis):
  ///   - 1 segment: up to 70 characters
  ///   - 2+ segments: 67 characters per segment
  static SmsCalculationResult calculate(String text) {
    if (text.isEmpty) {
      return const SmsCalculationResult(
        encoding: 'GSM-7',
        isUnicode: false,
        charCount: 0,
        segments: 0,
        remainingInSegment: 160,
        segmentLimit: 160,
      );
    }

    final runes = text.runes.toList();
    final length = runes.length;

    // Check if any character falls outside the standard GSM-7 basic & extension set
    bool isUnicode = false;
    for (final rune in runes) {
      final char = String.fromCharCode(rune);
      if (!_gsm7BasicChars.contains(char)) {
        isUnicode = true;
        break;
      }
    }

    if (isUnicode) {
      // Unicode / Tamil: 70 chars for single segment, 67 for concatenated
      final int segments;
      final int remaining;
      if (length <= 70) {
        segments = 1;
        remaining = 70 - length;
      } else {
        segments = ((length - 1) ~/ 67) + 1;
        remaining = (segments * 67) - length;
      }
      return SmsCalculationResult(
        encoding: 'Unicode (UCS-2)',
        isUnicode: true,
        charCount: length,
        segments: segments,
        remainingInSegment: remaining,
        segmentLimit: segments == 1 ? 70 : 67,
      );
    } else {
      // Standard GSM-7: 160 chars for single segment, 153 for concatenated
      final int segments;
      final int remaining;
      if (length <= 160) {
        segments = 1;
        remaining = 160 - length;
      } else {
        segments = ((length - 1) ~/ 153) + 1;
        remaining = (segments * 153) - length;
      }
      return SmsCalculationResult(
        encoding: 'GSM-7',
        isUnicode: false,
        charCount: length,
        segments: segments,
        remainingInSegment: remaining,
        segmentLimit: segments == 1 ? 160 : 153,
      );
    }
  }

  /// Mask mobile number so full phone numbers are not exposed unnecessarily:
  /// e.g. "9876543210" -> "+91 98*** **210"
  static String maskPhone(String phone) {
    if (phone.isEmpty) return 'N/A';
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    if (clean.length >= 10) {
      final last10 = clean.substring(clean.length - 10);
      return '+91 ${last10.substring(0, 2)}*** **${last10.substring(7)}';
    } else if (clean.length > 4) {
      return '${clean.substring(0, 2)}***${clean.substring(clean.length - 2)}';
    }
    return '***';
  }
}
