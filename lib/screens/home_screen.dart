import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:appwrite/models.dart' as aw;
import 'package:appwrite/appwrite.dart' show RealtimeSubscription;
import '../models/post.dart';
import '../models/news_article.dart';
import '../services/appwrite_service.dart';
import '../services/feed_exposure_service.dart';
import '../services/storage_service.dart';
import '../services/feed_cache.dart';
import '../widgets/post_card.dart';
import '../widgets/reel_player.dart';
import '../widgets/watch_video_card.dart';
import '../widgets/guest_prompt.dart';
import '../models/status.dart';
import '../models/story.dart';
import '../services/story_manager.dart';
import '../widgets/story_avatar.dart';
import '../widgets/keep_alive_tab.dart';
import '../widgets/home_feed_ad_widgets.dart';
import '../services/avatar_cache.dart';
import '../services/native_ad_preload_service.dart';
import '../services/rewarded_ad_preload_service.dart';
import '../services/device_mode_service.dart';
import '../services/push_notification_service.dart';
import '../services/home_feed_batch_layout.dart';
import '../services/video_cache_service.dart';
import 'story_publish_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'search_screen.dart';
import 'post_detail_screen.dart';
import 'video_detail_screen.dart';
import 'status_viewer_screen.dart';
import '../widgets/pending_upload_banner.dart';
import '../widgets/shimmer_loading.dart';
import '../services/pending_upload_service.dart';
import 'live_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  static const String _feedSessionSeedKey = 'feed_session_seed_v1';
  static const int _reelPrefetchAheadCount = 2;
  final List<Post> _forYouPosts = FeedCache.forYouPosts;
  final List<Post> _followingPosts = FeedCache.followingPosts;
  final List<Post> _watchPosts = [];
  final List<Post> _reelsPosts = [];
  final Map<String, List<String>> _mediaByPostId = FeedCache.mediaByPostId;
  final Map<String, String> _authorByPostId = FeedCache.authorByPostId;
  final List<NewsArticle> _newsArticles = [];
  final List<Story> _stories = [];
  final List<StatusUpdate> _statusUpdates = [];
  final ScrollController _forYouController = ScrollController();
  final ScrollController _followingController = ScrollController();
  final ScrollController _watchController = ScrollController();
  final ScrollController _newsController = ScrollController();
  RealtimeSubscription? _postsSub;
  bool _monetizedAccepted = false;
  late TabController _tabController;
  bool _isLoading = false;
  bool _isLoadingNews = false;
  bool _hasMoreNews = true;
  bool _isGuest = true;
  String? _currentUserId;
  String? _forYouCursor = FeedCache.forYouCursor;
  String? _followingCursor = FeedCache.followingCursor;
  String? _watchCursor;
  String? _reelsCursor;
  String? _newsCursor;
  List<String> _followingIds = [];
  int _activeReelIndex = 0;
  final Set<String> _seenForYouIds = <String>{};
  final Set<String> _seenFollowingIds = <String>{};
  final Set<String> _seenWatchIds = <String>{};
  final Set<String> _seenReelIds = <String>{};
  final List<Post> _pendingForYouPosts = <Post>[];
  final List<Post> _pendingFollowingPosts = <Post>[];
  final List<List<bool>> _forYouBatchAdStates = <List<bool>>[];
  final List<List<bool>> _followingBatchAdStates = <List<bool>>[];
  final List<List<bool>> _watchBatchAdStates = <List<bool>>[];
  int _feedRefreshSeed = 0;
  late final VoidCallback _storiesListener;
  late final VoidCallback _publishedUploadListener;
  final ImagePicker _storyPicker = ImagePicker();
  bool _isLoadingWatch = false;
  bool _isLoadingReels = false;
  bool _feedsReadyForFirstPaint = false;

  bool get _enableFeedAds => !kIsWeb && !DeviceModeService.isTv;
  bool get _isTvMode => DeviceModeService.isTv;

  @override
  void initState() {
    super.initState();
    _checkUser();
    _tabController = TabController(length: 6, vsync: this);
    StoryManager.init();
    _storiesListener = _syncStories;
    StoryManager.stories.addListener(_storiesListener);
    _publishedUploadListener = () {
      if (!mounted) return;
      final publishedPostId = PendingUploadService.publishedPostId.value;
      if (publishedPostId != null && publishedPostId.isNotEmpty) {
        unawaited(_promotePublishedPostToTop(publishedPostId));
      }
      unawaited(_queueNewPostsForFeed(true));
      unawaited(_queueNewPostsForFeed(false));
    };
    PendingUploadService.publishedPostId.addListener(_publishedUploadListener);
    PendingUploadService.publishedVersion.addListener(_publishedUploadListener);
    _syncStories();
    StoryManager.loadFromServer();
    _seenForYouIds.addAll(_forYouPosts.map((post) => post.id));
    _seenFollowingIds.addAll(_followingPosts.map((post) => post.id));
    _seenWatchIds.addAll(_watchPosts.map((post) => post.id));
    _seenReelIds.addAll(_reelsPosts.map((post) => post.id));
    _syncBatchAdStates(_forYouPosts, _forYouBatchAdStates);
    _syncBatchAdStates(_followingPosts, _followingBatchAdStates);
    _newsController.addListener(_onNewsScroll);
    _bootstrapFeeds();
    _subscribePostsRealtime();
  }

  Future<void> _bootstrapFeeds() async {
    await _advanceFeedSessionSeed();
    if (!mounted) return;

    if (mounted) {
      setState(() => _feedsReadyForFirstPaint = true);
    }

    _loadInitialNews();
    unawaited(_primeNativeFeedAds(maxSlotIndex: 2));
    await _refreshFeed(true);
    unawaited(_prefetchFirstBatch());
    unawaited(_refreshFeed(false));

    if (!kIsWeb && !DeviceModeService.isTv) {
      unawaited(RewardedAdPreloadService.warmup());
    }
  }

  /// Pre-warm the first 8 For You posts so card data is in cache before the
  /// user scrolls. This mirrors how major social apps pre-resolve avatars,
  /// display names, and like state so each card renders instantly.
  Future<void> _prefetchFirstBatch() async {
    final user = await AppwriteService.getCurrentUser();
    final posts = _forYouPosts.take(8).toList();
    if (posts.isEmpty) return;

    final authorIds = posts
        .map((p) => _authorByPostId[p.id] ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    // 1. Warm profile cache (display name + avatar) for each unique author.
    final profileFutures = authorIds
        .map((id) => AppwriteService.getProfileByUserId(id).then((prof) async {
              if (prof == null) return;
              final rawAvatar = (prof.data['avatarUrl'] as String?)?.trim() ?? '';
              if (rawAvatar.isNotEmpty) {
                final url = StorageService.getImageDisplayUrlSync(rawAvatar);
                AvatarCache.setForUserId(id, url);
              }
            }).catchError((_) {}));

    // 2. Warm per-post like status for signed-in users.
    final stateFutures = user == null
        ? <Future<void>>[]
        : posts.map((post) async {
            try {
              final liked = await AppwriteService.isPostLikedBy(user.$id, post.id);
              // Cache the result into the static like map that PostCard reads.
              if (liked) PostCard.primePostLikedCache(post.id, liked);
            } catch (_) {}
          }).toList();

    await Future.wait([...profileFutures, ...stateFutures]);
  }


  Future<void> _advanceFeedSessionSeed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final previousSeed = prefs.getInt(_feedSessionSeedKey) ??
          DateTime.now().millisecondsSinceEpoch;
      final nextSeed = previousSeed + 1;
      await prefs.setInt(_feedSessionSeedKey, nextSeed);
      if (!mounted) return;
      setState(() => _feedRefreshSeed = nextSeed);
    } catch (_) {
      if (!mounted) return;
      setState(() => _feedRefreshSeed = DateTime.now().millisecondsSinceEpoch);
    }
  }

  Future<void> _bumpRefreshSeed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nextSeed = (_feedRefreshSeed == 0
              ? prefs.getInt(_feedSessionSeedKey) ??
                  DateTime.now().millisecondsSinceEpoch
              : _feedRefreshSeed) +
          1;
      await prefs.setInt(_feedSessionSeedKey, nextSeed);
      if (!mounted) return;
      setState(() => _feedRefreshSeed = nextSeed);
    } catch (_) {
      if (!mounted) return;
      setState(() => _feedRefreshSeed += 1);
    }
  }

  int _batchItemCount(int postCount, {required bool includeLoading}) {
    return HomeFeedBatchLayout.batchItemCount(
      postCount,
      enableFeedAds: false,
      includeLoading: includeLoading,
    );
  }

  bool _canShowBatchAds(int postCount) {
    return false;
  }

  bool _isBatchAdRow(int rowIndex, int postCount) {
    return HomeFeedBatchLayout.isBatchAdRow(rowIndex, postCount);
  }

  int _batchAdSlotForRow(int rowIndex) {
    return HomeFeedBatchLayout.batchAdSlotForRow(rowIndex);
  }

  int _batchPostIndexForRow(int rowIndex, int postCount) {
    return HomeFeedBatchLayout.batchPostIndexForRow(rowIndex, postCount);
  }

  // ignore: unused_element
  bool _batchAdVisible(
    List<List<bool>> batchStates,
    int rowIndex,
  ) {
    final batchIndex = rowIndex ~/ 8;
    if (batchIndex >= batchStates.length) return false;
    final slotIndex = switch (rowIndex % 8) {
      1 => 0,
      4 => 1,
      7 => 2,
      _ => -1,
    };
    if (slotIndex < 0) return false;
    return batchStates[batchIndex][slotIndex];
  }

  void _syncBatchAdStates(
    List<Post> posts,
    List<List<bool>> batchStates,
  ) {
    final batchCount = posts.length ~/ 5;
    if (batchStates.length >= batchCount) return;
    for (var batchIndex = batchStates.length;
        batchIndex < batchCount;
        batchIndex++) {
      final slotBase = batchIndex * 3;
      batchStates.add(<bool>[
        NativeAdPreloadService.isLoaded(slotBase),
        NativeAdPreloadService.isLoaded(slotBase + 1),
        NativeAdPreloadService.isLoaded(slotBase + 2),
      ]);
    }
  }

  Future<void> _primeNativeFeedAds({int maxSlotIndex = 2}) async {
    if (!_enableFeedAds || kIsWeb) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        NativeAdPreloadService.warmupFast(maxSlotIndex: maxSlotIndex),
      );
    });
  }

  Future<void> _checkUser() async {
    // 1. Immediately sync details from memory/disk cache for instant rendering
    final syncUser = AppwriteService.getCurrentUserSync();
    if (syncUser != null) {
      _isGuest = false;
      _currentUserId = syncUser.$id;
      final cachedAvatar = AvatarCache.getForUserId(syncUser.$id);
      String displayName = '';
      final cachedProfile = AppwriteService.getCachedProfileByUserId(syncUser.$id);
      if (cachedProfile != null) {
        displayName = (cachedProfile.data['displayName'] as String?)?.trim() ?? '';
      }
      StoryManager.updateMyProfile(
        userAvatar: cachedAvatar ?? '',
        username: displayName,
      );
    }

    // 2. Perform async refresh in background
    final user = await AppwriteService.getCurrentUser();
    if (!mounted) return;
    setState(() {
      _isGuest = user == null;
      _currentUserId = user?.$id;
    });
    if (user != null) {
      unawaited(PushNotificationService.maybeRequestNotificationPermissionOnLaunch());
      _followingIds = await AppwriteService.getFollowingUserIds(user.$id);
      // listen for follow/unfollow changes
      AppwriteService.followingVersion.addListener(() async {
        final me = await AppwriteService.getCurrentUser();
        if (me != null && mounted) {
          _followingIds = await AppwriteService.getFollowingUserIds(me.$id);
          await _refreshFeed(false);
        }
      });
      if (_followingIds.isNotEmpty && _followingPosts.isEmpty) {
        await _refreshFeed(false);
      }

      // Update current user's story avatar, preferring persistent cache
      // so it does not refresh on navigation.
      try {
        String? avatar = AvatarCache.getForUserId(user.$id);
        if (avatar == null) {
          final prof = await AppwriteService.getProfileByUserId(user.$id);
          final raw = prof?.data['avatarUrl'] as String?;
          if (raw != null && raw.isNotEmpty) {
            if (raw.startsWith('http://') || raw.startsWith('https://')) {
              avatar = raw;
            } else {
              try {
                avatar = await StorageService.getSignedUrl(raw);
              } catch (_) {
                avatar = raw;
              }
            }
            await AvatarCache.setForUserId(user.$id, avatar);
          }
        }
        String displayName = '';
        final prof = await AppwriteService.getProfileByUserId(user.$id);
        if (prof != null) {
          final data = prof.data;
          final rawName = (data['displayName'] as String?)?.trim();
          displayName = rawName?.isNotEmpty == true ? rawName! : '';
        }
        StoryManager.updateMyProfile(
          userAvatar: avatar ?? '',
          username: displayName,
        );
      } catch (_) {}
    }
  }

  void _syncStories() {
    final values = StoryManager.stories.value;
    void applySync() {
      _statusUpdates
        ..clear()
        ..addAll(values);

      final meList = values.where((status) => status.id == 'me').toList();
      final otherList = values.where((status) => status.id != 'me').toList();

      // Sort: unviewed first, viewed last
      otherList.sort((a, b) {
        if (a.isViewed != b.isViewed) {
          return a.isViewed ? 1 : -1;
        }
        return 0;
      });

      final sortedList = [...meList, ...otherList];

      _stories
        ..clear()
        ..addAll(
          sortedList.map(
            (status) => Story(
              id: status.id,
              username: status.username,
              imageUrl: status.mediaUrls.isNotEmpty
                  ? status.mediaUrls.first
                  : status.userAvatar,
              isViewed: status.isViewed,
              isUploading: status.isUploading,
              hasActiveStories: status.mediaUrls.isNotEmpty || status.isUploading,
            ),
          ),
        );
    }

    if (!mounted) {
      applySync();
      return;
    }
    setState(applySync);
  }

  void _subscribePostsRealtime() {
    final channel =
        'databases.${AppwriteService.databaseId}.collections.${AppwriteService.postsCollectionId}.documents';
    try {
      _postsSub = AppwriteService.realtime.subscribe([channel]);
      _postsSub?.stream.listen((event) async {
        if (!mounted) return;
        if (event.events.isEmpty) return;
        final name = event.events.first;
        final payload = event.payload;
        final payloadUserId = payload['userId']?.toString() ?? '';
        final isOwnPost = _currentUserId != null &&
            _currentUserId!.isNotEmpty &&
            payloadUserId == _currentUserId;
        if (name.contains('.create')) {
          if (isOwnPost) {
            final createdPost = await _mapRealtimePayloadToPost(payload);
            if (createdPost != null) {
              _insertPostAtTop(createdPost, true);
            }
          }
          await Future.wait([
            _queueNewPostsForFeed(true),
            _queueNewPostsForFeed(false),
          ]);
          if (isOwnPost) {
            await _applyPendingNewPosts(true);
          }
          return;
        }
        if (name.contains('.delete')) {
          await _refreshFeed(true);
          await _refreshFeed(false);
        }
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final onSurface = theme.colorScheme.onSurface;
        final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;

        // Treat as desktop layout only on wide screens; narrow web should use
        // the same mobile layout as the native app.
        if (constraints.maxWidth > 1100) {
          return _buildDesktopScaffold(theme, onSurface, onSurfaceVariant);
        }
        return _buildMobileScaffold(theme, onSurface, onSurfaceVariant);
      },
    );
  }

  Widget _buildMobileScaffold(
    ThemeData theme,
    Color onSurface,
    Color onSurfaceVariant,
  ) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: theme.colorScheme.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 40,
        title: const Text(
          'XapZap',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1DA1F2),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: Icon(Icons.search, color: onSurface, size: 24),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const SearchScreen(),
                  ),
                );
              },
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelPadding: const EdgeInsets.symmetric(horizontal: 14),
            labelColor: onSurface,
            unselectedLabelColor: onSurfaceVariant,
            indicatorColor: onSurface,
            onTap: _handleTabTap,
            tabs: const [
              Tab(text: 'For You', height: 36),
              Tab(text: 'Watch', height: 36),
              Tab(text: 'Reels', height: 36),
              Tab(text: 'Live', height: 36),
              Tab(text: 'News', height: 36),
              Tab(text: 'Following', height: 36),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _buildTabViews(),
      ),
    );
  }

  Widget _buildDesktopScaffold(
    ThemeData theme,
    Color onSurface,
    Color onSurfaceVariant,
  ) {
    final bool isWatchTab = _tabController.index == 1;
    final bool isReelsTab = _tabController.index == 2;
    final bool isLiveTab = _tabController.index == 3;
    final bool isCompactNav = isWatchTab || isReelsTab || isLiveTab;
    return Scaffold(
      // Header is rendered by MainScreen on desktop.
      body: Row(
        children: [
          SizedBox(
            width: isCompactNav ? 72 : 260,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
              children: [
                const SizedBox(height: 4),
                _buildSideNavItem(
                  Icons.home_filled,
                  'For You',
                  0,
                  compact: isCompactNav,
                ),
                _buildSideNavItem(
                  Icons.ondemand_video_outlined,
                  'Watch',
                  1,
                  compact: isCompactNav,
                ),
                _buildSideNavItem(
                  Icons.video_library_outlined,
                  'Reels',
                  2,
                  compact: isCompactNav,
                ),
                _buildSideNavItem(
                  Icons.wifi_tethering,
                  'Live',
                  3,
                  compact: isCompactNav,
                ),
                _buildSideNavItem(
                  Icons.article_outlined,
                  'News',
                  4,
                  compact: isCompactNav,
                ),
                _buildSideNavItem(
                  Icons.groups_outlined,
                  'Following',
                  5,
                  compact: isCompactNav,
                ),
              ],
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  // On Watch tab, keep feed fairly wide; for other tabs
                  // (For You, Reels, etc.) cap width so content stays tight.
                  maxWidth: isWatchTab ? 1200 : 960,
                ),
                child: TabBarView(
                  controller: _tabController,
                  children: _buildTabViews(),
                ),
              ),
            ),
          ),
          if (!isWatchTab)
            SizedBox(width: 260, child: _buildRightSidebar(theme)),
        ],
      ),
    );
  }

  Widget _buildSideNavItem(
    IconData icon,
    String label,
    int tabIndex, {
    VoidCallback? onTap,
    bool compact = false,
  }) {
    final isSelected = tabIndex >= 0 && _tabController.index == tabIndex;
    if (compact) {
      return IconButton(
        tooltip: label,
        icon: Icon(
          icon,
          color: isSelected ? const Color(0xFF1DA1F2) : null,
        ),
        onPressed: () {
          if (onTap != null) {
            onTap();
            return;
          }
          if (tabIndex >= 0) {
            _handleTabTap(tabIndex);
            setState(() => _tabController.index = tabIndex);
          }
        },
      );
    }
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      leading: Icon(icon, color: isSelected ? const Color(0xFF1DA1F2) : null),
      title: Text(label),
      selected: isSelected,
      onTap: () {
        if (onTap != null) {
          onTap();
          return;
        }
        if (tabIndex >= 0) {
          _handleTabTap(tabIndex);
          setState(() => _tabController.index = tabIndex);
        }
      },
    );
  }

  Widget _buildRightSidebar(ThemeData theme) {
    // Right sidebar previously showed static mock data (trending tags,
    // notifications, chats). Hide it until backed by real data.
    return const SizedBox.shrink();
  }

  List<Widget> _buildTabViews() {
    return [
      KeepAliveTab(
        builder: (_) => _buildFeed(_forYouPosts, _forYouController, true),
      ),
      _buildWatchTab(),
      _buildReelsTab(),
      KeepAliveTab(builder: (_) => _buildLiveTab()),
      KeepAliveTab(builder: (_) => _buildNewsTab()),
      KeepAliveTab(
        builder: (_) =>
            _buildFeed(_followingPosts, _followingController, false),
      ),
    ];
  }

  Future<void> _handleTabTap(int index) async {
    if (index == 1 || index == 2) {
      final ok = await _ensureMonetizedConsent();
      if (!ok) {
        // Force back to For You tab on cancel.
        _tabController.index = 0;
        setState(() {});
        return;
      }
      if (index == 1 && _watchPosts.isEmpty && !_isLoadingWatch) {
        await _refreshWatchFeed();
      }
      if (index == 2 && _reelsPosts.isEmpty && !_isLoadingReels) {
        await _refreshReelsFeed();
      }
    }
    setState(() {});
  }

  Future<bool> _ensureMonetizedConsent() async {
    if (_monetizedAccepted) return true;
    if (!mounted) return false;
    final theme = Theme.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          title: const Text('Monetized videos'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'All videos in this section are monetized. Watching short ads unlocks each video feed.',
              ),
              SizedBox(height: 8),
              Text('Part of the ad revenue supports video creators.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Accept & Continue'),
            ),
          ],
        );
      },
    );
    if (result == true) {
      _monetizedAccepted = true;
      return true;
    }
    return false;
  }

  Widget _buildWatchTab() {
    return _buildVideoList(_watchPosts);
  }

  Widget _buildLiveTab() {
    return LiveScreen(isGuest: _isGuest);
  }

  bool _isVideoPost(Post post) {
    final postType = post.postType?.toLowerCase() ?? '';
    if (postType.contains('video') || postType.contains('reel')) return true;
    if (post.videoUrl != null) return true;
    final media = _mediaByPostId[post.id] ?? const <String>[];
    return media.any(_isVideoUrl);
  }

  bool _isVideoUrl(String url) {
    final uri = Uri.tryParse(url);
    final lower = uri?.queryParameters['filename']?.toLowerCase() ??
        uri?.queryParameters['path']?.toLowerCase() ??
        url.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm');
  }

  bool _isReelPost(Post post) {
    final postType = post.postType?.toLowerCase();
    if (postType == null) return false;
    // Treat posts marked as reel/short as vertical reels.
    return postType.contains('reel') || postType.contains('short');
  }

  Widget _buildReelsTab() {
    return _buildReelsFeed(_reelsPosts);
  }

  Widget _buildNewsTab() {
    return RefreshIndicator(
      onRefresh: _refreshNews,
      child: ListView.builder(
        controller: _newsController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: EdgeInsets.zero,
        itemCount: _newsArticles.isEmpty && !_isLoadingNews
            ? 1
            : _newsArticles.length + (_isLoadingNews ? 1 : 0),
        itemBuilder: (context, index) {
          if (_newsArticles.isEmpty && !_isLoadingNews) {
            return const SizedBox(
              height: 200,
              child:
                  Center(child: Text('No news articles yet. Pull to refresh')),
            );
          }
          if (index >= _newsArticles.length) {
            return _isLoadingNews
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF1DA1F2),
                      ),
                    ),
                  )
                : const SizedBox.shrink();
          }
          final article = _newsArticles[index];
          return _buildNewsCard(article);
        },
      ),
    );
  }

  Future<void> _loadInitialNews() async {
    _newsArticles.clear();
    _newsCursor = null;
    _hasMoreNews = true;
    await _loadMoreNews();
  }

  Future<void> _refreshNews() async {
    _newsArticles.clear();
    _newsCursor = null;
    _hasMoreNews = true;
    await _loadMoreNews();
  }

  void _onNewsScroll() {
    if (!_hasMoreNews || _isLoadingNews) return;
    if (!_newsController.hasClients) return;
    final position = _newsController.position;
    if (position.pixels >= position.maxScrollExtent - 600) {
      _loadMoreNews();
    }
  }

  Future<void> _loadMoreNews() async {
    if (_isLoadingNews || !_hasMoreNews) return;
    setState(() => _isLoadingNews = true);
    try {
      final aw.RowList list = await AppwriteService.fetchNewsArticles(
        limit: 20,
        cursorId: _newsCursor,
      );
      final rows = list.rows;
      if (rows.isEmpty) {
        _hasMoreNews = false;
        return;
      }
      for (final row in rows) {
        final data = row.data;
        final List<String> tags = data['tags'] is List
            ? (data['tags'] as List).map((e) => e.toString()).toList()
            : <String>[];
        final List<String> imageUrls = data['imageUrls'] is List
            ? (data['imageUrls'] as List).map((e) => e.toString()).toList()
            : <String>[];
        String? thumbnail;
        final rawThumb1 = data['thumbnailUrl'];
        if (rawThumb1 is String && rawThumb1.isNotEmpty) {
          thumbnail = rawThumb1;
        } else {
          final rawThumb2 = data['thumbnailUr'];
          if (rawThumb2 is String && rawThumb2.isNotEmpty) {
            thumbnail = rawThumb2;
          }
        }
        final createdAt = DateTime.tryParse(row.$createdAt) ??
            (data['publishedAt'] is String
                ? DateTime.tryParse(data['publishedAt'] as String)
                : null) ??
            DateTime.now();
        _newsArticles.add(
          NewsArticle(
            id: row.$id,
            title: data['title'] as String? ?? '',
            subtitle: data['subtitle'] as String?,
            content: data['content'] as String? ?? '',
            summary: data['summary'] as String?,
            category: data['category'] as String?,
            tags: tags,
            topic: data['topic'] as String?,
            thumbnailUrl: thumbnail,
            imageUrls: imageUrls,
            language: data['language'] as String? ?? 'en',
            sourceType: data['sourceType'] as String? ?? 'user',
            aiGenerated: data['aiGenerated'] as bool? ?? false,
            createdAt: createdAt,
          ),
        );
      }
      _newsCursor = rows.last.$id;
    } catch (_) {
      // Ignore errors for now; UI will just stop loading more.
    } finally {
      if (mounted) {
        setState(() => _isLoadingNews = false);
      }
    }
  }

  String _formatNewsTimestamp(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final difference = now.difference(local);
    if (difference.inMinutes < 60) {
      final m = difference.inMinutes.clamp(1, 59);
      return '${m}m ago';
    }
    if (difference.inHours < 24) {
      final h = difference.inHours;
      return '${h}h ago';
    }
    if (difference.inDays < 7) {
      final d = difference.inDays;
      return '${d}d ago';
    }
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
  }

  Widget _buildNewsCard(NewsArticle article) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
    final isAi = article.aiGenerated;

    String? thumb = article.thumbnailUrl ??
        (article.imageUrls.isNotEmpty ? article.imageUrls.first : null);
    if ((thumb ?? '').contains('b-cdn.net')) {
      thumb = null;
    }

    final timestampLabel = _formatNewsTimestamp(article.createdAt);
    final primaryTag = article.tags.isNotEmpty ? article.tags.first : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: theme.colorScheme.surface,
            builder: (ctx) {
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          article.title,
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                        ),
                        if (article.subtitle != null &&
                            article.subtitle!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              article.subtitle!,
                              style: textTheme.titleSmall?.copyWith(
                                color: onSurfaceVariant,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (article.category != null &&
                                article.category!.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary
                                      .withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  article.category!,
                                  style: textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            if (article.category != null &&
                                article.category!.isNotEmpty)
                              const SizedBox(width: 8),
                            Text(
                              '${article.language.toUpperCase()} • $timestampLabel',
                              style: textTheme.labelSmall?.copyWith(
                                color: onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            if (isAi)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.secondary
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'AI',
                                  style: textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.secondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (thumb != null && thumb.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: Image.network(
                                thumb,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        if (thumb != null && thumb.isNotEmpty)
                          const SizedBox(height: 12),
                        Text(
                          article.content,
                          style: textTheme.bodyMedium?.copyWith(
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (article.category != null &&
                            article.category!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  theme.colorScheme.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              article.category!,
                              style: textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        const Spacer(),
                        Text(
                          '${article.language.toUpperCase()} • $timestampLabel',
                          style: textTheme.labelSmall?.copyWith(
                            color: onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      article.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    if (article.summary != null && article.summary!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          article.summary!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (primaryTag != null && primaryTag.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '#$primaryTag',
                              style: textTheme.labelSmall?.copyWith(
                                color: onSurfaceVariant,
                              ),
                            ),
                          ),
                        const Spacer(),
                        if (isAi)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  theme.colorScheme.secondary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'AI generated',
                              style: textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (thumb != null && thumb.isNotEmpty) ...[
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 10,
                    child: Image.network(
                      thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const SizedBox(width: 0, height: 0),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostCard(
    Post post,
    List<String>? media, {
    bool countVideoImpressions = false,
  }) {
    final isVideo = _isVideoPost(post);
    final isReel = _isReelPost(post);
    final card = PostCard(
      key: ValueKey(post.id),
      post: post,
      isGuest: _isGuest,
      onGuestAction: _showGuestPrompt,
      mediaUrls: media,
      authorId: _authorByPostId[post.id],
      showReelBadge: isReel,
      // Count feed impressions for regular posts everywhere, and for videos/reels
      // when they appear in the For You feed. Real views still come from playback.
      trackImpressions: !isVideo || countVideoImpressions,
      onOpenPost: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) {
              if (isReel && isVideo) {
                return ReelPlayer(
                  post: post,
                  isGuest: _isGuest,
                  onGuestAction: _showGuestPrompt,
                  authorId: _authorByPostId[post.id],
                  enableAds: _enableFeedAds,
                  initialResolvedVideoUrl:
                      post.previewVideoUrl ?? post.videoUrl ?? post.hlsVideoUrl,
                  initialAuthorName: post.username,
                  initialAuthorAvatarUrl: post.userAvatar,
                );
              }
              if (isVideo) {
                return VideoDetailScreen(
                  post: post,
                  mediaUrls: media,
                  authorId: _authorByPostId[post.id],
                  isGuest: _isGuest,
                  onGuestAction: _showGuestPrompt,
                );
              }
              return PostDetailScreen(
                post: post,
                mediaUrls: media,
                authorId: _authorByPostId[post.id],
                isGuest: _isGuest,
                onGuestAction: _showGuestPrompt,
              );
            },
          ),
        );
      },
      onDeleted: () {
        setState(() {
          _forYouPosts.removeWhere((p) => p.id == post.id);
          _followingPosts.removeWhere((p) => p.id == post.id);
        });
      },
    );
    if (!_isTvMode) {
      return card;
    }
    return HomeTvFocusableTile(
      onPressed: () {
        if (isReel && isVideo) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ReelPlayer(
                post: post,
                isGuest: _isGuest,
                onGuestAction: _showGuestPrompt,
                authorId: _authorByPostId[post.id],
                enableAds: _enableFeedAds,
                initialResolvedVideoUrl:
                    post.previewVideoUrl ?? post.videoUrl ?? post.hlsVideoUrl,
                initialAuthorName: post.username,
                initialAuthorAvatarUrl: post.userAvatar,
              ),
            ),
          );
          return;
        }
        if (isVideo) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VideoDetailScreen(
                post: post,
                mediaUrls: media,
                authorId: _authorByPostId[post.id],
                isGuest: _isGuest,
                onGuestAction: _showGuestPrompt,
              ),
            ),
          );
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PostDetailScreen(
              post: post,
              mediaUrls: media,
              authorId: _authorByPostId[post.id],
              isGuest: _isGuest,
              onGuestAction: _showGuestPrompt,
            ),
          ),
        );
      },
      child: card,
    );
  }

  Widget _buildVideoList(List<Post> posts) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktopGrid = constraints.maxWidth > 1100;
        if (!isDesktopGrid) {
          final showBatchAds = _canShowBatchAds(posts.length);
          final itemCount =
              _batchItemCount(posts.length, includeLoading: _isLoadingWatch);
          return NotificationListener<ScrollEndNotification>(
            onNotification: (notification) {
              if (notification.metrics.extentAfter < 200 && !_isLoadingWatch) {
                _loadMoreWatch();
              }
              return false;
            },
            child: ListView.builder(
              controller: _watchController,
              cacheExtent: 1200,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.only(bottom: 72),
              itemCount: posts.isEmpty && !_isLoadingWatch ? 1 : itemCount,
              itemBuilder: (context, index) {
                if (posts.isEmpty && !_isLoadingWatch) {
                  return const SizedBox(
                    height: 200,
                    child:
                        Center(child: Text('No videos yet. Pull to refresh')),
                  );
                }
                if (showBatchAds &&
                    index >= itemCount - (_isLoadingWatch ? 1 : 0)) {
                  return _isLoadingWatch
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF1DA1F2),
                            ),
                          ),
                        )
                      : const SizedBox.shrink();
                }
                if (index >= posts.length) {
                  return _isLoadingWatch
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF1DA1F2),
                            ),
                          ),
                        )
                      : const SizedBox.shrink();
                }
                if (showBatchAds) {
                  if (_isBatchAdRow(index, posts.length)) {
                    final slotIndex = _batchAdSlotForRow(index);
                    return _isTvMode
                        ? _buildTvSponsoredTile(slotIndex: slotIndex)
                        : _buildNativeAdTile(slotIndex: slotIndex);
                  }
                  final postIndex = _batchPostIndexForRow(index, posts.length);
                  if (postIndex >= posts.length) {
                    return const SizedBox.shrink();
                  }
                  final post = posts[postIndex];
                  if (post.videoUrl != null && post.videoUrl!.isNotEmpty) {
                    final card = WatchVideoCard(
                      post: post,
                      mediaUrls: _mediaByPostId[post.id],
                      isGuest: _isGuest,
                      onGuestAction: _showGuestPrompt,
                      authorId: _authorByPostId[post.id],
                      enableAds: _enableFeedAds,
                    );
                    return _isTvMode
                        ? HomeTvFocusableTile(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => VideoDetailScreen(
                                    post: post,
                                    mediaUrls: _mediaByPostId[post.id],
                                    authorId: _authorByPostId[post.id],
                                    isGuest: _isGuest,
                                    onGuestAction: _showGuestPrompt,
                                    autoPlay: true,
                                  ),
                                ),
                              );
                            },
                            child: card,
                          )
                        : card;
                  }
                  final card = WatchVideoCard(
                    post: post,
                    mediaUrls: _mediaByPostId[post.id],
                    isGuest: _isGuest,
                    onGuestAction: _showGuestPrompt,
                    authorId: _authorByPostId[post.id],
                    enableAds: _enableFeedAds,
                  );
                  return _isTvMode
                      ? HomeTvFocusableTile(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => VideoDetailScreen(
                                  post: post,
                                  mediaUrls: _mediaByPostId[post.id],
                                  authorId: _authorByPostId[post.id],
                                  isGuest: _isGuest,
                                  onGuestAction: _showGuestPrompt,
                                  autoPlay: true,
                                ),
                              ),
                            );
                          },
                          child: card,
                        )
                      : card;
                }
                final post = posts[index];
                if (post.videoUrl != null && post.videoUrl!.isNotEmpty) {
                  final card = WatchVideoCard(
                    post: post,
                    mediaUrls: _mediaByPostId[post.id],
                    isGuest: _isGuest,
                    onGuestAction: _showGuestPrompt,
                    authorId: _authorByPostId[post.id],
                    enableAds: _enableFeedAds,
                  );
                  return _isTvMode
                      ? HomeTvFocusableTile(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => VideoDetailScreen(
                                  post: post,
                                  mediaUrls: _mediaByPostId[post.id],
                                  authorId: _authorByPostId[post.id],
                                  isGuest: _isGuest,
                                  onGuestAction: _showGuestPrompt,
                                  autoPlay: true,
                                ),
                              ),
                            );
                          },
                          child: card,
                        )
                      : card;
                }
                final card = WatchVideoCard(
                  post: post,
                  mediaUrls: _mediaByPostId[post.id],
                  isGuest: _isGuest,
                  onGuestAction: _showGuestPrompt,
                  authorId: _authorByPostId[post.id],
                  enableAds: _enableFeedAds,
                );
                return _isTvMode
                    ? HomeTvFocusableTile(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => VideoDetailScreen(
                                post: post,
                                mediaUrls: _mediaByPostId[post.id],
                                authorId: _authorByPostId[post.id],
                                isGuest: _isGuest,
                                onGuestAction: _showGuestPrompt,
                                autoPlay: true,
                              ),
                            ),
                          );
                        },
                        child: card,
                      )
                    : card;
              },
            ),
          );
        }

        if (posts.isEmpty && !_isLoadingWatch) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('No videos yet. Pull to refresh'),
            ),
          );
        }

        return GridView.builder(
          controller: _watchController,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            // Slightly shorter than 16:9, but tall enough
            // to fit the video area + metadata without overflow.
            childAspectRatio: 16 / 11,
          ),
          itemCount: posts.length + (_isLoadingWatch ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= posts.length) {
              return _isLoadingWatch
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF1DA1F2),
                      ),
                    )
                  : const SizedBox.shrink();
            }
            final post = posts[index];
            if (post.videoUrl != null && post.videoUrl!.isNotEmpty) {
              final card = WatchVideoCard(
                post: post,
                mediaUrls: _mediaByPostId[post.id],
                isGuest: _isGuest,
                onGuestAction: _showGuestPrompt,
                authorId: _authorByPostId[post.id],
                enableAds: _enableFeedAds,
              );
              return _isTvMode
                  ? HomeTvFocusableTile(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => VideoDetailScreen(
                              post: post,
                              mediaUrls: _mediaByPostId[post.id],
                              authorId: _authorByPostId[post.id],
                              isGuest: _isGuest,
                              onGuestAction: _showGuestPrompt,
                              autoPlay: true,
                            ),
                          ),
                        );
                      },
                      child: card,
                    )
                  : card;
            }
            return _buildPostCard(post, _mediaByPostId[post.id]);
          },
        );
      },
    );
  }

  Widget _buildReelsFeed(List<Post> posts) {
    if (posts.isEmpty && !_isLoadingReels) {
      return const Center(child: Text('No reels yet. Pull to refresh'));
    }
    // The bottom nav bar is 68px tall. Since extendBody is true in
    // MainScreen, the body extends behind the nav – shift reel overlays
    // up by exactly the nav bar height so they sit just above it.
    const double bottomNavHeight = 68.0;
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: posts.length,
      onPageChanged: (index) {
        if (!mounted) return;
        setState(() => _activeReelIndex = index);
        _warmUpcomingReels(startIndex: index);
        if (index >= posts.length - 3) {
          _loadMoreReels();
        }
      },
      itemBuilder: (context, index) {
        final post = posts[index];
        // Only show reels with a video URL.
        if (post.videoUrl == null || post.videoUrl!.isEmpty) {
          return const Center(
            child: Text(
              'Video unavailable',
              style: TextStyle(color: Colors.white),
            ),
          );
        }
        return ReelPlayer(
          post: post,
          isGuest: _isGuest,
          onGuestAction: _showGuestPrompt,
          authorId: _authorByPostId[post.id],
          enableAds: _enableFeedAds,
          isActive: index == _activeReelIndex,
          initialResolvedVideoUrl:
              post.previewVideoUrl ?? post.videoUrl ?? post.hlsVideoUrl,
          initialAuthorName: post.username,
          initialAuthorAvatarUrl: post.userAvatar,
          bottomInset: bottomNavHeight,
        );
      },
    );
  }

  void _warmUpcomingReels({required int startIndex}) {
    if (kIsWeb || _reelsPosts.isEmpty) return;
    final maxIndex = _reelsPosts.length - 1;
    final safeStart = startIndex.clamp(0, maxIndex);
    final endIndex = (safeStart + _reelPrefetchAheadCount).clamp(0, maxIndex);
    for (var i = safeStart + 1; i <= endIndex; i++) {
      final url = _reelsPosts[i].preferredVideoUrl?.trim();
      if (url == null || url.isEmpty) continue;
      VideoCacheService.warm(url);
    }
  }

  Widget _buildFeed(
    List<Post> posts,
    ScrollController controller,
    bool isForYou,
  ) {
    if (posts.isEmpty && (_isLoading || !_feedsReadyForFirstPaint)) {
      return _buildFeedSkeleton(
        controller: controller,
        isForYou: isForYou,
      );
    }
    final visiblePosts = List<Post>.from(posts);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final showBatchAds = _canShowBatchAds(visiblePosts.length);
    final itemCount =
        _batchItemCount(visiblePosts.length, includeLoading: _isLoading);
    final pendingPosts = _pendingPostsForFeed(isForYou);
    return RefreshIndicator(
      onRefresh: () => _refreshFeed(isForYou),
      child: NotificationListener<ScrollEndNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter < 200 && !_isLoading) {
            _loadMore(isForYou);
          }
          return false;
        },
        child: CustomScrollView(
          controller: controller,
          cacheExtent: 400,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            if (isForYou)
              const SliverToBoxAdapter(child: PendingUploadBanner()),
            if (pendingPosts.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildNewPostsBanner(
                  count: pendingPosts.length,
                  onTap: () async {
                    await _applyPendingNewPosts(isForYou);
                    if (controller.hasClients) {
                      await controller.animateTo(
                        0,
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                ),
              ),
            if (isForYou) ...[
              SliverToBoxAdapter(
                child: Container(
                  color: isDark ? Colors.black : Colors.black.withOpacity(0.03),
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    color: theme.colorScheme.surface,
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 110,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _stories.length,
                            itemBuilder: (context, index) {
                              final story = _stories[index];
                              final avatar = StoryAvatar(
                                story: story,
                                isCurrentUser: index == 0,
                              );
                              return GestureDetector(
                                onTap: () => _handleStoryTap(index),
                                child: avatar,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: theme.dividerColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (_enableFeedAds)
              SliverToBoxAdapter(
                child: _buildNativeAdTile(slotIndex: 0),
              ),

            if (visiblePosts.isEmpty && !_isLoading)
              const SliverToBoxAdapter(child: SizedBox.shrink()),
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                if (showBatchAds) {
                  if (index >= itemCount - (_isLoading ? 1 : 0)) {
                    return _isLoading
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(
                                color: Color(0xFF1DA1F2),
                              ),
                            ),
                          )
                        : const SizedBox.shrink();
                  }
                  if (_isBatchAdRow(index, visiblePosts.length)) {
                    final slotIndex = _batchAdSlotForRow(index);
                    return _isTvMode
                        ? _buildTvSponsoredTile(slotIndex: slotIndex)
                        : _buildNativeAdTile(slotIndex: slotIndex);
                  }
                  final postIndex =
                      _batchPostIndexForRow(index, visiblePosts.length);
                  if (postIndex >= visiblePosts.length) {
                    return const SizedBox.shrink();
                  }
                  final post = visiblePosts[postIndex];
                  return _buildPostCard(
                    post,
                    _mediaByPostId[post.id],
                    countVideoImpressions: isForYou,
                  );
                }
                if (index >= visiblePosts.length) {
                  return _isLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(
                              color: Color(0xFF1DA1F2),
                            ),
                          ),
                        )
                      : const SizedBox.shrink();
                }
                final post = visiblePosts[index];
                return _buildPostCard(
                  post,
                  _mediaByPostId[post.id],
                  countVideoImpressions: isForYou,
                );
              }, childCount: itemCount),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 72),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedSkeleton({
    required ScrollController controller,
    required bool isForYou,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Premium neutral colors that blend beautifully under the shimmer gradient
    final baseColor = isDark ? const Color(0xFF242424) : const Color(0xFFE5E5EA);
    final accentColor = isDark ? const Color(0xFF2C2C2C) : const Color(0xFFEBEBF0);

    Widget block({double height = 16, double width = double.infinity, double radius = 999}) {
      return Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }

    Widget avatar() {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: baseColor,
          shape: BoxShape.circle,
        ),
      );
    }

    Widget storyAvatar({double width = 54}) {
      return Container(
        width: width,
        height: width,
        decoration: BoxDecoration(
          color: baseColor,
          shape: BoxShape.circle,
        ),
      );
    }

    Widget storiesSkeleton() {
      return SizedBox(
        height: 110,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          itemBuilder: (context, index) => SizedBox(
            width: 72,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.dividerColor.withOpacity(0.2),
                      width: 2,
                    ),
                  ),
                  child: storyAvatar(width: 54),
                ),
                const SizedBox(height: 6),
                block(height: 10, width: 50, radius: 2),
              ],
            ),
          ),
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemCount: 7,
        ),
      );
    }

    Widget cardSkeleton() {
      final mediaAspectRatio = isForYou ? 1.0 : 16 / 9;
      return Container(
        color: isDark ? Colors.black : Colors.black.withOpacity(0.03),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor, width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    avatar(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          block(height: 18, width: 140, radius: 4),
                          const SizedBox(height: 6),
                          block(height: 12, width: 70, radius: 3),
                        ],
                      ),
                    ),
                    // Trailing follow/menu placeholder
                    block(height: 24, width: 60, radius: 12),
                  ],
                ),
              ),

              // Description Text Content
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    block(height: 14, width: double.infinity, radius: 4),
                    const SizedBox(height: 6),
                    block(height: 14, width: 200, radius: 4),
                  ],
                ),
              ),

              // Media content
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: mediaAspectRatio,
                    child: Container(
                      color: accentColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Actions Row (Exactly mirroring PostCard actions bar)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Bookmark
                    block(height: 20, width: 20, radius: 4),
                    // Share
                    block(height: 20, width: 20, radius: 4),
                    // Repost
                    Row(
                      children: [
                        block(height: 18, width: 18, radius: 4),
                        const SizedBox(width: 4),
                        block(height: 12, width: 16, radius: 2),
                      ],
                    ),
                    // Impression (views)
                    Row(
                      children: [
                        block(height: 18, width: 18, radius: 4),
                        const SizedBox(width: 4),
                        block(height: 12, width: 16, radius: 2),
                      ],
                    ),
                    // Comment
                    Row(
                      children: [
                        block(height: 18, width: 18, radius: 4),
                        const SizedBox(width: 4),
                        block(height: 12, width: 16, radius: 2),
                      ],
                    ),
                    // Like
                    Row(
                      children: [
                        block(height: 18, width: 18, radius: 4),
                        const SizedBox(width: 4),
                        block(height: 12, width: 16, radius: 2),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      );
    }

    return ShimmerLoading(
      child: RefreshIndicator(
        onRefresh: () => _refreshFeed(isForYou),
        child: CustomScrollView(
          controller: controller,
          cacheExtent: 1200,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            if (isForYou) SliverToBoxAdapter(child: storiesSkeleton()),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => cardSkeleton(),
                childCount: 5,
              ),
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildNativeAdTile({required int slotIndex}) {
    if (kIsWeb) return const SizedBox.shrink();
    return HomeInlineNativeAdTile(
      key: ValueKey<int>(slotIndex),
      slotIndex: slotIndex,
      reserveSpaceWhenLoading: slotIndex < 3,
      sharedPool: slotIndex < 3,
    );
  }

  List<Post> _postsForFeed(bool isForYou) {
    return isForYou ? _forYouPosts : _followingPosts;
  }

  List<Post> _pendingPostsForFeed(bool isForYou) {
    return isForYou ? _pendingForYouPosts : _pendingFollowingPosts;
  }

  String _feedKeyFor(bool isForYou) {
    return isForYou ? 'for_you' : 'following';
  }

  void _sortPostsNewestFirst(List<Post> posts) {
    posts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<void> _queueNewPostsForFeed(bool isForYou) async {
    if (!mounted) return;
    if (!isForYou && _followingIds.isEmpty) return;
    if (isForYou && !_feedsReadyForFirstPaint) return;

    try {
      final fetchLimit = 20;
      final aw.RowList docsList = isForYou
          ? await (_isGuest
              ? AppwriteService.fetchPosts(
                  limit: fetchLimit,
                  applyFeedRanking: true,
                  sessionSeed: _feedRefreshSeed,
                )
              : AppwriteService.fetchForYouFeed(
                  userId: _currentUserId,
                  limit: fetchLimit,
                  sessionSeed: _feedRefreshSeed,
                ))
          : await AppwriteService.fetchPostsByUserIds(
              _followingIds,
              limit: fetchLimit,
              sessionSeed: _feedRefreshSeed,
            );

      final rows = docsList.rows;
      final mapped = <Post>[];
      for (final row in rows) {
        final post = await _mapRowToPost(row);
        if (post != null) {
          mapped.add(post);
        }
      }
      if (mapped.isEmpty) return;

      final currentIds = <String>{
        ..._postsForFeed(isForYou).map((post) => post.id),
        ..._pendingPostsForFeed(isForYou).map((post) => post.id),
      };
      final freshPosts =
          mapped.where((post) => !currentIds.contains(post.id)).toList();
      if (freshPosts.isEmpty) return;

      _prefetchPostImages(freshPosts);

      if (!mounted) return;
      setState(() {
        final pending = _pendingPostsForFeed(isForYou);
        pending.removeWhere(
          (existing) => freshPosts.any((post) => post.id == existing.id),
        );
        pending.addAll(freshPosts);
        _sortPostsNewestFirst(pending);
      });
    } catch (_) {}
  }

  Future<void> _promotePublishedPostToTop(String postId) async {
    try {
      final row = await AppwriteService.getRow(
          AppwriteService.postsCollectionId, postId);
      final post = await _mapRowToPost(row);
      if (post == null || !mounted) return;
      _insertPostAtTop(post, true);
    } catch (_) {}
  }

  Future<Post?> _mapRealtimePayloadToPost(Map<String, dynamic> data) async {
    try {
      final rowId = data[r'$id']?.toString().trim().isNotEmpty == true
          ? data[r'$id'].toString().trim()
          : data['id']?.toString().trim();
      if (rowId == null || rowId.isEmpty) return null;
      final List<String> rawMedia = data['mediaUrls'] is List
          ? (data['mediaUrls'] as List)
              .map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList()
          : <String>[];
      _authorByPostId[rowId] = data['userId'] as String? ?? '';
      final postType = data['postType'] as String?;
      final title = data['title'] as String?;
      final thumbnailUrl = data['thumbnailUrl'] as String?;
      final postTypeLower = (postType ?? '').toLowerCase();
      final isVideoPost =
          postTypeLower.contains('video') || postTypeLower.contains('reel');

      String? videoUrl;
      String? previewVideoUrl = (data['previewVideoUrl'] as String?)?.trim();
      String? hlsVideoUrl = (data['hlsVideoUrl'] as String?)?.trim();
      String? firstImage;
      List<String> mediaForUi;

      if (isVideoPost && rawMedia.isNotEmpty) {
        final first = rawMedia.first;
        videoUrl = (first.startsWith('http://') || first.startsWith('https://'))
            ? first
            : StorageService.getVideoDisplayUrlSync(first);
        firstImage = thumbnailUrl?.isNotEmpty == true
            ? StorageService.getImageDisplayUrlSync(thumbnailUrl!)
            : (rawMedia.length > 1
                ? StorageService.getImageDisplayUrlSync(rawMedia[1])
                : null);
        mediaForUi = firstImage != null ? <String>[firstImage] : <String>[];
      } else {
        firstImage = thumbnailUrl?.isNotEmpty == true
            ? StorageService.getImageDisplayUrlSync(thumbnailUrl!)
            : (rawMedia.isNotEmpty
                ? StorageService.getImageDisplayUrlSync(rawMedia.first)
                : null);
        mediaForUi = <String>[];
        for (final media in rawMedia) {
          mediaForUi.add(StorageService.getImageDisplayUrlSync(media));
        }
      }

      _mediaByPostId[rowId] = mediaForUi;
      return Post(
        id: rowId,
        username: (data['displayName'] as String?)?.trim() ?? '',
        userAvatar: data['userAvatar'] as String? ?? '',
        content: data['content'] as String? ?? '',
        timestamp: DateTime.tryParse(data[r'$createdAt']?.toString() ?? '') ??
            DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        likes: data['likes'] as int? ?? 0,
        comments: data['comments'] as int? ?? 0,
        reposts: data['reposts'] as int? ?? 0,
        impressions: data['impressions'] as int? ?? 0,
        views: data['views'] as int? ?? 0,
        textBgColor: data['textBgColor'] as int?,
        imageUrl: firstImage,
        videoUrl: videoUrl,
        previewVideoUrl:
            previewVideoUrl?.isNotEmpty == true ? previewVideoUrl : null,
        hlsVideoUrl: hlsVideoUrl?.isNotEmpty == true ? hlsVideoUrl : null,
        postType: postType,
        title: title,
        thumbnailUrl: thumbnailUrl,
        sourcePostId: data['sourcePostId'] as String?,
        sourceUserId: data['sourceUserId'] as String?,
        sourceUsername: data['sourceUsername'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  void _insertPostAtTop(Post post, bool isForYou) {
    if (!mounted) return;
    final list = _postsForFeed(isForYou);
    final pending = _pendingPostsForFeed(isForYou);
    final seen = isForYou ? _seenForYouIds : _seenFollowingIds;
    setState(() {
      list.removeWhere((item) => item.id == post.id);
      pending.removeWhere((item) => item.id == post.id);
      list.insert(0, post);
      _sortPostsNewestFirst(list);
      seen.add(post.id);
      if (isForYou) {
        FeedCache.forYouPosts = _forYouPosts;
      } else {
        FeedCache.followingPosts = _followingPosts;
      }
    });
  }

  Future<void> _applyPendingNewPosts(bool isForYou) async {
    final pending = _pendingPostsForFeed(isForYou);
    if (pending.isEmpty) return;

    final list = _postsForFeed(isForYou);
    final existingIds = list.map((post) => post.id).toSet();
    final toInsert = <Post>[];
    for (final post in pending) {
      if (existingIds.add(post.id)) {
        toInsert.add(post);
      }
    }
    if (toInsert.isEmpty) {
      pending.clear();
      return;
    }

    _sortPostsNewestFirst(toInsert);

    setState(() {
      list.insertAll(0, toInsert);
      _sortPostsNewestFirst(list);
      pending.clear();
      if (isForYou) {
        FeedCache.forYouPosts = _forYouPosts;
      } else {
        FeedCache.followingPosts = _followingPosts;
      }
    });

    await FeedExposureService.markShown(
      _feedKeyFor(isForYou),
      toInsert.map((post) => post.id),
      topPostId: toInsert.first.id,
    );
  }

  Widget _buildNewPostsBanner({
    required int count,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.fiber_new,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    count == 1 ? 'See 1 new post' : 'See $count new posts',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_up,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTvSponsoredTile({required int slotIndex}) {
    return HomeTvFocusableTile(
      child: HomeTvSponsoredCard(slotIndex: slotIndex),
    );
  }

  Future<void> _handleStoryTap(int index) async {
    if (index == 0) {
      final user = await AppwriteService.getCurrentUser();
      if (user == null) {
        _showGuestPrompt();
        return;
      }
      _showStoryOptions();
      return;
    }
    final user = await AppwriteService.getCurrentUser();
    if (!mounted) return;
    if (user == null) {
      _showGuestPrompt();
      return;
    }
    if (_isGuest) {
      setState(() => _isGuest = false);
    }
    if (index >= _stories.length) return;
    final story = _stories[index];
    StatusUpdate? statusMatch;
    for (final candidate in _statusUpdates) {
      if (candidate.id == story.id) {
        statusMatch = candidate;
        break;
      }
    }
    final status = statusMatch ??
        StoryManager.stories.value.firstWhere(
          (s) => s.id == story.id,
          orElse: () => StoryManager.stories.value.first,
        );
    status.isViewed = true;
    StoryManager.markViewed(status.id);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StatusViewerScreen(status: status)),
    );
  }

  void _showStoryOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose photo from gallery'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickStory(ImageSource.gallery, video: false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_library),
                title: const Text('Choose video from gallery'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickStory(ImageSource.gallery, video: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take photo'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickStory(ImageSource.camera, video: false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: const Text('Record video'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickStory(ImageSource.camera, video: true);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickStory(ImageSource source, {required bool video}) async {
    try {
      final XFile? file = video
          ? await _storyPicker.pickVideo(
              source: source,
              maxDuration: const Duration(seconds: 30),
            )
          : await _storyPicker.pickImage(source: source);
      if (file == null) return;
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StoryPublishScreen(media: file)),
      );
    } catch (_) {}
  }

  Future<void> _refreshFeed(bool isForYou) async {
    await _bumpRefreshSeed();
    unawaited(NativeAdPreloadService.refresh(maxSlotIndex: 2));
    if (isForYou) {
      if (_forYouPosts.isEmpty) {
        setState(() {
          _forYouCursor = null;
          FeedCache.clearForYou();
          _seenForYouIds.clear();
          _pendingForYouPosts.clear();
          _forYouBatchAdStates.clear();
        });
        await _loadMore(true);
        if (_forYouPosts.length < 5) {
          await _loadMore(true);
        }
        return;
      }

      await _queueNewPostsForFeed(true);
      await _applyPendingNewPosts(true);
      return;
    }

    setState(() {
      _followingPosts.clear();
      _followingCursor = null;
      FeedCache.clearFollowing();
      _seenFollowingIds.clear();
      _pendingFollowingPosts.clear();
      _followingBatchAdStates.clear();
    });
    await _loadMore(false);
    if (_followingPosts.length < 5) {
      await _loadMore(false);
    }
  }

  List<Post> _filterUnseenPosts(List<Post> posts, Set<String> seenIds) {
    final unique = <Post>[];
    for (final post in posts) {
      if (seenIds.add(post.id)) {
        unique.add(post);
      }
    }
    return unique;
  }

  Future<void> _loadMore(bool isForYou) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final fetchLimit = isForYou
          ? (_forYouCursor == null ? 20 : 10)
          : (_followingCursor == null ? 20 : 10);
      final feedPage = isForYou
          ? await (_isGuest
              ? AppwriteService.fetchPostsPage(
                  limit: fetchLimit,
                  cursorId: _forYouCursor,
                  applyFeedRanking: true,
                  sessionSeed: _feedRefreshSeed,
                )
              : AppwriteService.fetchForYouFeedPage(
                  userId: _currentUserId,
                  limit: fetchLimit,
                  cursorId: _forYouCursor,
                  sessionSeed: _feedRefreshSeed,
                ))
          : await AppwriteService.fetchPostsByUserIdsPage(
              _followingIds,
              limit: fetchLimit,
              cursorId: _followingCursor,
              sessionSeed: _feedRefreshSeed,
            );
      final List<aw.Row> docs = feedPage.rows;
      if (_currentUserId != null && docs.isNotEmpty) {
        try {
          await AppwriteService.prefetchUserReactionsAndFollows(
            userId: _currentUserId!,
            postIds: docs.map((d) => d.$id).toList(),
            authorIds: docs
                .map((d) => d.data['userId'] as String? ?? '')
                .toList(),
          );
        } catch (_) {}
      }
      final mapped = <Post>[];
      for (final d in docs) {
        final data = d.data;
        final List<String> rawMedia = data['mediaUrls'] is List
            ? (data['mediaUrls'] as List)
                .map((item) => item.toString())
                .toList()
            : [];
        _authorByPostId[d.$id] = data['userId'] as String? ?? '';
        final postType = data['postType'] as String?;
        final title = data['title'] as String?;
        final thumbnailUrl = data['thumbnailUrl'] as String?;
        final postTypeLower = (postType ?? '').toLowerCase();
        final bool isVideoPost =
            postTypeLower.contains('video') || postTypeLower.contains('reel');

        String? videoUrl;
        String? firstImage;
        List<String> mediaForUi;

        if (isVideoPost && rawMedia.isNotEmpty) {
          final first = rawMedia.first;
          videoUrl =
              (first.startsWith('http://') || first.startsWith('https://'))
                  ? first
                  : StorageService.getVideoDisplayUrlSync(first);
          firstImage = thumbnailUrl?.isNotEmpty == true
              ? (thumbnailUrl!.startsWith('http')
                  ? StorageService.getImageDisplayUrlSync(thumbnailUrl)
                  : StorageService.getImageDisplayUrlSync(thumbnailUrl))
              : (rawMedia.length > 1
                  ? StorageService.getImageDisplayUrlSync(rawMedia[1])
                  : null);
          mediaForUi = firstImage != null ? <String>[firstImage] : <String>[];
        } else {
          firstImage = thumbnailUrl?.isNotEmpty == true
              ? (thumbnailUrl!.startsWith('http')
                  ? StorageService.getImageDisplayUrlSync(thumbnailUrl)
                  : StorageService.getImageDisplayUrlSync(thumbnailUrl))
              : (rawMedia.isNotEmpty
                  ? StorageService.getImageDisplayUrlSync(rawMedia.first)
                  : null);
          mediaForUi = <String>[];
          for (final media in rawMedia) {
            mediaForUi.add(StorageService.getImageDisplayUrlSync(media));
          }
        }

        _mediaByPostId[d.$id] = mediaForUi;
        mapped.add(
          Post(
            id: d.$id,
            username: (data['displayName'] as String?)?.trim() ?? '',
            userAvatar: data['userAvatar'] as String? ?? '',
            content: data['content'] as String? ?? '',
            // Prefer Appwrite system $createdAt for stable time,
            // fall back to custom column or now if missing.
            timestamp: DateTime.tryParse(d.$createdAt) ??
                (data['createdAt'] != null
                    ? DateTime.tryParse(data['createdAt'] as String? ?? '') ??
                        DateTime.now()
                    : DateTime.now()),
            likes: data['likes'] as int? ?? 0,
            comments: data['comments'] as int? ?? 0,
            reposts: data['reposts'] as int? ?? 0,
            impressions: data['impressions'] as int? ?? 0,
            views: data['views'] as int? ?? 0,
            textBgColor: data['textBgColor'] as int?,
            imageUrl: firstImage,
            videoUrl: videoUrl,
            postType: postType,
            title: title,
            thumbnailUrl: thumbnailUrl,
            sourcePostId: data['sourcePostId'] as String?,
            sourceUserId: data['sourceUserId'] as String?,
            sourceUsername: data['sourceUsername'] as String?,
          ),
        );
      }

      // For following feed, also merge repost events (mirror behavior)
      if (!isForYou && _followingIds.isNotEmpty) {
        final repostRows = await AppwriteService.fetchRepostsByUserIds(
          _followingIds,
          limit: 20,
        );
        for (final r in repostRows.rows) {
          final rData = r.data;
          final postId = rData['postId'] as String?;
          final userId = rData['userId'] as String?;
          if (postId == null || userId == null) continue;
          try {
            final original = await AppwriteService.getRow(
              AppwriteService.postsCollectionId,
              postId,
            );
            final data = original.data;
            final List<String> rawMedia = data['mediaUrls'] is List
                ? (data['mediaUrls'] as List)
                    .map((item) => item.toString())
                    .toList()
                : [];
            final postType = data['postType'] as String?;
            final title = data['title'] as String?;
            final thumbnailUrl = data['thumbnailUrl'] as String?;
            final postTypeLower = (postType ?? '').toLowerCase();
            final bool isVideoPost = postTypeLower.contains('video') ||
                postTypeLower.contains('reel');

            String? videoUrl;
            String? firstImage;
            List<String> mediaForUi;

            if (isVideoPost && rawMedia.isNotEmpty) {
              videoUrl = StorageService.getVideoDisplayUrlSync(rawMedia.first);
              firstImage = thumbnailUrl?.isNotEmpty == true
                  ? StorageService.getImageDisplayUrlSync(thumbnailUrl!)
                  : (rawMedia.length > 1
                      ? StorageService.getImageDisplayUrlSync(rawMedia[1])
                      : null);
              mediaForUi =
                  firstImage != null ? <String>[firstImage] : <String>[];
            } else {
              firstImage = thumbnailUrl?.isNotEmpty == true
                  ? StorageService.getImageDisplayUrlSync(thumbnailUrl!)
                  : (rawMedia.isNotEmpty
                      ? StorageService.getImageDisplayUrlSync(rawMedia.first)
                      : null);
              mediaForUi = <String>[];
              for (final media in rawMedia) {
                mediaForUi.add(StorageService.getImageDisplayUrlSync(media));
              }
            }

            _mediaByPostId[postId] = mediaForUi;
            _authorByPostId[postId] = data['userId'] as String? ?? '';

            // Reposter username is not stored in repost row; fall back to userId.
            final reposterName = rData['username'] as String? ?? userId;

            mapped.add(
              Post(
                id: postId,
                username: (data['displayName'] as String?)?.trim() ?? '',
                userAvatar: data['userAvatar'] as String? ?? '',
                content: data['content'] as String? ?? '',
                timestamp: rData['createdAt'] != null
                    ? DateTime.tryParse(rData['createdAt'] as String? ?? '') ??
                        DateTime.now()
                    : DateTime.now(),
                likes: data['likes'] as int? ?? 0,
                comments: data['comments'] as int? ?? 0,
                reposts: data['reposts'] as int? ?? 0,
                impressions: data['impressions'] as int? ?? 0,
                views: data['views'] as int? ?? 0,
                textBgColor: data['textBgColor'] as int?,
                imageUrl: firstImage,
                videoUrl: videoUrl,
                postType: postType,
                title: title,
                thumbnailUrl: thumbnailUrl,
                sourcePostId: postId,
                sourceUserId: userId,
                sourceUsername: reposterName,
              ),
            );
          } catch (_) {
            continue;
          }
        }
      }

      final uniqueMapped = _filterUnseenPosts(
        mapped,
        isForYou ? _seenForYouIds : _seenFollowingIds,
      );

      _prefetchPostImages(uniqueMapped);

      setState(() {
        final list = isForYou ? _forYouPosts : _followingPosts;
        list.addAll(uniqueMapped);
        _sortPostsNewestFirst(list);
        if (feedPage.nextCursor != null) {
          if (isForYou) {
            _forYouCursor = feedPage.nextCursor;
            FeedCache.forYouCursor = _forYouCursor;
          } else {
            _followingCursor = feedPage.nextCursor;
            FeedCache.followingCursor = _followingCursor;
          }
        }
        // Persist caches
        FeedCache.forYouPosts = _forYouPosts;
        FeedCache.followingPosts = _followingPosts;
        FeedCache.mediaByPostId = _mediaByPostId;
        FeedCache.authorByPostId = _authorByPostId;
        _syncBatchAdStates(
          list,
          isForYou ? _forYouBatchAdStates : _followingBatchAdStates,
        );
      });
      await FeedExposureService.markShown(
        isForYou ? 'for_you' : 'following',
        uniqueMapped.map((post) => post.id),
        topPostId: uniqueMapped.isNotEmpty ? uniqueMapped.first.id : null,
      );
      final bool needsExtraFetch = isForYou &&
          uniqueMapped.isNotEmpty &&
          _forYouPosts.length < 100 &&
          feedPage.nextCursor != null;
      if (needsExtraFetch) {
        await _loadMore(isForYou);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshWatchFeed() async {
    await _bumpRefreshSeed();
    setState(() {
      _watchPosts.clear();
      _watchCursor = null;
      _seenWatchIds.clear();
      _watchBatchAdStates.clear();
    });
    await _loadMoreWatch();
  }

  Future<void> _loadMoreWatch() async {
    if (_isLoadingWatch) return;
    setState(() => _isLoadingWatch = true);
    try {
      final docsList = await AppwriteService.fetchWatchFeedPage(
        limit: _watchCursor == null ? 20 : 10,
        cursorId: _watchCursor,
        sessionSeed: _feedRefreshSeed,
      );
      final docs = docsList.rows;
      if (_currentUserId != null && docs.isNotEmpty) {
        try {
          await AppwriteService.prefetchUserReactionsAndFollows(
            userId: _currentUserId!,
            postIds: docs.map((d) => d.$id).toList(),
            authorIds: docs
                .map((d) => d.data['userId'] as String? ?? '')
                .toList(),
          );
        } catch (_) {}
      }
      final mapped = <Post>[];
      for (final d in docs) {
        final post = await _mapRowToPost(d);
        if (post != null) mapped.add(post);
      }
      final uniqueMapped = _filterUnseenPosts(mapped, _seenWatchIds);
      setState(() {
        _watchPosts.addAll(uniqueMapped);
        if (docsList.nextCursor != null) {
          _watchCursor = docsList.nextCursor;
        }
        _syncBatchAdStates(_watchPosts, _watchBatchAdStates);
      });
      await FeedExposureService.markShown(
        'watch',
        uniqueMapped.map((post) => post.id),
        topPostId: uniqueMapped.isNotEmpty ? uniqueMapped.first.id : null,
      );
    } finally {
      if (mounted) setState(() => _isLoadingWatch = false);
    }
  }

  Future<void> _refreshReelsFeed() async {
    await _bumpRefreshSeed();
    setState(() {
      _reelsPosts.clear();
      _reelsCursor = null;
      _activeReelIndex = 0;
      _seenReelIds.clear();
    });
    await _loadMoreReels();
  }

  Future<void> _loadMoreReels() async {
    if (_isLoadingReels) return;
    setState(() => _isLoadingReels = true);
    try {
      final docsList = await AppwriteService.fetchReelsFeedPage(
        limit: _reelsCursor == null ? 20 : 10,
        cursorId: _reelsCursor,
        sessionSeed: _feedRefreshSeed,
      );
      final docs = docsList.rows;
      if (_currentUserId != null && docs.isNotEmpty) {
        try {
          await AppwriteService.prefetchUserReactionsAndFollows(
            userId: _currentUserId!,
            postIds: docs.map((d) => d.$id).toList(),
            authorIds: docs
                .map((d) => d.data['userId'] as String? ?? '')
                .toList(),
          );
        } catch (_) {}
      }
      final mapped = <Post>[];
      for (final d in docs) {
        final post = await _mapRowToPost(d);
        if (post != null) mapped.add(post);
      }
      final uniqueMapped = _filterUnseenPosts(mapped, _seenReelIds);
      setState(() {
        _reelsPosts.addAll(uniqueMapped);
        if (docsList.nextCursor != null) {
          _reelsCursor = docsList.nextCursor;
        }
      });
      _warmUpcomingReels(startIndex: _activeReelIndex);
      await FeedExposureService.markShown(
        'reels',
        uniqueMapped.map((post) => post.id),
        topPostId: uniqueMapped.isNotEmpty ? uniqueMapped.first.id : null,
      );
    } finally {
      if (mounted) setState(() => _isLoadingReels = false);
    }
  }

  Future<Post?> _mapRowToPost(aw.Row d) async {
    final data = d.data;
    final List<String> rawMedia = data['mediaUrls'] is List
        ? (data['mediaUrls'] as List).map((item) => item.toString()).toList()
        : [];
    _authorByPostId[d.$id] = data['userId'] as String? ?? '';
    final postType = data['postType'] as String?;
    final title = data['title'] as String?;
    final thumbnailUrl = data['thumbnailUrl'] as String?;
    final postTypeLower = (postType ?? '').toLowerCase();
    final bool isVideoPost =
        postTypeLower.contains('video') || postTypeLower.contains('reel');

    String? videoUrl;
    String? previewVideoUrl;
    String? hlsVideoUrl;
    String? firstImage;
    List<String> mediaForUi;

    if (isVideoPost && rawMedia.isNotEmpty) {
      final first = rawMedia.first;
      videoUrl = (first.startsWith('http://') || first.startsWith('https://'))
          ? first
          : StorageService.getVideoDisplayUrlSync(first);
      previewVideoUrl = (data['previewVideoUrl'] as String?)?.trim();
      hlsVideoUrl = (data['hlsVideoUrl'] as String?)?.trim();
      firstImage = thumbnailUrl?.isNotEmpty == true
          ? StorageService.getImageDisplayUrlSync(thumbnailUrl!)
          : (rawMedia.length > 1
              ? StorageService.getImageDisplayUrlSync(rawMedia[1])
              : null);
      mediaForUi = firstImage != null ? <String>[firstImage] : <String>[];
    } else {
      firstImage = thumbnailUrl?.isNotEmpty == true
          ? StorageService.getImageDisplayUrlSync(thumbnailUrl!)
          : (rawMedia.isNotEmpty
              ? StorageService.getImageDisplayUrlSync(rawMedia.first)
              : null);
      mediaForUi = <String>[];
      for (final media in rawMedia) {
        mediaForUi.add(StorageService.getImageDisplayUrlSync(media));
      }
    }

    _mediaByPostId[d.$id] = mediaForUi;
    return Post(
      id: d.$id,
      username: (data['displayName'] as String?)?.trim() ?? '',
      userAvatar: data['userAvatar'] as String? ?? '',
      content: data['content'] as String? ?? '',
      timestamp: DateTime.tryParse(d.$createdAt) ??
          (data['createdAt'] != null
              ? DateTime.tryParse(data['createdAt'] as String? ?? '') ??
                  DateTime.now()
              : DateTime.now()),
      likes: data['likes'] as int? ?? 0,
      comments: data['comments'] as int? ?? 0,
      reposts: data['reposts'] as int? ?? 0,
      impressions: data['impressions'] as int? ?? 0,
      views: data['views'] as int? ?? 0,
      textBgColor: data['textBgColor'] as int?,
      imageUrl: firstImage,
      videoUrl: videoUrl,
      previewVideoUrl:
          previewVideoUrl?.isNotEmpty == true ? previewVideoUrl : null,
      hlsVideoUrl: hlsVideoUrl?.isNotEmpty == true ? hlsVideoUrl : null,
      postType: postType,
      title: title,
      thumbnailUrl: thumbnailUrl,
      sourcePostId: data['sourcePostId'] as String?,
      sourceUserId: data['sourceUserId'] as String?,
      sourceUsername: data['sourceUsername'] as String?,
    );
  }

  void _showGuestPrompt() {
    showDialog(context: context, builder: (_) => const GuestPrompt());
  }

  static final Map<String, String> _homeSignedCache = {};

  Future<String?> _resolvePostImageUrl(String url) async {
    if (_homeSignedCache.containsKey(url)) return _homeSignedCache[url]!;
    if (url.contains('cloud.appwrite.io')) {
      _homeSignedCache[url] = url;
      return url;
    }
    try {
      String key = url;
      if (url.contains('://')) {
        final uri = Uri.parse(url);
        if (uri.host.contains('wasabisys.com') && uri.pathSegments.length >= 2) {
          key = uri.pathSegments.skip(1).join('/');
        }
      }
      final signed = await StorageService.getSignedUrl(key);
      _homeSignedCache[url] = signed;
      return signed;
    } catch (_) {
      return null;
    }
  }

  void _prefetchPostImages(List<Post> posts) {
    if (!mounted) return;
    for (final post in posts) {
      final media = _mediaByPostId[post.id];
      if (media != null && media.isNotEmpty) {
        for (final url in media) {
          if (url.isEmpty || url.contains('b-cdn.net')) continue;
          _resolvePostImageUrl(url).then((resolvedUrl) {
            if (resolvedUrl != null && resolvedUrl.isNotEmpty && mounted) {
              precacheImage(
                CachedNetworkImageProvider(resolvedUrl),
                context,
              ).catchError((_) {});
            }
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _forYouController.dispose();
    _followingController.dispose();
    _watchController.dispose();
    _newsController.dispose();
    _postsSub?.close();
    StoryManager.stories.removeListener(_storiesListener);
    PendingUploadService.publishedPostId
        .removeListener(_publishedUploadListener);
    PendingUploadService.publishedVersion
        .removeListener(_publishedUploadListener);
    super.dispose();
  }
}
