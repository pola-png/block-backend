import 'dart:convert';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'appwrite_service.dart';

class ChatDeviceBundle {
  final String userId;
  final String deviceId;
  final SimplePublicKey identityPublicKey;
  final SimplePublicKey signingPublicKey;
  final SimplePublicKey signedPrekeyPublicKey;
  final List<int> signedPrekeySignature;
  final bool signatureValid;

  const ChatDeviceBundle({
    required this.userId,
    required this.deviceId,
    required this.identityPublicKey,
    required this.signingPublicKey,
    required this.signedPrekeyPublicKey,
    required this.signedPrekeySignature,
    required this.signatureValid,
  });
}

class ChatSecurityInfo {
  final bool deviceBundlePublished;
  final bool partnerBundleAvailable;
  final bool partnerBundleVerified;
  final bool sessionReady;
  final bool safetyNumberVerified;
  final String? deviceId;
  final String? partnerDeviceId;
  final String safetyNumber;

  const ChatSecurityInfo({
    required this.deviceBundlePublished,
    required this.partnerBundleAvailable,
    required this.partnerBundleVerified,
    required this.sessionReady,
    required this.safetyNumberVerified,
    required this.deviceId,
    required this.partnerDeviceId,
    required this.safetyNumber,
  });
}

/// Handles chat encryption with a stronger device-oriented E2EE scaffold:
/// - per-device X25519 identity key
/// - per-device Ed25519 signing key
/// - per-device signed X25519 prekey
/// - device registry publishing to Appwrite
/// - client-side session establishment via verified signed prekeys
/// - safety-number generation and local verification state
class CryptoService {
  static final _storage = const FlutterSecureStorage();

  static const int currentE2eeVersion = 2;
  static const String currentKeyAlgorithm = 'x25519';
  static const String currentSigningAlgorithm = 'ed25519';
  static const String currentCipherAlgorithm = 'aes-256-gcm';

  static const String _deviceIdKey = 'e2ee_device_id';
  static const String _identitySeedKey = 'e2ee_identity_seed';
  static const String _signingSeedKey = 'e2ee_signing_seed';
  static const String _signedPrekeySeedKey = 'e2ee_signed_prekey_seed';

  static final _x25519 = X25519();
  static final _ed25519 = Ed25519();
  static final _kdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _cipher = AesGcm.with256bits();
  static final Map<String, SecretKey> _chatKeyCache = {};
  static final Map<String, Future<SecretKey?>> _chatKeyInFlight = {};

  static Future<SecretKey> _deriveCompatibilityChatKey({
    required String chatId,
    required String myUserId,
    required String partnerUserId,
  }) async {
    final participants = <String>[myUserId, partnerUserId]..sort();
    final seedMaterial = utf8.encode(
      'xapzap-compat-chat:${participants.join(':')}:$chatId',
    );
    return _kdf.deriveKey(
      secretKey: SecretKey(seedMaterial),
      nonce: utf8.encode(chatId),
      info: utf8.encode('xapzap-compat-session-v1'),
    );
  }

