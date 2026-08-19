import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/home_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/profile_screen.dart';
import '../models/upload_type.dart';
import '../screens/upload_screen.dart';
import '../services/backend_service.dart';
import '../screens/search_screen.dart';
import '../screens/banned_screen.dart';
import 'dart:async';
import '../services/push_notification_service.dart';
import '../models/chat.dart';
import '../services/chat_message_cache.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const String _welcomeIntroSeenKey = 'has_seen_welcome_intro_v2';

  int _currentIndex = 0;
  bool _isAuthed = false;
  bool _showBottomNav = true;
  int _unreadChats = 0;
  int _unreadNotifications = 0;
  RealtimeSubscription? _badgeSub;
  RealtimeSubscription? _banSub;
  String? _avatarUrl;
  bool _banHandled = false;
  bool _checkedWelcomeIntro = false;
  final ImagePicker _picker = ImagePicker();

  final List<Widget> _screens = [
    const HomeScreen(),
    const ChatScreen(),
    const SizedBox.shrink(),
    const NotificationsScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _checkAuth();
    _loadBadges();
    _subscribeBadges();
    _subscribeBanWatcher();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowWelcomeIntro();
      _initializeNotifications();
    });
  }

  void _initializeNotifications() {
    // Initialize push notifications in the background after the home screen has fully rendered.
    unawaited(PushNotificationService.initialize());
  }

  Future<void> _maybeShowWelcomeIntro() async {
    if (_checkedWelcomeIntro || !mounted) return;
    _checkedWelcomeIntro = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final hasSeenIntro = prefs.getBool(_welcomeIntroSeenKey) ?? false;
      if (hasSeenIntro || !mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _WelcomeIntroDialog(),
      );

      await prefs.setBool(_welcomeIntroSeenKey, true);
    } catch (_) {
      // Ignore intro persistence errors and let the app continue normally.
    }
  }

  Future<void> _checkAuth() async {
    final user = await BackendService.getCurrentUser();
    if (!mounted) return;
    if (user == null) {
      setState(() {
        _isAuthed = false;
        _avatarUrl = null;
      });
      return;
    }
    String? avatar;
    try {
      final profile = await BackendService.getProfileByUserId(user.$id);
      avatar = profile?.data['avatarUrl'] as String?;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _isAuthed = true;
      _avatarUrl = avatar;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 1100;
        return Scaffold(
          extendBody: true,
          appBar: isDesktop
              ? AppBar(
                  toolbarHeight: 64,
                  titleSpacing: 0,
                  leadingWidth: 0,
                  automaticallyImplyLeading: false,
                  leading: const SizedBox.shrink(),
                  title: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'XapZap',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Wrap(
                          spacing: 28,
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _buildNavAction(0, LucideIcons.home, null),
                            _buildNavAction(
                              1,
                              LucideIcons.messageCircle,
                              _unreadChats > 0 ? '$_unreadChats' : null,
                            ),
                            _buildNavAction(2, LucideIcons.plusSquare, null),
                            _buildNavAction(
                              3,
                              LucideIcons.bell,
                              _unreadNotifications > 0
                                  ? '$_unreadNotifications'
                                  : null,
                            ),
                            _buildNavAction(4, LucideIcons.user, null),
                          ],
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(LucideIcons.search),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SearchScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.grey.shade300,
                        backgroundImage:
                            (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                                ? NetworkImage(_avatarUrl!)
                                : null,
                        child: (_avatarUrl == null || _avatarUrl!.isEmpty)
                            ? const Icon(
                                LucideIcons.user,
                                size: 16,
                                color: Colors.black54,
                              )
                            : null,
                      ),
                    ),
                  ],
                )
              : null,
          body: NotificationListener<UserScrollNotification>(
            onNotification: (notification) {
              if (notification.direction == ScrollDirection.reverse) {
                if (_showBottomNav) {
                  setState(() {
                    _showBottomNav = false;
                  });
                }
              } else if (notification.direction == ScrollDirection.forward) {
                if (!_showBottomNav) {
                  setState(() {
                    _showBottomNav = true;
                  });
                }
              }
              return false;
            },
            child: IndexedStack(index: _currentIndex, children: _screens),
          ),
          bottomNavigationBar: isDesktop
              ? null
              : AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  height: _showBottomNav
                      ? 68.0 + MediaQuery.of(context).padding.bottom
                      : 0.0,
                  clipBehavior: Clip.hardEdge,
                  decoration: const BoxDecoration(),
                  child: Wrap(
                    children: [
                      ClipRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surface
                                  .withOpacity(0.85),
                              border: Border(
                                top: BorderSide(
                                  color: Theme.of(context).brightness ==
                                          Brightness.light
                                      ? Colors.black.withOpacity(0.08)
                                      : Colors.white.withOpacity(0.12),
                                  width: 0.8,
                                ),
                              ),
                            ),
                            child: SafeArea(
                              top: false,
                              child: SizedBox(
                                height: 68,
                                child: Stack(
                                  children: [
                                    _buildAnimatedIndicator(
                                        constraints.maxWidth),
                                    Row(
                                      children: [
                                        Expanded(
                                            child: Center(
                                                child: _buildNavItem(
                                                    0, LucideIcons.home, null))),
                                        Expanded(
                                          child: Center(
                                            child: _buildNavItem(
                                              1,
                                              LucideIcons.messageCircle,
                                              _unreadChats > 0
                                                  ? '$_unreadChats'
                                                  : null,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                            child: Center(
                                                child: _buildNavItem(2,
                                                    LucideIcons.plusSquare, null))),
                                        Expanded(
                                          child: Center(
                                            child: _buildNavItem(
                                              3,
                                              LucideIcons.bell,
                                              _unreadNotifications > 0
                                                  ? '$_unreadNotifications'
                                                  : null,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                            child: Center(
                                                child: _buildNavItem(
                                                    4, LucideIcons.user, null))),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _buildAnimatedIndicator(double barWidth) {
    final itemWidth = barWidth / 5;
    final double leftOffset;
    if (_currentIndex == 0) {
      leftOffset = 0 * itemWidth;
    } else if (_currentIndex == 1) {
      leftOffset = 1 * itemWidth;
    } else if (_currentIndex == 3) {
      leftOffset = 3 * itemWidth;
    } else if (_currentIndex == 4) {
      leftOffset = 4 * itemWidth;
    } else {
      leftOffset = 0.0;
    }

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.fastOutSlowIn,
      left: leftOffset + (itemWidth - 54) / 2,
      top: (68 - 40) / 2,
      child: Container(
        width: 54,
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String? badge) {
    final isActive = _currentIndex == index;

    if (index == 2) {
      return GestureDetector(
        onTap: () async {
          if (!_isAuthed) return;
          _showCreatePicker();
        },
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF4F46E5), Color(0xFF8B5CF6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4F46E5).withOpacity(0.35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(color: Colors.white24, width: 1.5),
          ),
          child: const Icon(
            LucideIcons.plus,
            color: Colors.white,
            size: 24,
          ),
        ),
      );
    }

    final activeColor = Theme.of(context).colorScheme.primary;
    final inactiveColor = Theme.of(context).brightness == Brightness.light
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);

    return GestureDetector(
      onTap: () async {
        if (!_isAuthed && index != 0) {
          return;
        }
        setState(() {
          _currentIndex = index;
          _showBottomNav = true;
        });
      },
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: AnimatedScale(
          scale: isActive ? 1.15 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                icon,
                size: 26,
                color: isActive ? activeColor : inactiveColor,
              ),
              if (badge != null)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.surface,
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavAction(int index, IconData icon, String? badge) {
    final isActive = _currentIndex == index;
    final activeColor = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            iconSize: 26,
            icon: Icon(icon, color: isActive ? activeColor : null),
            onPressed: () async {
              if (!_isAuthed && index != 0) {
                return;
              }
              if (index == 2) {
                if (!_isAuthed) return;
                _showCreatePicker();
              } else {
                setState(() => _currentIndex = index);
              }
            },
          ),
          if (badge != null)
            Positioned(
              right: 4,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                constraints: const BoxConstraints(
                  minWidth: 16,
                  minHeight: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    badge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showCreatePicker() {
    showModalBottomSheet<UploadType>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const Text(
                'Create',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(LucideIcons.image),
                title: const Text(
                  'Image / Text',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () => Navigator.of(ctx).pop(UploadType.standard),
              ),
              ListTile(
                leading: const Icon(LucideIcons.video),
                title: const Text(
                  'Video',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () => Navigator.of(ctx).pop(UploadType.video),
              ),
              ListTile(
                leading: const Icon(LucideIcons.playCircle),
                title: const Text(
                  'Reel',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () => Navigator.of(ctx).pop(UploadType.reel),
              ),
              ListTile(
                leading: const Icon(LucideIcons.clapperboard),
                title: const Text(
                  'Episode',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  'Upload a reel episode or video episode',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                  ),
                ),
                onTap: () => Navigator.of(ctx).pop(UploadType.episode),
              ),
              ListTile(
                leading: const Icon(LucideIcons.newspaper),
                title: const Text(
                  'News / Blog',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () => Navigator.of(ctx).pop(UploadType.news),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ).then((type) {
      if (type == null) return;
      if (!mounted) return;
      if (type == UploadType.video || type == UploadType.reel) {
        _openVideoUpload(type);
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => UploadScreen(type: type)),
      );
    });
  }

  Future<void> _openVideoUpload(UploadType type) async {
    final video = await _picker.pickVideo(source: ImageSource.gallery);
    if (!mounted || video == null) return;
    final navigator = Navigator.of(context);
    navigator.push(
      MaterialPageRoute(
        builder: (_) => UploadScreen(
          type: type,
          initialVideo: video,
        ),
      ),
    );
  }

  Future<void> _loadBadges() async {
    final user = await BackendService.getCurrentUser();
    if (user == null) return;
    try {
      final chats = await BackendService.fetchChatsForUser(user.$id);
      int unreadChatCount = 0;
      for (final chatRow in chats.rows) {
        final chatId = chatRow.$id;
        final cached = ChatMessageCache.get(chatId);
        if (cached != null) {
          final unreadInChat = cached.messages
              .where((m) => !m.isSent && !m.isRead)
              .length;
          if (unreadInChat > 0) {
            unreadChatCount++;
          }
        } else {
          final msgs = await BackendService.fetchMessagesForChat(
            chatId,
            limit: 10,
          );
          final unreadMessages = msgs.rows.where((row) {
            final data = row.data;
            final senderId = (data['senderId'] as String?) ?? '';
            if (senderId == user.$id) return false;
            final readBy = data['readBy'] is List
                ? (data['readBy'] as List).map((e) => e.toString().trim())
                : ((data['readBy'] as String?) ?? '').split(',').map((e) => e.trim());
            return !readBy.contains(user.$id);
          });
          if (unreadMessages.isNotEmpty) {
            unreadChatCount++;
          }
        }
      }
      final notifs = await BackendService.fetchNotifications(
        user.$id,
        limit: 50,
      );
      if (!mounted) return;
      setState(() {
        _unreadChats = unreadChatCount.clamp(0, 99);
        _unreadNotifications = notifs.length.clamp(0, 99);
      });
    } catch (_) {
      // ignore failures
    }
  }

  void _subscribeBadges() {
    try {
      final channelMessages =
          'databases.${BackendService.databaseId}.collections.${BackendService.messagesCollectionId}.documents';
      final channelNotifs =
          'databases.${BackendService.databaseId}.collections.${BackendService.notificationsCollectionId}.documents';
      _badgeSub = BackendService.realtime.subscribe([
        channelMessages,
        channelNotifs,
      ]);
      _badgeSub?.stream.listen((event) async {
        if (!mounted) return;
        if (event.events.isEmpty) return;
        final name = event.events.first;
        final payload = event.payload;
        if (name.contains('.create') || name.contains('.update')) {
          final chatId = (payload['chatId'] as String?)?.trim() ?? '';
          if (chatId.isNotEmpty) {
            final senderId = (payload['senderId'] as String?) ?? '';
            final user = await BackendService.getCurrentUser();
            if (user != null) {
              final readBy = payload['readBy'] is List
                  ? (payload['readBy'] as List).map((e) => e.toString().trim()).toList()
                  : ((payload['readBy'] as String?) ?? '').split(',').map((e) => e.trim()).toList();
              final timestampStr = payload['timestamp'] as String? ?? payload['createdAt'] as String? ?? '';
              final timestamp = DateTime.tryParse(timestampStr) ?? DateTime.now();
              
              final isSent = senderId == user.$id;
              final isRead = readBy.contains(user.$id);
              
              final msg = Message(
                id: payload['\$id'] as String? ?? '',
                content: (payload['content'] as String?) ?? '',
                mediaUrl: payload['mediaUrl'] as String?,
                thumbnailUrl: payload['thumbnailUrl'] as String?,
                mediaType: payload['mediaType'] as String?,
                timestamp: timestamp,
                isSent: isSent,
                isRead: isRead,
                deliveryStatus: MessageDeliveryStatusX.fromRaw(
                  payload['deliveryStatus'],
                  isRead: isRead,
                  isSent: isSent,
                ),
              );
              ChatMessageCache.addOrUpdateMessage(chatId, msg);
            }
          }
        }
        await _loadBadges();
      });
    } catch (_) {}
  }

  void _subscribeBanWatcher() async {
    try {
      final user = await BackendService.getCurrentUser();
      if (user == null) return;
      final channelProfile =
          'databases.${BackendService.databaseId}.collections.${BackendService.profilesCollectionId}.documents.${user.$id}';
      _banSub = BackendService.realtime.subscribe([channelProfile]);
      _banSub?.stream.listen((event) async {
        if (!mounted || _banHandled) return;
        // Any change to the profile should re-check ban status.
        final banned = await BackendService.isUserBanned(user.$id);
        if (!banned) return;
        _banHandled = true;
        try {
          await BackendService.signOut();
        } catch (_) {}
        if (!mounted) return;
        // Kick the user out of the app and show banned screen.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const BannedScreen()),
          (route) => false,
        );
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _badgeSub?.close();
    _banSub?.close();
    super.dispose();
  }
}

class _WelcomeIntroDialog extends StatefulWidget {
  const _WelcomeIntroDialog();

  @override
  State<_WelcomeIntroDialog> createState() => _WelcomeIntroDialogState();
}

class _WelcomeIntroDialogState extends State<_WelcomeIntroDialog> {
  final PageController _pageController = PageController();
  int _pageIndex = 0;

  static const List<_WelcomePageData> _pages = [
    _WelcomePageData(
      icon: LucideIcons.checkSquare,
      title: 'Micro Jobs',
      body: 'Complete simple tasks like watching videos or reviewing the app, and get rewarded instantly.',
      bullets: [
        'Repeatable Video Tasks: Earn \$0.02 - \$0.05 per video watch',
        'App Review Reward: Earn \$0.20 for reviewing the app',
        'Instant Pay: Earn directly into your balance immediately',
        'Unlimited Tasks: Complete as many video watches as you want',
      ],
    ),
    _WelcomePageData(
      icon: LucideIcons.flame,
      title: 'Creators Earn Daily',
      body: 'Unlike traditional social platforms, XapZap rewards you from day one. '
          'Post videos, reels, stories, or images, and start generating earnings immediately.',
      bullets: [
        'Instant Monetization: No follower minimums to start earning',
        'Daily Cashouts: Your balance updates daily for easy withdrawals',
        'Upload Anything: Share videos, reels, stories, or news',
        'Creator-First Split: Earn directly from ad views on your posts',
      ],
    ),
    _WelcomePageData(
      icon: LucideIcons.users,
      title: 'Lifetime 10% Referrals',
      body: 'Invite other creators to join XapZap and build your passive income stream.',
      bullets: [
        'Share your personal invite link with friends',
        'Earn a lifetime 10% bonus from the earnings of the people you referred',
        'Track your referred users and watch combined earnings grow',
      ],
    ),
    _WelcomePageData(
      icon: LucideIcons.wallet,
      title: 'Monetization Made Easy',
      body: 'Every view on your posts generates real value. Watch your balance grow '
          'transparently as people interact with your content.',
      bullets: [
        'Transparent ad revenue sharing model',
        'Simple, automated revenue sync directly to your wallet',
        'Earn from views, likes, and general post engagement',
      ],
    ),
    _WelcomePageData(
      icon: LucideIcons.rocket,
      title: 'Organic Reach & Growth',
      body: 'Our advanced batch distribution algorithms ensure new creators get seen '
          'and build their audience without paywalls.',
      bullets: [
        'Built to help new creators gain visibility organically',
        'Jittered algorithm ensures all posts get fair initial views',
        'Post consistently to grow your reach and maximize earnings',
      ],
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _next() async {
    if (_pageIndex >= _pages.length - 1) {
      await _finish();
      return;
    }

    await _pageController.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primary.withOpacity(0.12),
              colorScheme.surface,
              const Color(0xFFFFC857).withOpacity(0.10),
            ],
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Welcome to XapZap',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: _finish,
                  child: const Text('Skip'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) {
                  setState(() => _pageIndex = index);
                },
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            page.icon,
                            color: colorScheme.primary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          page.title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          page.body,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                        ),
                        const SizedBox(height: 18),
                        ...page.bullets.map(
                          (bullet) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 3),
                                  child: Icon(
                                    LucideIcons.sparkles,
                                    size: 16,
                                    color: Color(0xFF29ABE2),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    bullet,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ...List.generate(
                  _pages.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    width: _pageIndex == index ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _pageIndex == index
                          ? colorScheme.primary
                          : colorScheme.primary.withOpacity(0.24),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _next,
                  child: Text(
                    _pageIndex == _pages.length - 1
                        ? 'Start exploring'
                        : 'Next',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomePageData {
  final IconData icon;
  final String title;
  final String body;
  final List<String> bullets;

  const _WelcomePageData({
    required this.icon,
    required this.title,
    required this.body,
    required this.bullets,
  });
}
