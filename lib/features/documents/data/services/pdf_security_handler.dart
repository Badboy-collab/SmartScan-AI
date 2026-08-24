import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pdf/pdf.dart';
// ignore: implementation_imports — PdfNum/PdfString/PdfObjectBase are not
// re-exported publicly by package:pdf, so internal imports are required.
import 'package:pdf/src/pdf/format/num.dart';
import 'package:pdf/src/pdf/format/object_base.dart';
import 'package:pdf/src/pdf/format/string.dart';

/// PDF "Standard" security handler (Revision 2, V2, 40-bit RC4).
///
/// The `pdf` package exposes the encryption hook ([PdfEncryption]) but ships
/// no concrete handler, so we implement the classic PDF 1.4 RC4 security
/// handler here. Readers (Acrobat, Chrome, Android PdfRenderer, ...) support
/// it. Note: RC4-40 is cryptographically weak; it only protects casual
/// viewing, not serious confidentiality.
class PdfStandardSecurityHandler extends PdfEncryption {
  static const List<int> _padding = [
    0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, 0x64, 0x00, 0x4E, 0x56,
    0xFF, 0xFA, 0x01, 0x08, 0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
    0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
  ];

  final Uint8List _key;
  final int _keyLen;

  PdfStandardSecurityHandler(
    PdfDocument pdfDocument, {
    required String userPassword,
    required String ownerPassword,
  })  : _keyLen = 5,
        _key = _computeKey(pdfDocument, userPassword, ownerPassword),
        super(pdfDocument) {
    final ownerPad = _pad(ownerPassword);
    final oKey = md5.convert(ownerPad).bytes.sublist(0, _keyLen);
    final oBytes = _rc4(Uint8List.fromList(oKey), _pad(userPassword));

    final uBytes = _rc4(_key, Uint8List.fromList(_padding));

    // Permissions: allow printing / copying / modifying (-4 = 0xFFFFFFFC).
    const p = -4;

    params['/Filter'] = PdfName('Standard');
    params['/V'] = PdfNum(2);
    params['/R'] = PdfNum(2);
    params['/O'] = PdfString(
      Uint8List.fromList(oBytes),
      format: PdfStringFormat.binary,
      encrypted: false,
    );
    params['/U'] = PdfString(
      uBytes,
      format: PdfStringFormat.binary,
      encrypted: false,
    );
    params['/P'] = PdfNum(p);
    params['/Length'] = PdfNum(40);
  }

  /// Computes the 40-bit (5 byte) file encryption key (PDF spec 7.6.3.3).
  static Uint8List _computeKey(
    PdfDocument pdfDocument,
    String userPassword,
    String ownerPassword,
  ) {
    final ownerPad = _pad(ownerPassword);
    final oKey = md5.convert(ownerPad).bytes.sublist(0, 5);
    final oBytes = _rc4(Uint8List.fromList(oKey), _pad(userPassword));

    const p = -4;
    final pBytes = <int>[
      p & 0xFF,
      (p >> 8) & 0xFF,
      (p >> 16) & 0xFF,
      (p >> 24) & 0xFF,
    ];

    final id = pdfDocument.documentID;
    final hash = md5.convert([
      ..._pad(userPassword),
      ...oBytes,
      ...pBytes,
      ...id,
    ]).bytes;

    return Uint8List.fromList(hash.sublist(0, 5));
  }

  static Uint8List _pad(String password) {
    final bytes = Uint8List(32);
    bytes.setAll(0, password.codeUnits.take(32));
    for (var i = password.codeUnits.length; i < 32; i++) {
      bytes[i] = _padding[i];
    }
    return bytes;
  }

  @override
  Uint8List encrypt(Uint8List input, PdfObjectBase object) {
    final key = Uint8List(_keyLen + 5);
    key.setAll(0, _key);

    final objser = object.objser;
    final objgen = object.objgen;
    key[_keyLen] = objser & 0xFF;
    key[_keyLen + 1] = (objser >> 8) & 0xFF;
    key[_keyLen + 2] = (objser >> 16) & 0xFF;
    key[_keyLen + 3] = objgen & 0xFF;
    key[_keyLen + 4] = (objgen >> 8) & 0xFF;

    final objKey = md5.convert(key).bytes.sublist(0, _keyLen);
    return _rc4(Uint8List.fromList(objKey), input);
  }

  static Uint8List _rc4(Uint8List key, Uint8List data) {
    final s = List<int>.generate(256, (i) => i);
    var j = 0;
    for (var i = 0; i < 256; i++) {
      j = (j + s[i] + key[i % key.length]) % 256;
      final tmp = s[i];
      s[i] = s[j];
      s[j] = tmp;
    }

    final out = Uint8List(data.length);
    var i = 0;
    j = 0;
    for (var k = 0; k < data.length; k++) {
      i = (i + 1) % 256;
      j = (j + s[i]) % 256;
      final tmp = s[i];
      s[i] = s[j];
      s[j] = tmp;
      out[k] = data[k] ^ s[(s[i] + s[j]) % 256];
    }
    return out;
  }
}