  static Future<String> getDeviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final random = await _cipher.newSecretKey();
    final bytes = await random.extractBytes();
    final deviceId =
        base64UrlEncode(bytes).replaceAll('=', '').substring(0, 24);
    await _storage.write(key: _deviceIdKey, value: deviceId);
    return deviceId;
  }

  static Future<List<int>> _loadOrCreateSeed(String storageKey) async {
    final existing = await _storage.read(key: storageKey);
    if (existing != null && existing.isNotEmpty) {
      return base64Decode(existing);
    }
    final random = await _cipher.newSecretKey();
    final seed = await random.extractBytes();
    await _storage.write(key: storageKey, value: base64Encode(seed));
    return seed;
  }

  static Future<SimpleKeyPair> _getIdentityKeyPair() async {
    final seed = await _loadOrCreateSeed(_identitySeedKey);
    return _x25519.newKeyPairFromSeed(seed);
  }

  static Future<SimpleKeyPair> _getSigningKeyPair() async {
    final seed = await _loadOrCreateSeed(_signingSeedKey);
    return _ed25519.newKeyPairFromSeed(seed);
  }

  static Future<SimpleKeyPair> _getSignedPrekeyPair() async {
    final seed = await _loadOrCreateSeed(_signedPrekeySeedKey);
    return _x25519.newKeyPairFromSeed(seed);
  }

  static Future<KeyPair?> ensureIdentityKeysAndPublish() async {
    final me = await AppwriteService.getCurrentUser();
    if (me == null) return null;

    final identityKeys = await _getIdentityKeyPair();
    final identityPublicKey = await identityKeys.extractPublicKey();
    final publicKeyB64 = base64Encode(identityPublicKey.bytes);

    try {
      await AppwriteService.updateUserProfile(me.$id, {
        'publicKey': publicKeyB64,
      });
    } catch (_) {}

    await ensureDeviceBundlePublished();
    return identityKeys;
  }

  static Future<bool> ensureDeviceBundlePublished() async {
    final me = await AppwriteService.getCurrentUser();
    if (me == null) return false;

    try {
      final deviceId = await getDeviceId();
      final identityKeys = await _getIdentityKeyPair();
      final signingKeys = await _getSigningKeyPair();
      final signedPrekey = await _getSignedPrekeyPair();

      final identityPublicKey = await identityKeys.extractPublicKey();
      final signingPublicKey = await signingKeys.extractPublicKey();
      final signedPrekeyPublicKey = await signedPrekey.extractPublicKey();
      final signature = await _ed25519.sign(
        signedPrekeyPublicKey.bytes,
        keyPair: signingKeys,
      );

      await AppwriteService.upsertChatDeviceBundle(
        me.$id,
        deviceId,
        {
          'identityPublicKey': base64Encode(identityPublicKey.bytes),
          'signingPublicKey': base64Encode(signingPublicKey.bytes),
          'signedPrekeyPublicKey': base64Encode(signedPrekeyPublicKey.bytes),
          'signedPrekeySignature': base64Encode(signature.bytes),
          'keyAlgorithm': currentKeyAlgorithm,
          'signingAlgorithm': currentSigningAlgorithm,
          'cipherAlgorithm': currentCipherAlgorithm,
          'e2eeVersion': currentE2eeVersion,
          'isActive': true,
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<ChatDeviceBundle?> fetchPrimaryVerifiedDeviceBundle(
    String userId,
  ) async {
    try {
      final rows = await AppwriteService.fetchChatDevicesForUser(userId);
      for (final row in rows.rows) {
        final data = row.data;
        final identityB64 = (data['identityPublicKey'] as String?) ?? '';
        final signingB64 = (data['signingPublicKey'] as String?) ?? '';
        final signedPrekeyB64 =
            (data['signedPrekeyPublicKey'] as String?) ?? '';
        final signatureB64 = (data['signedPrekeySignature'] as String?) ?? '';
        if (identityB64.isEmpty ||
            signingB64.isEmpty ||
            signedPrekeyB64.isEmpty ||
            signatureB64.isEmpty) {
          continue;
        }

        final identityPublicKey = SimplePublicKey(
          base64Decode(identityB64),
          type: KeyPairType.x25519,
        );
        final signingPublicKey = SimplePublicKey(
          base64Decode(signingB64),
          type: KeyPairType.ed25519,
        );
        final signedPrekeyPublicKey = SimplePublicKey(
          base64Decode(signedPrekeyB64),
          type: KeyPairType.x25519,
        );
        final signatureBytes = base64Decode(signatureB64);
        final signature = Signature(
          signatureBytes,
          publicKey: signingPublicKey,
        );
        final isValid = await _ed25519.verify(
          signedPrekeyPublicKey.bytes,
          signature: signature,
        );
        if (!isValid) {
          continue;
        }

        return ChatDeviceBundle(
          userId: userId,
          deviceId: (data['deviceId'] as String?) ?? '',
          identityPublicKey: identityPublicKey,
          signingPublicKey: signingPublicKey,
          signedPrekeyPublicKey: signedPrekeyPublicKey,
          signedPrekeySignature: signatureBytes,
          signatureValid: true,
        );
      }
    } catch (_) {}
    return null;
  }

  static Future<SecretKey?> getChatKey({
    required String chatId,
    required String partnerUserId,
  }) async {
    final cacheKey = '$chatId::$partnerUserId';
    final cached = _chatKeyCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final inFlight = _chatKeyInFlight[cacheKey];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _resolveChatKey(
      chatId: chatId,
      partnerUserId: partnerUserId,
      cacheKey: cacheKey,
    );
    _chatKeyInFlight[cacheKey] = future;
    try {
      return await future;
    } finally {
      _chatKeyInFlight.remove(cacheKey);
    }
  }

  static Future<List<int>?> getChatKeyBytes({
    required String chatId,
    required String partnerUserId,
  }) async {
    final key = await getChatKey(chatId: chatId, partnerUserId: partnerUserId);
    if (key == null) return null;
    return key.extractBytes();
  }

  static Future<SecretKey?> _resolveChatKey({
    required String chatId,
    required String partnerUserId,
    required String cacheKey,
  }) async {
    final me = await AppwriteService.getCurrentUser();
    if (me == null) return null;

    await ensureDeviceBundlePublished();
    final partnerBundle = await fetchPrimaryVerifiedDeviceBundle(partnerUserId);
    if (partnerBundle == null || !partnerBundle.signatureValid) {
      final compat = await _deriveCompatibilityChatKey(
        chatId: chatId,
        myUserId: me.$id,
        partnerUserId: partnerUserId,
      );
      _chatKeyCache[cacheKey] = compat;
      return compat;
    }

    final storageKey = 'chat_key_${chatId}_${partnerBundle.deviceId}';
    final cached = await _storage.read(key: storageKey);
    if (cached != null && cached.isNotEmpty) {
      final secret = SecretKey(base64Decode(cached));
      _chatKeyCache[cacheKey] = secret;
      return secret;
    }

    final identityKeys = await _getIdentityKeyPair();
    final shared = await _x25519.sharedSecretKey(
      keyPair: identityKeys,
      remotePublicKey: partnerBundle.signedPrekeyPublicKey,
    );

    final derived = await _kdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode('$chatId:${partnerBundle.deviceId}'),
      info: utf8.encode('xapzap-session-v2'),
    );

    final raw = await derived.extractBytes();
    await _storage.write(key: storageKey, value: base64Encode(raw));
    _chatKeyCache[cacheKey] = derived;
    return derived;
  }

  static Future<Map<String, String>?> encryptMessage({
    required String chatId,
    required String partnerUserId,
    required String plaintext,
  }) async {
    final key = await getChatKey(chatId: chatId, partnerUserId: partnerUserId);
    if (key == null) {
      return null;
    }
    final nonce = _cipher.newNonce();
    final secretBox = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    return {
      'ciphertext': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(secretBox.nonce),
      'mac': base64Encode(secretBox.mac.bytes),
    };
  }

  static Future<String?> decryptMessage({
    required String chatId,
    required String partnerUserId,
    required String ciphertextB64,
    required String nonceB64,
    required String macB64,
  }) async {
    final key = await getChatKey(chatId: chatId, partnerUserId: partnerUserId);
    if (key == null) return null;

    try {
      final box = SecretBox(
        base64Decode(ciphertextB64),
        nonce: base64Decode(nonceB64),
        mac: Mac(base64Decode(macB64)),
      );
      final clearBytes = await _cipher.decrypt(box, secretKey: key);
      return utf8.decode(clearBytes);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getIdentityFingerprint() async {
    final keyPair = await ensureIdentityKeysAndPublish();
    if (keyPair == null) return null;
    final extracted = await keyPair.extract();
    final pub = extracted.publicKey;
    if (pub is! SimplePublicKey) {
      return null;
    }
    return _groupFingerprint(hash.sha256.convert(pub.bytes).toString());
  }

  static Future<String> buildSafetyNumber(String partnerUserId) async {
    await ensureDeviceBundlePublished();
    final myIdentityKeys = await _getIdentityKeyPair();
    final mySigningKeys = await _getSigningKeyPair();
    final myIdentityPublic = await myIdentityKeys.extractPublicKey();
    final mySigningPublic = await mySigningKeys.extractPublicKey();
    final partnerBundle = await fetchPrimaryVerifiedDeviceBundle(partnerUserId);

    final buffer = <int>[
      ...myIdentityPublic.bytes,
      ...mySigningPublic.bytes,
      if (partnerBundle != null) ...partnerBundle.identityPublicKey.bytes,
      if (partnerBundle != null) ...partnerBundle.signingPublicKey.bytes,
    ];
    final digest = hash.sha256.convert(buffer).toString();
    return _groupFingerprint(digest);
  }

  static String _groupFingerprint(String value) {
    final compact = value.replaceAll(RegExp(r'[^A-Fa-f0-9]'), '').toUpperCase();
    final chunks = <String>[];
    for (var i = 0; i < compact.length && i < 48; i += 4) {
      final end = (i + 4 < compact.length) ? i + 4 : compact.length;
      chunks.add(compact.substring(i, end));
    }
    return chunks.join(' ');
  }

  static Future<bool> isSafetyNumberVerified(
    String partnerUserId,
    String safetyNumber,
  ) async {
    final stored = await _storage.read(
      key: 'verified_safety_$partnerUserId',
    );
    return stored == safetyNumber;
  }

  static Future<void> markSafetyNumberVerified(
    String partnerUserId,
    String safetyNumber,
  ) async {
    await _storage.write(
      key: 'verified_safety_$partnerUserId',
      value: safetyNumber,
    );
  }

  static Future<void> clearSafetyNumberVerification(
      String partnerUserId) async {
    await _storage.delete(key: 'verified_safety_$partnerUserId');
  }

  static Future<ChatSecurityInfo> getChatSecurityInfo({
    required String chatId,
    required String partnerUserId,
  }) async {
    final devicePublished = await ensureDeviceBundlePublished();
    final deviceId = await getDeviceId();
    final partnerBundle = await fetchPrimaryVerifiedDeviceBundle(partnerUserId);
    final sessionReady =
        await getChatKey(chatId: chatId, partnerUserId: partnerUserId) != null;
    final safetyNumber = await buildSafetyNumber(partnerUserId);
    final verified = await isSafetyNumberVerified(partnerUserId, safetyNumber);

    return ChatSecurityInfo(
      deviceBundlePublished: devicePublished,
      partnerBundleAvailable: partnerBundle != null,
      partnerBundleVerified: partnerBundle?.signatureValid ?? false,
      sessionReady: sessionReady,
      safetyNumberVerified: verified,
      deviceId: deviceId,
      partnerDeviceId: partnerBundle?.deviceId,
      safetyNumber: safetyNumber,
    );
  }
}
