import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import '../models/reward_live_model.dart';

/// Generates and plays rich, custom sound signatures for the 20 official XapZap gifts
class GiftSoundService {
  GiftSoundService._internal();
  static final GiftSoundService instance = GiftSoundService._internal();

  FlutterSoundPlayer? _player;
  bool _isPlayerOpen = false;
  final Map<String, Uint8List> _soundCache = {};

  Future<void> init() async {
    if (_isPlayerOpen) return;
    try {
      _player = FlutterSoundPlayer();
      await _player!.openPlayer();
      await _player!.setVolume(0.35);
      _isPlayerOpen = true;
    } catch (e) {
      debugPrint('[GiftSoundService] Error opening player: $e');
    }
  }

  void dispose() {
    try {
      if (_isPlayerOpen && _player != null) {
        _player!.closePlayer();
        _isPlayerOpen = false;
      }
    } catch (_) {}
  }

  Uint8List _getOrGenerateSound(String key) {
    if (_soundCache.containsKey(key)) {
      return _soundCache[key]!;
    }
    Uint8List generated;
    switch (key) {
      case 'xapzap_universe':
        generated = _genXapZapUniverse();
        break;
      case 'thunder_falcon':
        generated = _genThunderFalcon();
        break;
      case 'fire_phoenix':
        generated = _genFirePhoenix();
        break;
      case 'leon_and_lion':
        generated = _genLeonAndLion();
        break;
      case 'zeus':
        generated = _genZeus();
        break;
      case 'lion':
        generated = _genLion();
        break;
      case 'golden_sports_car':
        generated = _genGoldenSportsCar();
        break;
      case 'dragon_flame':
        generated = _genDragonFlame();
        break;
      case 'dragon_phoenix':
        generated = _genDragonPhoenix();
        break;
      case 'castle_fantasy':
        generated = _genCastleFantasy();
        break;
      case 'dolphin':
        generated = _genDolphin();
        break;
      case 'rocket':
        generated = _genRocket();
        break;
      case 'interstellar':
        generated = _genInterstellar();
        break;
      case 'falcon':
        generated = _genFalcon();
        break;
      case 'sports_car':
        generated = _genSportsCar();
        break;
      case 'unicorn_fantasy':
        generated = _genUnicornFantasy();
        break;
      case 'private_jet':
        generated = _genPrivateJet();
        break;
      case 'whale_diving':
        generated = _genWhaleDiving();
        break;
      case 'fireworks':
        generated = _genFireworks();
        break;
      case 'galaxy':
        generated = _genGalaxy();
        break;
      default:
        generated = _genXapZapUniverse();
        break;
    }
    _soundCache[key] = generated;
    return generated;
  }

  bool _isPlaying = false;

  Future<void> playGiftSound(RewardDefinition reward) async {
    // 1. Tactile haptic burst (No OS generic click tone)
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}

    // 2. If another sound is currently playing, remain silent to avoid audio clash and native crashes
    if (_isPlaying) {
      return;
    }

    // 3. High-fidelity audio playback
    if (!_isPlayerOpen || _player == null) {
      await init();
    }
    if (!_isPlayerOpen || _player == null) return;

