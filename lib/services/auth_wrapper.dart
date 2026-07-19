import 'dart:async';

import 'package:flutter/material.dart';
import '../screens/main_screen.dart';
import '../screens/auth/sign_in_screen.dart';
import '../screens/banned_screen.dart';
import 'appwrite_service.dart';
import 'crypto_service.dart';
import 'device_mode_service.dart';


class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  late bool _isLoading;
  late bool _isAuthenticated;
  late bool _isBanned;

  @override
  void initState() {
    super.initState();
    final cachedUser = AppwriteService.getCurrentUserSync();
    final cachedBanned = AppwriteService.isUserBannedSync();
    final isLoggedIn = AppwriteService.isLoggedInSync();

    if (isLoggedIn || cachedUser != null) {
      _isLoading = false;
      _isAuthenticated = !cachedBanned;
      _isBanned = cachedBanned;

      unawaited(AppwriteService.validateSessionAndStatus(
        onCompleted: (isAuthenticated, isBanned) {
          if (!mounted) return;
          if (_isAuthenticated != isAuthenticated || _isBanned != isBanned) {
            setState(() {
              _isAuthenticated = isAuthenticated;
              _isBanned = isBanned;
            });
          }
        },
      ));

      if (!cachedBanned) {
        unawaited(CryptoService.ensureIdentityKeysAndPublish());
        unawaited(AppwriteService.maybeAutoSyncAdmobRevenue());
      }
    } else {
      _isLoading = false;
      _isAuthenticated = false;
      _isBanned = false;
      _checkAuthStatus();
    }
  }

  Future<void> _checkAuthStatus() async {
    try {
      final user = await AppwriteService.getCurrentUser();
      var banned = false;
      if (user != null) {
        banned = await AppwriteService.isUserBanned(user.$id);
      }
      if (user != null && !banned) {
        unawaited(AppwriteService.validateSessionAndStatus(
          onCompleted: (_, __) {},
        ));
        unawaited(CryptoService.ensureIdentityKeysAndPublish());
        unawaited(AppwriteService.maybeAutoSyncAdmobRevenue());
      }
      setState(() {
        _isAuthenticated = user != null && !banned;
        _isBanned = banned;
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _isAuthenticated = false;
        _isBanned = false;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (DeviceModeService.isTv) {
      return const MainScreen();
    }

    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF29ABE2),
          ),
        ),
      );
    }

    if (_isBanned) {
      return const BannedScreen();
    }

    return _isAuthenticated ? const MainScreen() : const SignInScreen();
  }
}
