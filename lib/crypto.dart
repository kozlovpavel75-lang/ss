import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ─────────────────────────────────────────────
// AES-256-CBC ШИФРУВАННЯ
//
// Принцип роботи:
// 1. При першому запуску генерується випадковий
//    256-бітний ключ і зберігається у
//    flutter_secure_storage (Android Keystore /
//    iOS Keychain) — недоступний без розблокування
// 2. Кожен рядок шифрується окремо з унікальним IV
// 3. Результат = base64(IV + ciphertext)
//
// Без доступу до пристрою — дані нечитабельні.
// ─────────────────────────────────────────────

class CryptoHelper {
  static final CryptoHelper instance = CryptoHelper._internal();
  CryptoHelper._internal();

  static const _storage    = FlutterSecureStorage();
  static const _keyAlias   = 'ukr_osint_aes_key_v1';

  // Кеш ключа в пам'яті (щоб не читати Keystore при кожній операції)
  Uint8List? _keyCache;

  // ── Ініціалізація ────────────────────────────
  Future<void> init() async {
    _keyCache = await _loadOrCreateKey();
  }

  Future<Uint8List> _loadOrCreateKey() async {
    final existing = await _storage.read(key: _keyAlias);
    if (existing != null) {
      return base64.decode(existing);
    }
    // Генеруємо новий 256-бітний ключ
    final key = _randomBytes(32);
    await _storage.write(key: _keyAlias, value: base64.encode(key));
    return key;
  }

  Uint8List _randomBytes(int length) {
    final rng   = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return bytes;
  }

  // ── Шифрування ───────────────────────────────
  Future<String> encrypt(String plaintext) async {
    if (plaintext.isEmpty) return plaintext;
    final key = _keyCache ?? await _loadOrCreateKey();
    final iv  = _randomBytes(16);

    final ptBytes = utf8.encode(plaintext);
    final padded  = _pkcs7Pad(ptBytes, 16);
    final cipher  = _aesCbcEncrypt(key, iv, padded);

    // Результат: base64( IV(16) + ciphertext )
    final combined = Uint8List(16 + cipher.length);
    combined.setRange(0,  16,             iv);
    combined.setRange(16, 16 + cipher.length, cipher);
    return base64.encode(combined);
  }

  // ── Дешифрування ─────────────────────────────
  Future<String> decrypt(String ciphertext) async {
    if (ciphertext.isEmpty) return ciphertext;
    // Якщо рядок не є base64 — повертаємо як є
    // (для сумісності зі старими незашифрованими даними)
    try {
      final key      = _keyCache ?? await _loadOrCreateKey();
      final combined = base64.decode(ciphertext);
      if (combined.length < 17) return ciphertext; // занадто короткий
      final iv         = combined.sublist(0,  16);
      final ctBytes    = combined.sublist(16);
      final decrypted  = _aesCbcDecrypt(key, iv, ctBytes);
      final unpadded   = _pkcs7Unpad(decrypted);
      return utf8.decode(unpadded);
    } catch (_) {
      // Якщо не вдалося розшифрувати — повертаємо як є
      // Це дозволяє безболісно відкрити базу після міграції
      return ciphertext;
    }
  }

  // ── Зручні методи для nullable ───────────────
  Future<String?> encryptNullable(String? value) async {
    if (value == null) return null;
    return encrypt(value);
  }

  Future<String?> decryptNullable(String? value) async {
    if (value == null) return null;
    return decrypt(value);
  }

  // ════════════════════════════════════════════
  // AES-CBC РЕАЛІЗАЦІЯ (без зовнішніх пакетів)
  // ════════════════════════════════════════════

  // S-Box таблиця AES
  static const List<int> _sbox = [
    0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
    0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
    0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
    0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
    0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
    0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
    0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
    0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
    0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
    0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
    0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
    0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
    0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
    0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
    0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
    0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16,
  ];

