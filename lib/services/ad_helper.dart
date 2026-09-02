import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdHelper {
  static const String appId = 'ca-app-pub-6927256363821778~7392700976';

  static String get appOpen {
    if (kDebugMode) {
      return 'ca-app-pub-3940256099942544/9257395921';
    }
    final raw = dotenv.env['XAPZAP_APP_OPEN_AD_UNIT_ID']?.trim();
    return raw == null || raw.isEmpty ? 'ca-app-pub-6927256363821778/7137550107' : raw;
  }

  static String get banner => kDebugMode
      ? 'ca-app-pub-3940256099942544/6300978111'
      : 'ca-app-pub-6927256363821778/6670646245';

  static String get interstitial {
    if (kDebugMode) {
      return 'ca-app-pub-3940256099942544/1033173712';
    }
    final raw = dotenv.env['XAPZAP_INTERSTITIAL_AD_UNIT_ID']?.trim();
    return raw == null || raw.isEmpty ? 'ca-app-pub-6927256363821778/5357564573' : raw;
  }

  static String get native => kDebugMode
      ? 'ca-app-pub-3940256099942544/2247696110'
      : 'ca-app-pub-6927256363821778/4507894635';

  static String get rewarded => kDebugMode
      ? 'ca-app-pub-3940256099942544/5224354917'
      : 'ca-app-pub-6927256363821778/2076795115';

  static String get rewardedReels => kDebugMode
      ? 'ca-app-pub-3940256099942544/5224354917'
      : 'ca-app-pub-6927256363821778/5820976305';

  static List<String> get nativeUnits {
    if (kDebugMode) {
      return const <String>['ca-app-pub-3940256099942544/2247696110'];
    }
    final raw = dotenv.env['XAPZAP_NATIVE_AD_UNIT_IDS']?.trim();
    if (raw == null || raw.isEmpty) {
      return <String>[native];
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
      return <String>[rewarded];
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

  // High eCPM/RPM financial keywords targeting configuration
  static AdRequest get financialRequest => const AdRequest(
    keywords: <String>[
      'finance',
      'investing',
      'personal finance',
      'passive income',
      'loans',
      'credit cards',
      'savings accounts',
      'make money online',
      'earn money',
      'wealth management',
      'insurance',
      'cryptocurrency',
      'trading',
    ],
    contentUrl: 'https://xapzap.com/personal-finance-earnings',
  );
}