    try {
      _isPlaying = true;
      final key = _resolveSoundKey(reward);
      final wavData = _getOrGenerateSound(key);

      if (_player!.isPlaying) {
        await _player!.stopPlayer();
      }

      await _player!.startPlayer(
        fromDataBuffer: wavData,
        codec: Codec.pcm16WAV,
        whenFinished: () {
          _isPlaying = false;
        },
      );

      // Auto-unlock timeout safeguard
      Future.delayed(const Duration(milliseconds: 2000), () {
        _isPlaying = false;
      });
    } catch (e) {
      _isPlaying = false;
      debugPrint('[GiftSoundService] Error playing sound for ${reward.id}: $e');
    }
  }

  String _resolveSoundKey(RewardDefinition reward) {
    final id = reward.id.toLowerCase();
    final name = reward.name.toLowerCase();

    if (_soundCache.containsKey(id)) return id;

    if (id.contains('xapzap') || name.contains('xapzap') || name.contains('universe')) return 'xapzap_universe';
    if (id.contains('thunder') || name.contains('thunder')) return 'thunder_falcon';
    if (id.contains('phoenix') && id.contains('fire')) return 'fire_phoenix';
    if (id.contains('leon') || name.contains('leon')) return 'leon_and_lion';
    if (id.contains('zeus') || name.contains('zeus')) return 'zeus';
    if (id.contains('golden') || name.contains('golden')) return 'golden_sports_car';
    if (id.contains('dragon') && id.contains('flame')) return 'dragon_flame';
    if (id.contains('dragon') && id.contains('phoenix')) return 'dragon_phoenix';
    if (id.contains('castle') || name.contains('castle')) return 'castle_fantasy';
    if (id.contains('dolphin') || name.contains('dolphin')) return 'dolphin';
    if (id.contains('rocket') || name.contains('rocket')) return 'rocket';
    if (id.contains('interstellar') || name.contains('interstellar')) return 'interstellar';
    if (id.contains('falcon') || name.contains('falcon')) return 'falcon';
    if (id.contains('sports') || name.contains('sports')) return 'sports_car';
    if (id.contains('unicorn') || name.contains('unicorn')) return 'unicorn_fantasy';
    if (id.contains('jet') || name.contains('jet')) return 'private_jet';
    if (id.contains('whale') || name.contains('whale')) return 'whale_diving';
    if (id.contains('fireworks') || name.contains('fireworks')) return 'fireworks';
    if (id.contains('galaxy') || name.contains('galaxy')) return 'galaxy';
    if (id.contains('lion') || name.contains('lion')) return 'lion';

    return 'xapzap_universe';
  }

  // -------------------------------------------------------------
  // AUDIO SYNTHESIZERS (Pure Dart 16-Bit PCM WAV Generators)
  // -------------------------------------------------------------
  static Uint8List _createWavContainer(List<int> pcm16Samples, int sampleRate) {
    final byteCount = pcm16Samples.length * 2;
    final totalSize = 44 + byteCount;
    final buffer = ByteData(totalSize);

    // RIFF header
    buffer.setUint8(0, 0x52); buffer.setUint8(1, 0x49); buffer.setUint8(2, 0x46); buffer.setUint8(3, 0x46);
    buffer.setUint32(4, totalSize - 8, Endian.little);
    buffer.setUint8(8, 0x57); buffer.setUint8(9, 0x41); buffer.setUint8(10, 0x56); buffer.setUint8(11, 0x45);

    // fmt sub-chunk
    buffer.setUint8(12, 0x66); buffer.setUint8(13, 0x6D); buffer.setUint8(14, 0x74); buffer.setUint8(15, 0x20);
    buffer.setUint32(16, 16, Endian.little);
    buffer.setUint16(20, 1, Endian.little); // PCM
    buffer.setUint16(22, 1, Endian.little); // Mono
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little);
    buffer.setUint16(32, 2, Endian.little);
    buffer.setUint16(34, 16, Endian.little);

    // data sub-chunk
    buffer.setUint8(36, 0x64); buffer.setUint8(37, 0x61); buffer.setUint8(38, 0x74); buffer.setUint8(39, 0x61);
    buffer.setUint32(40, byteCount, Endian.little);

    var offset = 44;
    for (final sample in pcm16Samples) {
      final scaled = (sample * 0.35).clamp(-32768, 32767).toInt();
      buffer.setInt16(offset, scaled, Endian.little);
      offset += 2;
    }

    return buffer.buffer.asUint8List();
  }

  // 1. 🌌 XapZap Universe: Huge cinematic/futuristic fanfare + explosive/space sound
  static Uint8List _genXapZapUniverse() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.75).toInt();
    final samples = <int>[];
    final fanfareNotes = [261.63, 329.63, 392.00, 523.25, 659.25, 783.99, 1046.50];

    for (int i = 0; i < totalSamples; i++) {
      final t = i / totalSamples;
      final subBassBoom = sin(2 * pi * (60.0 - 25.0 * t) * (i / sampleRate)) * exp(-2.2 * t);
      double brassFanfare = 0.0;
      for (final n in fanfareNotes) {
        brassFanfare += sin(2 * pi * n * (i / sampleRate) + sin(8 * pi * t));
      }
      brassFanfare /= fanfareNotes.length;
      final spaceWhoosh = sin(2 * pi * (200.0 + 900.0 * pow(t, 2.0)) * (i / sampleRate)) * 0.35;
      final envelope = sin(pi * pow(t, 0.25)) * exp(-2.0 * t);
      final mix = (0.45 * subBassBoom + 0.35 * brassFanfare + 0.20 * spaceWhoosh) * envelope;
      samples.add((mix * 32767 * 0.95).toInt().clamp(-32768, 32767));
    }
    return _createWavContainer(samples, sampleRate);
  }

  // 2. 🦅 Thunder Falcon: Thunder + powerful falcon/bird sound + dramatic impact
  static Uint8List _genThunderFalcon() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.65).toInt();
    final samples = <int>[];

    for (int i = 0; i < totalSamples; i++) {
      final t = i / totalSamples;
      final screechFreq = 1600.0 + 1400.0 * sin(pi * t) + 200.0 * sin(40 * pi * t);
      final birdCall = sin(2 * pi * screechFreq * (i / sampleRate)) + 0.3 * sin(4 * pi * screechFreq * (i / sampleRate));
      final thunderBoom = sin(2 * pi * (90.0 - 55.0 * t) * (i / sampleRate)) * exp(-2.5 * t);
      final envelope = exp(-2.6 * t);
      final mix = (0.55 * birdCall + 0.45 * thunderBoom) * envelope;
      samples.add((mix * 32767 * 0.95).toInt().clamp(-32768, 32767));
    }
    return _createWavContainer(samples, sampleRate);
  }

  // 3. 🔥 Fire Phoenix: Fire whoosh + phoenix/bird cry + epic impact
  static Uint8List _genFirePhoenix() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.60).toInt();
    final samples = <int>[];

    for (int i = 0; i < totalSamples; i++) {
      final t = i / totalSamples;
      final cryFreq = 950.0 + 1100.0 * sin(pi * pow(t, 0.6)) + 120.0 * sin(30 * pi * t);
      final phoenixCry = sin(2 * pi * cryFreq * (i / sampleRate));
      final fireWhoosh = (sin(2 * pi * 350 * (i / sampleRate)) + sin(2 * pi * 520 * (i / sampleRate))) * (1.0 - t);
      final impact = sin(2 * pi * (100.0 - 40.0 * t) * (i / sampleRate)) * exp(-3.0 * t);
      final envelope = exp(-2.5 * t);
      final mix = (0.45 * phoenixCry + 0.35 * fireWhoosh + 0.20 * impact) * envelope;
      samples.add((mix * 32767 * 0.95).toInt().clamp(-32768, 32767));
    }
    return _createWavContainer(samples, sampleRate);
  }

  // 4. 🦁 Leon and Lion: Lion roar + dramatic cinematic hit
  static Uint8List _genLeonAndLion() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.65).toInt();
    final samples = <int>[];

    for (int i = 0; i < totalSamples; i++) {
      final t = i / totalSamples;
      final dualRoarFreq1 = 120.0 + 40.0 * sin(15 * pi * t) - 45.0 * t;
      final dualRoarFreq2 = 145.0 + 50.0 * sin(18 * pi * t) - 50.0 * t;
      final roar1 = sin(2 * pi * dualRoarFreq1 * (i / sampleRate)) + 0.5 * sin(3 * pi * dualRoarFreq1 * (i / sampleRate));
      final roar2 = sin(2 * pi * dualRoarFreq2 * (i / sampleRate)) + 0.4 * sin(4 * pi * dualRoarFreq2 * (i / sampleRate));
      final cinematicHit = sin(2 * pi * (70.0 - 30.0 * t) * (i / sampleRate)) * exp(-3.2 * t);
      final envelope = sin(pi * pow(t, 0.35)) * exp(-2.2 * t);
      final mix = (0.40 * roar1 + 0.35 * roar2 + 0.25 * cinematicHit) * envelope;
      samples.add((mix * 32767 * 0.95).toInt().clamp(-32768, 32767));
    }
    return _createWavContainer(samples, sampleRate);
  }

  // 5. ⚡ Zeus: Thunder crack + powerful boom + divine/epic sound
  static Uint8List _genZeus() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.60).toInt();
    final samples = <int>[];

    for (int i = 0; i < totalSamples; i++) {
      final t = i / totalSamples;
      final crackle = (t < 0.20) ? sin(2 * pi * 2200 * (i / sampleRate)) * (1.0 - t / 0.20) : 0.0;
      final divineChoir = sin(2 * pi * 880 * (i / sampleRate)) * sin(pi * t) * 0.3;
      final heavyBoom = sin(2 * pi * (75.0 - 40.0 * t) * (i / sampleRate)) * exp(-2.8 * t);
      final mix = (0.40 * crackle + 0.40 * heavyBoom + 0.20 * divineChoir);
      samples.add((mix * 32767 * 0.96).toInt().clamp(-32768, 32767));
    }
    return _createWavContainer(samples, sampleRate);
  }

  // 6. 🦁 Lion: Deep lion roar + heavy cinematic impact
  static Uint8List _genLion() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.58).toInt();
    final samples = <int>[];

    for (int i = 0; i < totalSamples; i++) {
      final t = i / totalSamples;
      final roarFreq = 105.0 + 35.0 * sin(16 * pi * t) - 35.0 * t;
      final roar = sin(2 * pi * roarFreq * (i / sampleRate)) + 0.6 * sin(3 * pi * roarFreq * (i / sampleRate));
      final subImpact = sin(2 * pi * (80.0 - 40.0 * t) * (i / sampleRate)) * exp(-3.0 * t);
      final envelope = sin(pi * pow(t, 0.4)) * exp(-2.4 * t);
      final mix = (0.65 * roar + 0.35 * subImpact) * envelope;
      samples.add((mix * 32767 * 0.95).toInt().clamp(-32768, 32767));
    }
    return _createWavContainer(samples, sampleRate);
  }

  // 7. 🚗 Golden Sports Car: Engine rev + fast whoosh + luxury impact
  static Uint8List _genGoldenSportsCar() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.55).toInt();
    final samples = <int>[];

    for (int i = 0; i < totalSamples; i++) {
      final t = i / totalSamples;
      final revFreq = 180.0 + 850.0 * pow(t, 1.3);
      final engine = sin(2 * pi * revFreq * (i / sampleRate)) + 0.4 * sin(3 * pi * revFreq * (i / sampleRate));
      final luxuryChime = sin(2 * pi * 1320.0 * (i / sampleRate)) * exp(-4.0 * t) * 0.35;
      final whoosh = sin(2 * pi * 420 * (i / sampleRate)) * sin(pi * t);
      final mix = (0.50 * engine + 0.25 * luxuryChime + 0.25 * whoosh);
      samples.add((mix * 32767 * 0.92).toInt().clamp(-32768, 32767));
    }
    return _createWavContainer(samples, sampleRate);
  }

  // 8. 🔥 Dragon Flame: Dragon roar + fire burst/whoosh + heavy impact
  static Uint8List _genDragonFlame() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.60).toInt();
    final samples = <int>[];

    for (int i = 0; i < totalSamples; i++) {
      final t = i / totalSamples;
      final dragonRoarFreq = 150.0 + 90.0 * sin(12 * pi * t) - 60.0 * t;
      final roar = sin(2 * pi * dragonRoarFreq * (i / sampleRate)) + 0.5 * sin(2 * pi * (dragonRoarFreq * 2.5) * (i / sampleRate));
      final flameBurst = sin(2 * pi * 440 * (i / sampleRate)) * (1.0 - t);
      final subImpact = sin(2 * pi * 65 * (i / sampleRate)) * exp(-3.0 * t);
      final envelope = exp(-2.4 * t);
      final mix = (0.50 * roar + 0.30 * flameBurst + 0.20 * subImpact) * envelope;
      samples.add((mix * 32767 * 0.95).toInt().clamp(-32768, 32767));
    }
    return _createWavContainer(samples, sampleRate);
  }

  // 9. 🐉 Dragon/Phoenix: Roar + fire/wind + cinematic impact
  static Uint8List _genDragonPhoenix() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.62).toInt();
    final samples = <int>[];

    for (int i = 0; i < totalSamples; i++) {
      final t = i / totalSamples;
      final roar = sin(2 * pi * (140.0 - 40.0 * t) * (i / sampleRate));
      final cry = sin(2 * pi * (1100.0 + 500.0 * sin(pi * t)) * (i / sampleRate)) * 0.4;
      final wind = sin(2 * pi * 320 * (i / sampleRate)) * (1.0 - t) * 0.3;
      final subImpact = sin(2 * pi * 70 * (i / sampleRate)) * exp(-3.0 * t);
      final envelope = exp(-2.3 * t);
      final mix = (0.40 * roar + 0.30 * cry + 0.15 * wind + 0.15 * subImpact) * envelope;
      samples.add((mix * 32767 * 0.95).toInt().clamp(-32768, 32767));
    }
    return _createWavContainer(samples, sampleRate);
  }

  // 10. 🏰 Castle Fantasy: Magical orchestral fanfare + sparkle/impact
  static Uint8List _genCastleFantasy() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.58).toInt();
    final samples = <int>[];
    final notes = [392.00, 523.25, 659.25, 783.99, 1046.50];

    for (int i = 0; i < totalSamples; i++) {
      final t = i / totalSamples;
      double fanfare = 0.0;
      for (final n in notes) {
        fanfare += sin(2 * pi * n * (i / sampleRate));
      }
      fanfare /= notes.length;
      final sparkle = sin(2 * pi * (1400.0 + 900.0 * sin(24 * pi * t)) * (i / sampleRate)) * 0.35;
      final envelope = exp(-2.6 * t);
      final mix = (fanfare * 0.70 + sparkle * 0.30) * envelope;
      samples.add((mix * 32767 * 0.92).toInt().clamp(-32768, 32767));
    }
    return _createWavContainer(samples, sampleRate);
  }

  // 11. 🐬 Dolphin: Water splash + dolphin call + magical sound
  static Uint8List _genDolphin() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.50).toInt();
    final samples = <int>[];

    for (int i = 0; i < totalSamples; i++) {
      final t = i / totalSamples;
      final dolphinFreq = 1400.0 + 1400.0 * sin(pi * t) + 160.0 * sin(32 * pi * t);
      final chirp = sin(2 * pi * dolphinFreq * (i / sampleRate));
      final splash = sin(2 * pi * 240 * (i / sampleRate)) * exp(-5.0 * t) * 0.4;
      final chime = sin(2 * pi * 1567.98 * (i / sampleRate)) * exp(-3.5 * t) * 0.25;
      final envelope = exp(-2.8 * t);
      final mix = (0.55 * chirp + 0.25 * splash + 0.20 * chime) * envelope;
      samples.add((mix * 32767 * 0.92).toInt().clamp(-32768, 32767));
    }
    return _createWavContainer(samples, sampleRate);
  }

  // 12. 🚀 Rocket: Rocket launch + engine/whoosh + explosion/impact
  static Uint8List _genRocket() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.58).toInt();
    final samples = <int>[];

    for (int i = 0; i < totalSamples; i++) {
      final t = i / totalSamples;
      final rocketPitch = 160.0 * pow(1100.0 / 160.0, t);
      final jetEngine = sin(2 * pi * rocketPitch * (i / sampleRate)) + 0.4 * sin(3 * pi * rocketPitch * (i / sampleRate));
      final subExplosion = sin(2 * pi * (80.0 - 45.0 * t) * (i / sampleRate)) * exp(-2.8 * t);
      final envelope = sin(pi * t);
      final mix = (0.60 * jetEngine * envelope + 0.40 * subExplosion);
      samples.add((mix * 32767 * 0.95).toInt().clamp(-32768, 32767));
    }
    return _createWavContainer(samples, sampleRate);
  }

  // 13. 🌌 Interstellar: Space ambience + rising whoosh + huge cinematic hit
  static Uint8List _genInterstellar() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.68).toInt();
    final samples = <int>[];

    for (int i = 0; i < totalSamples; i++) {
      final t = i / totalSamples;
      final spaceWhoosh = sin(2 * pi * (280.0 + 950.0 * pow(t, 2.2)) * (i / sampleRate));
      final subHit = sin(2 * pi * (65.0 - 25.0 * t) * (i / sampleRate)) * exp(-2.2 * t);
      final cosmicPad = sin(2 * pi * 880.0 * (i / sampleRate)) * 0.25;
      final envelope = exp(-2.3 * t);
      final mix = (0.45 * spaceWhoosh + 0.40 * subHit + 0.15 * cosmicPad) * envelope;
      samples.add((mix * 32767 * 0.95).toInt().clamp(-32768, 32767));
    }
    return _createWavContainer(samples, sampleRate);
  }

  // 14. 🦅 Falcon: Falcon screech + wind/whoosh + impact
  static Uint8List _genFalcon() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.52).toInt();
    final samples = <int>[];

    for (int i = 0; i < totalSamples; i++) {
      final t = i / totalSamples;
      final screechFreq = 1500.0 + 1100.0 * sin(pi * t) + 140.0 * sin(30 * pi * t);
      final screech = sin(2 * pi * screechFreq * (i / sampleRate));
      final wind = sin(2 * pi * 360 * (i / sampleRate)) * (1.0 - t) * 0.35;
      final impact = sin(2 * pi * 95 * (i / sampleRate)) * exp(-4.0 * t) * 0.3;
      final envelope = exp(-3.0 * t);
      final mix = (0.60 * screech + 0.20 * wind + 0.20 * impact) * envelope;
      samples.add((mix * 32767 * 0.92).toInt().clamp(-32768, 32767));
    }
    return _createWavContainer(samples, sampleRate);
  }

  // 15. 🏎️ Sports Car: Engine acceleration + tire/whoosh + impact
  static Uint8List _genSportsCar() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.50).toInt();
    final samples = <int>[];

    for (int i = 0; i < totalSamples; i++) {
      final t = i / totalSamples;
      final revFreq = 150.0 + 680.0 * pow(t, 1.5);
      final engine = sin(2 * pi * revFreq * (i / sampleRate)) + 0.4 * sin(3 * pi * revFreq * (i / sampleRate));
      final tireScreech = (t > 0.15 && t < 0.35) ? sin(2 * pi * 1800 * (i / sampleRate)) * 0.35 : 0.0;
      final envelope = sin(pi * t);
      final mix = (0.70 * engine * envelope + tireScreech);
      samples.add((mix * 32767 * 0.92).toInt().clamp(-32768, 32767));
    }
    return _createWavContainer(samples, sampleRate);
  }

  // 16. 🦄 Unicorn Fantasy: Magical sparkle + fantasy chime + orchestral rise
  static Uint8List _genUnicornFantasy() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.55).toInt();
    final samples = <int>[];
    final harpChords = [523.25, 659.25, 783.99, 1046.50, 1318.51, 1567.98];

    for (int i = 0; i < totalSamples; i++) {
      final t = i / totalSamples;
      final chordIdx = (t * harpChords.length).toInt().clamp(0, harpChords.length - 1);
      final note = sin(2 * pi * harpChords[chordIdx] * (i / sampleRate));
      final sparkle = sin(2 * pi * (1600.0 + 800.0 * sin(28 * pi * t)) * (i / sampleRate)) * 0.35;
      final envelope = exp(-2.8 * t);
      final mix = (0.65 * note + 0.35 * sparkle) * envelope;
      samples.add((mix * 32767 * 0.92).toInt().clamp(-32768, 32767));
    }
    return _createWavContainer(samples, sampleRate);
  }

  // 17. ✈️ Private Jet: Jet engine + fly-by/whoosh + luxury sting
  static Uint8List _genPrivateJet() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.52).toInt();
    final samples = <int>[];

    for (int i = 0; i < totalSamples; i++) {
      final t = i / totalSamples;
      final turbineFreq = 850.0 - 480.0 * pow(t, 0.75);
      final turbine = sin(2 * pi * turbineFreq * (i / sampleRate)) + 0.4 * sin(2 * pi * (turbineFreq * 1.5) * (i / sampleRate));
      final luxurySting = sin(2 * pi * 1396.91 * (i / sampleRate)) * exp(-4.0 * t) * 0.35;
      final envelope = sin(pi * t);
      final mix = (0.65 * turbine * envelope + luxurySting);
      samples.add((mix * 32767 * 0.92).toInt().clamp(-32768, 32767));
    }
    return _createWavContainer(samples, sampleRate);
  }

  // 18. 🐋 Whale Diving: Ocean/water splash + whale sound
  static Uint8List _genWhaleDiving() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.65).toInt();
    final samples = <int>[];

    for (int i = 0; i < totalSamples; i++) {
      final t = i / totalSamples;
      final whalePitch = 130.0 + 170.0 * sin(pi * t);
      final whaleSong = sin(2 * pi * whalePitch * (i / sampleRate)) + 0.5 * sin(2 * pi * (whalePitch * 1.6) * (i / sampleRate));
      final splash = sin(2 * pi * 210 * (i / sampleRate)) * exp(-5.5 * t) * 0.35;
      final envelope = sin(pi * pow(t, 0.4)) * exp(-2.0 * t);
      final mix = (whaleSong / 1.5 * envelope + splash);
      samples.add((mix * 32767 * 0.95).toInt().clamp(-32768, 32767));
    }
    return _createWavContainer(samples, sampleRate);
  }

  // 19. 🎆 Fireworks: Fuse/whoosh + multiple fireworks explosions
  static Uint8List _genFireworks() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.60).toInt();
    final samples = <int>[];

    for (int i = 0; i < totalSamples; i++) {
      final t = i / totalSamples;
      double explosions = 0.0;
      final t1 = (t - 0.04).clamp(0.0, 1.0);
      final t2 = (t - 0.20).clamp(0.0, 1.0);
      final t3 = (t - 0.36).clamp(0.0, 1.0);

      if (t >= 0.04) explosions += sin(2 * pi * 140 * (i / sampleRate)) * exp(-12.0 * t1);
      if (t >= 0.20) explosions += sin(2 * pi * 240 * (i / sampleRate)) * exp(-12.0 * t2);
      if (t >= 0.36) explosions += sin(2 * pi * 110 * (i / sampleRate)) * exp(-10.0 * t3);

      final fuseWhoosh = sin(2 * pi * (1300.0 - 700.0 * t) * (i / sampleRate)) * exp(-4.5 * t) * 0.35;
      final mix = (explosions + fuseWhoosh).clamp(-1.0, 1.0);
      samples.add((mix * 32767 * 0.95).toInt().clamp(-32768, 32767));
    }
    return _createWavContainer(samples, sampleRate);
  }

  // 20. 🌌 Galaxy: Space/galaxy ambience + magical/cinematic sound
  static Uint8List _genGalaxy() {
    const sampleRate = 22050;
    final totalSamples = (sampleRate * 0.64).toInt();
    final samples = <int>[];

    for (int i = 0; i < totalSamples; i++) {
      final t = i / totalSamples;
      final spaceAmbience = sin(2 * pi * (320.0 + 600.0 * sin(pi * t)) * (i / sampleRate));
      final cinematicSub = sin(2 * pi * (70.0 - 25.0 * t) * (i / sampleRate)) * exp(-2.4 * t);
      final magicalChime = sin(2 * pi * 1174.66 * (i / sampleRate)) * exp(-3.0 * t) * 0.30;
      final envelope = exp(-2.2 * t);
      final mix = (0.40 * spaceAmbience + 0.40 * cinematicSub + 0.20 * magicalChime) * envelope;
      samples.add((mix * 32767 * 0.95).toInt().clamp(-32768, 32767));
    }
    return _createWavContainer(samples, sampleRate);
  }
}
