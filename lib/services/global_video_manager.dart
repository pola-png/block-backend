import 'dart:async';

class GlobalVideoManager {
  static Object? _activeOwner;
  static Future<void> Function()? _activeRelease;

  static Future<void> claim(
    Object owner, {
    required Future<void> Function() releaseOthers,
  }) async {
    if (identical(_activeOwner, owner)) return;
    final previousRelease = _activeRelease;
    if (previousRelease != null) {
      await previousRelease();
    }
    _activeOwner = owner;
    _activeRelease = releaseOthers;
  }

  static void clear(Object owner) {
    if (!identical(_activeOwner, owner)) return;
    _activeOwner = null;
    _activeRelease = null;
  }

  static Future<void> releaseActive() async {
    final release = _activeRelease;
    _activeOwner = null;
    _activeRelease = null;
    if (release != null) {
      await release();
    }
  }
}