  // Inverse S-Box
  static const List<int> _rsbox = [
    0x52,0x09,0x6a,0xd5,0x30,0x36,0xa5,0x38,0xbf,0x40,0xa3,0x9e,0x81,0xf3,0xd7,0xfb,
    0x7c,0xe3,0x39,0x82,0x9b,0x2f,0xff,0x87,0x34,0x8e,0x43,0x44,0xc4,0xde,0xe9,0xcb,
    0x54,0x7b,0x94,0x32,0xa6,0xc2,0x23,0x3d,0xee,0x4c,0x95,0x0b,0x42,0xfa,0xc3,0x4e,
    0x08,0x2e,0xa1,0x66,0x28,0xd9,0x24,0xb2,0x76,0x5b,0xa2,0x49,0x6d,0x8b,0xd1,0x25,
    0x72,0xf8,0xf6,0x64,0x86,0x68,0x98,0x16,0xd4,0xa4,0x5c,0xcc,0x5d,0x65,0xb6,0x92,
    0x6c,0x70,0x48,0x50,0xfd,0xed,0xb9,0xda,0x5e,0x15,0x46,0x57,0xa7,0x8d,0x9d,0x84,
    0x90,0xd8,0xab,0x00,0x8c,0xbc,0xd3,0x0a,0xf7,0xe4,0x58,0x05,0xb8,0xb3,0x45,0x06,
    0xd0,0x2c,0x1e,0x8f,0xca,0x3f,0x0f,0x02,0xc1,0xaf,0xbd,0x03,0x01,0x13,0x8a,0x6b,
    0x3a,0x91,0x11,0x41,0x4f,0x67,0xdc,0xea,0x97,0xf2,0xcf,0xce,0xf0,0xb4,0xe6,0x73,
    0x96,0xac,0x74,0x22,0xe7,0xad,0x35,0x85,0xe2,0xf9,0x37,0xe8,0x1c,0x75,0xdf,0x6e,
    0x47,0xf1,0x1a,0x71,0x1d,0x29,0xc5,0x89,0x6f,0xb7,0x62,0x0e,0xaa,0x18,0xbe,0x1b,
    0xfc,0x56,0x3e,0x4b,0xc6,0xd2,0x79,0x20,0x9a,0xdb,0xc0,0xfe,0x78,0xcd,0x5a,0xf4,
    0x1f,0xdd,0xa8,0x33,0x88,0x07,0xc7,0x31,0xb1,0x12,0x10,0x59,0x27,0x80,0xec,0x5f,
    0x60,0x51,0x7f,0xa9,0x19,0xb5,0x4a,0x0d,0x2d,0xe5,0x7a,0x9f,0x93,0xc9,0x9c,0xef,
    0xa0,0xe0,0x3b,0x4d,0xae,0x2a,0xf5,0xb0,0xc8,0xeb,0xbb,0x3c,0x83,0x53,0x99,0x61,
    0x17,0x2b,0x04,0x7e,0xba,0x77,0xd6,0x26,0xe1,0x69,0x14,0x63,0x55,0x21,0x0c,0x7d,
  ];

  static const List<int> _rcon = [
    0x00,0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36,
  ];

  // GF(2^8) множення
  static int _xtime(int a) => ((a << 1) ^ ((a & 0x80) != 0 ? 0x1b : 0)) & 0xff;

  static int _mul(int a, int b) {
    int p = 0;
    for (int i = 0; i < 8; i++) {
      if ((b & 1) != 0) p ^= a;
      bool hiBitSet = (a & 0x80) != 0;
      a = (a << 1) & 0xff;
      if (hiBitSet) a ^= 0x1b;
      b >>= 1;
    }
    return p;
  }

  // Key expansion для AES-256 (14 раундів)
  static List<List<int>> _keyExpansion(Uint8List key) {
    const nk = 8; // 256-bit key = 8 words
    const nr = 14;
    final w = List<List<int>>.generate((nr + 1) * 4, (_) => List<int>.filled(4, 0));

    for (int i = 0; i < nk; i++) {
      w[i] = [key[4*i], key[4*i+1], key[4*i+2], key[4*i+3]];
    }
    for (int i = nk; i < (nr + 1) * 4; i++) {
      var temp = List<int>.from(w[i - 1]);
      if (i % nk == 0) {
        // RotWord + SubWord + Rcon
        final t = temp[0];
        temp[0] = _sbox[temp[1]] ^ _rcon[i ~/ nk];
        temp[1] = _sbox[temp[2]];
        temp[2] = _sbox[temp[3]];
        temp[3] = _sbox[t];
      } else if (nk > 6 && i % nk == 4) {
        temp = [_sbox[temp[0]], _sbox[temp[1]], _sbox[temp[2]], _sbox[temp[3]]];
      }
      for (int j = 0; j < 4; j++) w[i][j] = w[i - nk][j] ^ temp[j];
    }
    return w;
  }

  // AddRoundKey
  static void _addRoundKey(List<List<int>> state, List<List<int>> w, int round) {
    for (int c = 0; c < 4; c++) {
      for (int r = 0; r < 4; r++) {
        state[r][c] ^= w[round * 4 + c][r];
      }
    }
  }

  // SubBytes
  static void _subBytes(List<List<int>> state) {
    for (int r = 0; r < 4; r++) for (int c = 0; c < 4; c++) state[r][c] = _sbox[state[r][c]];
  }

  // ShiftRows
  static void _shiftRows(List<List<int>> state) {
    for (int r = 1; r < 4; r++) {
      final row = List<int>.from(state[r]);
      for (int c = 0; c < 4; c++) state[r][c] = row[(c + r) % 4];
    }
  }

  // MixColumns
  static void _mixColumns(List<List<int>> state) {
    for (int c = 0; c < 4; c++) {
      final s = [state[0][c], state[1][c], state[2][c], state[3][c]];
      state[0][c] = _mul(0x02, s[0]) ^ _mul(0x03, s[1]) ^ s[2] ^ s[3];
      state[1][c] = s[0] ^ _mul(0x02, s[1]) ^ _mul(0x03, s[2]) ^ s[3];
      state[2][c] = s[0] ^ s[1] ^ _mul(0x02, s[2]) ^ _mul(0x03, s[3]);
      state[3][c] = _mul(0x03, s[0]) ^ s[1] ^ s[2] ^ _mul(0x02, s[3]);
    }
  }

