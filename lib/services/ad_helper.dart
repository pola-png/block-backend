import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AdHelper {
  static const String appId = 'ca-app-pub-3088816615654692~2908303701';

  static String get appOpen => kDebugMode
      ? 'ca-app-pub-3940256099942544/9257395921'
      : 'ca-app-pub-3088816615654692/2070381678';

  static String get banner => kDebugMode
      ? 'ca-app-pub-3940256099942544/6300978111'
      : 'ca-app-pub-3088816615654692/4271104801';

  static String get interstitial => kDebugMode
      ? 'ca-app-pub-3940256099942544/1033173712'
      : 'ca-app-pub-3088816615654692/2958023134';

  static String get native => kDebugMode
      ? 'ca-app-pub-3940256099942544/2247696110'
      : 'ca-app-pub-3088816615654692/6836086212';

  static String get rewarded => kDebugMode
      ? 'ca-app-pub-3940256099942544/5224354917'
      : 'ca-app-pub-3088816615654692/1556527737';

  static String get rewardedReels => kDebugMode
      ? 'ca-app-pub-3940256099942544/5224354917'
      : 'ca-app-pub-3088816615654692/7794633021';

  static List<String> get nativeUnits {
    if (kDebugMode) {
      return const <String>['ca-app-pub-3940256099942544/2247696110'];
    }
    final raw = dotenv.env['XAPZAP_NATIVE_AD_UNIT_IDS']?.trim();
    if (raw == null || raw.isEmpty) {
      return const <String>[
        'ca-app-pub-3088816615654692/6836086212',
        'ca-app-pub-3088816615654692/1141657121',
        'ca-app-pub-3088816615654692/4267634446',
        'ca-app-pub-3088816615654692/5150410625',
        'ca-app-pub-3088816615654692/4822904305',
        'ca-app-pub-3088816615654692/9584479652',
        'ca-app-pub-3088816615654692/3837328954',
        'ca-app-pub-3088816615654692/1211165614',
        'ca-app-pub-3088816615654692/9883659298',
        'ca-app-pub-3088816615654692/2707876854',
        'ca-app-pub-3088816615654692/7795815913',
        'ca-app-pub-3088816615654692/5565343598',
        'ca-app-pub-3088816615654692/8015307768',
        'ca-app-pub-3088816615654692/1394795186',
        'ca-app-pub-3088816615654692/6702226095',
        'ca-app-pub-3088816615654692/8898083945',
        'ca-app-pub-3088816615654692/8271397981',
        'ca-app-pub-3088816615654692/5169652571',
        'ca-app-pub-3088816615654692/7585002271',
      ];
    }
    final units = raw
        .split(',')
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList(growable: false);
    return units.isEmpty ? <String>[native] : units;
  }

  static String nativeForSlot(int slotIndex) {
    final units = nativeUnits;
    return units[slotIndex % units.length];
  }

  static String nativeForFeedSlot(int slotIndex) {
    final units = nativeUnits;
    if (units.length <= 1) return units.first;
    // Shift feed slots away from the first three inventory entries.
    final feedIndex = (slotIndex + 3) % units.length;
    return units[feedIndex];
  }

  static List<String> get rewardedUnits {
    if (kDebugMode) {
      return const <String>['ca-app-pub-3940256099942544/5224354917'];
    }
    final raw = dotenv.env['XAPZAP_REWARDED_AD_UNIT_IDS']?.trim();
    if (raw == null || raw.isEmpty) {
      return <String>[
        rewarded,
        'ca-app-pub-3088816615654692/9108897586',
        'ca-app-pub-3088816615654692/5269626865',
        'ca-app-pub-3088816615654692/1259063819',
        'ca-app-pub-3088816615654692/3509822630',
        'ca-app-pub-3088816615654692/4958838933',
      ];
    }
    final units = raw
        .split(',')
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList(growable: false);
    return units.isEmpty ? <String>[rewarded] : units;
  }

  static String rewardedForKey(String key) {
    final units = rewardedUnits;
    if (units.length == 1) return units.first;
    final index = key.hashCode.abs() % units.length;
    return units[index];
  }

  static String get rewardedReelsUnit {
    if (kDebugMode) {
      return 'ca-app-pub-3940256099942544/5224354917';
    }
    final raw = dotenv.env['XAPZAP_REWARDED_REELS_AD_UNIT_ID']?.trim();
    return raw == null || raw.isEmpty ? rewardedReels : raw;
  }
}

