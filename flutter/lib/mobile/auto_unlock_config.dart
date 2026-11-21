import 'dart:convert';

import '../common.dart';
import '../consts.dart';
import '../models/platform_model.dart';

/// Local auto-unlock settings per peer. The Windows password is kept encrypted
/// with an Android Keystore key; plaintext entries from older builds are read
/// and migrated on first touch.
class AutoUnlockConfig {
  static String key(String peerId) => 'uu-auto-unlock:$peerId';

  static Map<String, dynamic> load(String peerId) {
    try {
      final raw = bind.mainGetLocalOption(key: key(peerId));
      if (raw.isEmpty) return {};
      final cfg = json.decode(raw);
      return cfg is Map ? Map<String, dynamic>.from(cfg) : {};
    } catch (_) {
      return {};
    }
  }

  static void save(String peerId, Map<String, dynamic> cfg) =>
      bind.mainSetLocalOption(key: key(peerId), value: json.encode(cfg));

  static Future<String?> encrypt(String plain) async {
    try {
      return await gFFI.invokeMethodWithResult<String>(
          AndroidChannel.kAutoUnlockEncrypt, plain);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> decrypt(String payload) async {
    try {
      return await gFFI.invokeMethodWithResult<String>(
          AndroidChannel.kAutoUnlockDecrypt, payload);
    } catch (_) {
      return null;
    }
  }

  static bool hasStoredPassword(Map<String, dynamic> cfg) {
    final enc = cfg['enc']?.toString() ?? '';
    final pwd = cfg['pwd']?.toString() ?? '';
    return enc.isNotEmpty || pwd.isNotEmpty;
  }

  /// Resolves the stored password; legacy plaintext entries still work.
  static Future<String?> password(Map<String, dynamic> cfg) async {
    final enc = cfg['enc']?.toString() ?? '';
    if (enc.isNotEmpty) {
      return decrypt(enc);
    }
    final pwd = cfg['pwd']?.toString() ?? '';
    return pwd.isEmpty ? null : pwd;
  }

  /// Moves a legacy plaintext password into Keystore storage. Returns false
  /// when there is nothing to migrate or the platform cannot encrypt.
  static Future<bool> migrate(String peerId, Map<String, dynamic> cfg) async {
    final pwd = cfg['pwd']?.toString() ?? '';
    if (pwd.isEmpty) return false;
    final enc = await encrypt(pwd);
    if (enc == null) return false;
    cfg['enc'] = enc;
    cfg.remove('pwd');
    save(peerId, cfg);
    return true;
  }
}