  // InvSubBytes
  static void _invSubBytes(List<List<int>> state) {
    for (int r = 0; r < 4; r++) for (int c = 0; c < 4; c++) state[r][c] = _rsbox[state[r][c]];
  }

  // InvShiftRows
  static void _invShiftRows(List<List<int>> state) {
    for (int r = 1; r < 4; r++) {
      final row = List<int>.from(state[r]);
      for (int c = 0; c < 4; c++) state[r][c] = row[(c - r + 4) % 4];
    }
  }

  // InvMixColumns
  static void _invMixColumns(List<List<int>> state) {
    for (int c = 0; c < 4; c++) {
      final s = [state[0][c], state[1][c], state[2][c], state[3][c]];
      state[0][c] = _mul(0x0e, s[0]) ^ _mul(0x0b, s[1]) ^ _mul(0x0d, s[2]) ^ _mul(0x09, s[3]);
      state[1][c] = _mul(0x09, s[0]) ^ _mul(0x0e, s[1]) ^ _mul(0x0b, s[2]) ^ _mul(0x0d, s[3]);
      state[2][c] = _mul(0x0d, s[0]) ^ _mul(0x09, s[1]) ^ _mul(0x0e, s[2]) ^ _mul(0x0b, s[3]);
      state[3][c] = _mul(0x0b, s[0]) ^ _mul(0x0d, s[1]) ^ _mul(0x09, s[2]) ^ _mul(0x0e, s[3]);
    }
  }

  // Шифрування одного 16-байтного блоку
  static Uint8List _aesEncryptBlock(Uint8List block, List<List<int>> w) {
    const nr = 14;
    // Формуємо state[row][col]
    final state = List.generate(4, (r) => List.generate(4, (c) => block[r + 4 * c]));
    _addRoundKey(state, w, 0);
    for (int round = 1; round < nr; round++) {
      _subBytes(state);
      _shiftRows(state);
      _mixColumns(state);
      _addRoundKey(state, w, round);
    }
    _subBytes(state);
    _shiftRows(state);
    _addRoundKey(state, w, nr);
    final out = Uint8List(16);
    for (int r = 0; r < 4; r++) for (int c = 0; c < 4; c++) out[r + 4 * c] = state[r][c];
    return out;
  }

  // Дешифрування одного блоку
  static Uint8List _aesDecryptBlock(Uint8List block, List<List<int>> w) {
    const nr = 14;
    final state = List.generate(4, (r) => List.generate(4, (c) => block[r + 4 * c]));
    _addRoundKey(state, w, nr);
    for (int round = nr - 1; round >= 1; round--) {
      _invShiftRows(state);
      _invSubBytes(state);
      _addRoundKey(state, w, round);
      _invMixColumns(state);
    }
    _invShiftRows(state);
    _invSubBytes(state);
    _addRoundKey(state, w, 0);
    final out = Uint8List(16);
    for (int r = 0; r < 4; r++) for (int c = 0; c < 4; c++) out[r + 4 * c] = state[r][c];
    return out;
  }

  // CBC шифрування
  static Uint8List _aesCbcEncrypt(Uint8List key, Uint8List iv, Uint8List data) {
    final w      = _keyExpansion(key);
    final result = Uint8List(data.length);
    var   prev   = iv;
    for (int i = 0; i < data.length; i += 16) {
      final block = Uint8List(16);
      for (int j = 0; j < 16; j++) block[j] = data[i + j] ^ prev[j];
      final enc = _aesEncryptBlock(block, w);
      result.setRange(i, i + 16, enc);
      prev = enc;
    }
    return result;
  }

  // CBC дешифрування
  static Uint8List _aesCbcDecrypt(Uint8List key, Uint8List iv, Uint8List data) {
    final w      = _keyExpansion(key);
    final result = Uint8List(data.length);
    var   prev   = iv;
    for (int i = 0; i < data.length; i += 16) {
      final block = data.sublist(i, i + 16);
      final dec   = _aesDecryptBlock(block, w);
      for (int j = 0; j < 16; j++) result[i + j] = dec[j] ^ prev[j];
      prev = block;
    }
    return result;
  }

  // PKCS#7 padding
  static Uint8List _pkcs7Pad(List<int> data, int blockSize) {
    final pad    = blockSize - (data.length % blockSize);
    final result = Uint8List(data.length + pad);
    result.setRange(0, data.length, data);
    for (int i = data.length; i < result.length; i++) result[i] = pad;
    return result;
  }

  static Uint8List _pkcs7Unpad(Uint8List data) {
    if (data.isEmpty) return data;
    final pad = data.last;
    if (pad < 1 || pad > 16) return data;
    return data.sublist(0, data.length - pad);
  }
}
