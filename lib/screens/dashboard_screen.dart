import 'package:appwrite/appwrite.dart' show Query;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/appwrite_service.dart';
import '../services/avatar_cache.dart';
import '../widgets/tv_focusable_action.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _dashboardFuture;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboard();
  }

  Future<_DashboardData> _loadDashboard() async {
    final user = await AppwriteService.getCurrentUser();
    if (user == null) {
      throw StateError('You need to sign in to view analytics.');
    }

    final profile = await AppwriteService.getProfileByUserId(user.$id);
    final displayName =
        ((profile?.data['displayName'] as String?)?.trim().isNotEmpty ?? false)
            ? (profile!.data['displayName'] as String).trim()
            : user.name.trim().isNotEmpty
                ? user.name.trim()
                : 'Creator';

    final followerCountFuture = AppwriteService.getFollowerCount(user.$id);
    final followingIdsFuture = AppwriteService.getFollowingUserIds(user.$id);
    final earningsSummaryFuture =
        AppwriteService.fetchCreatorEarningsSummary(creatorId: user.$id);
    final balanceFuture = AppwriteService.getLatestCreatorBalance(user.$id);
    final referralsFuture = AppwriteService.fetchReferralFollows(user.$id);
    final postsFuture = _fetchAllPostsForUser(user.$id);

    final results = await Future.wait<dynamic>([
      followerCountFuture,
      followingIdsFuture,
      earningsSummaryFuture,
      balanceFuture,
      referralsFuture,
      postsFuture,
    ]);

    final followerCount = results[0] as int;
    final followingIds = results[1] as List<String>;
    final earningsSummary = results[2] as Map<String, dynamic>;
    final balanceRow = results[3];
    final referrals = results[4] as List<Map<String, dynamic>>;
    final posts = results[5] as List<dynamic>;

    int totalLikes = 0;
    int totalComments = 0;
    int totalViews = 0;
    int totalImpressions = 0;
    int totalReposts = 0;
    int videoPosts = 0;
    int reelPosts = 0;
    int imagePosts = 0;
    int textPosts = 0;
    dynamic topPost;
    int topPostViews = -1;

    for (final row in posts) {
      final data = row.data as Map<String, dynamic>;
      final likes = _parseInt(data['likes']);
      final comments = _parseInt(data['comments']);
      final views = _parseInt(data['views']);
      final impressions = _parseInt(data['impressions']);
      final reposts = _parseInt(data['reposts']);
      final postType = ((data['postType'] as String?) ?? '').toLowerCase();

      totalLikes += likes;
      totalComments += comments;
      totalViews += views;
      totalImpressions += impressions;
      totalReposts += reposts;

      if (postType.contains('reel')) {
        reelPosts += 1;
      } else if (postType.contains('video')) {
        videoPosts += 1;
      } else if (postType.contains('image')) {
        imagePosts += 1;
      } else {
        textPosts += 1;
      }

      if (views > topPostViews) {
        topPostViews = views;
        topPost = row;
      }
    }

    final balanceData = balanceRow?.data as Map<String, dynamic>?;
    final availableBalanceUsd =
        _parseDouble(balanceData?['availableBalanceUsd']);
    final lifetimeEarningsUsd =
        _parseDouble(earningsSummary['creatorEarningsUsd']) +
            _parseDouble(earningsSummary['referralEarningsUsd']);
    final totalTrackedImpressions = _parseInt(earningsSummary['impressions']);

    String? topPostTitle;
    int topPostLikes = 0;
    int topPostComments = 0;
    if (topPost != null) {
      final topData = topPost.data as Map<String, dynamic>;
      final rawTitle = ((topData['title'] as String?) ?? '').trim();
      final rawContent = ((topData['content'] as String?) ?? '').trim();
      final rawCaption = ((topData['caption'] as String?) ?? '').trim();
      topPostTitle = rawTitle.isNotEmpty
          ? rawTitle
          : rawCaption.isNotEmpty
              ? rawCaption
              : rawContent.isNotEmpty
                  ? rawContent
                  : 'Untitled post';
      topPostLikes = _parseInt(topData['likes']);
      topPostComments = _parseInt(topData['comments']);
    }

    return _DashboardData(
      displayName: displayName,
      totalPosts: posts.length,
      followerCount: followerCount,
      followingCount: followingIds.length,
      totalLikes: totalLikes,
      totalComments: totalComments,
      totalViews: totalViews,
      totalImpressions: totalImpressions,
      totalReposts: totalReposts,
      videoPosts: videoPosts,
      reelPosts: reelPosts,
      imagePosts: imagePosts,
      textPosts: textPosts,
      availableBalanceUsd: availableBalanceUsd,
      lifetimeEarningsUsd: lifetimeEarningsUsd,
      totalTrackedImpressions: totalTrackedImpressions,
      referralCount: referrals.length,
      topPostTitle: topPostTitle,
      topPostViews: topPostViews < 0 ? 0 : topPostViews,
      topPostLikes: topPostLikes,
      topPostComments: topPostComments,
    );
  }

  Future<List<dynamic>> _fetchAllPostsForUser(String userId) async {
    final collected = <dynamic>[];
    String? cursorId;

    while (true) {
      final res = await AppwriteService.getDocuments(
        AppwriteService.postsCollectionId,
        queries: <String>[
          Query.equal('userId', userId),
          Query.orderDesc('createdAt'),
          Query.limit(100),
          if (cursorId != null) Query.cursorAfter(cursorId),
        ],
      );
      if (res.rows.isEmpty) {
        break;
      }
      collected.addAll(res.rows);
      cursorId = res.rows.last.$id;
      if (res.rows.length < 100) {
        break;
      }
    }

    return collected;
  }

  int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  double _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0.0;
  }

  Future<void> _refresh() async {
    setState(() {
      _dashboardFuture = _loadDashboard();
    });
    await _dashboardFuture;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0.5,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Log out',
            onPressed: () => _logout(context),
            icon: const Icon(LucideIcons.logOut),
          ),
        ],
      ),
      body: FutureBuilder<_DashboardData>(
        future: _dashboardFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.insights_outlined, size: 40),
                    const SizedBox(height: 12),
                    const Text(
                      'Unable to load analytics right now.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _refresh,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _heroCard(context, data),
                const SizedBox(height: 16),
                _sectionTitle(context, 'Overview'),
                const SizedBox(height: 10),
                _statGrid(
                  context,
                  [
                    _DashboardStat(
                        'Posts', '${data.totalPosts}', Icons.grid_view_rounded),
                    _DashboardStat('Followers', '${data.followerCount}',
                        Icons.people_alt_outlined),
                    _DashboardStat('Following', '${data.followingCount}',
                        Icons.person_add_alt_1_outlined),
                    _DashboardStat('Referrals', '${data.referralCount}',
                        Icons.card_giftcard_outlined),
                  ],
                ),
                const SizedBox(height: 16),
                _sectionTitle(context, 'Content Performance'),
                const SizedBox(height: 10),
                _statGrid(
                  context,
                  [
                    _DashboardStat('Views', _compactNumber(data.totalViews),
                        Icons.play_circle_outline),
                    _DashboardStat(
                        'Impressions',
                        _compactNumber(data.totalImpressions),
                        Icons.visibility_outlined),
                    _DashboardStat('Likes', _compactNumber(data.totalLikes),
                        Icons.favorite_border),
                    _DashboardStat(
                        'Comments',
                        _compactNumber(data.totalComments),
                        Icons.mode_comment_outlined),
                    _DashboardStat('Reposts', _compactNumber(data.totalReposts),
                        Icons.repeat),
                    _DashboardStat(
                        'Tracked Ad Impressions',
                        _compactNumber(data.totalTrackedImpressions),
                        Icons.attach_money),
                  ],
                ),
                const SizedBox(height: 16),
                _sectionTitle(context, 'Content Mix'),
                const SizedBox(height: 10),
                _mixCard(context, data),
                const SizedBox(height: 16),
                _sectionTitle(context, 'Earnings'),
                const SizedBox(height: 10),
                _earningsCard(context, data),
                const SizedBox(height: 16),
                _sectionTitle(context, 'Top Post'),
                const SizedBox(height: 10),
                _topPostCard(context, data),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _heroCard(BuildContext context, _DashboardData data) {
    final theme = Theme.of(context);
    return TvFocusableAction(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primary.withOpacity(0.14),
              theme.colorScheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Creator Dashboard',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Here is your latest audience, post, and earnings summary, ${data.displayName}.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    );
  }

  Widget _statGrid(BuildContext context, List<_DashboardStat> stats) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: stats
          .map(
            (stat) => SizedBox(
              width: 160,
              child: TvFocusableAction(
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(stat.icon,
                          size: 20, color: theme.colorScheme.primary),
                      const SizedBox(height: 12),
                      Text(
                        stat.value,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stat.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _mixCard(BuildContext context, _DashboardData data) {
    final theme = Theme.of(context);
    return TvFocusableAction(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          children: [
            _mixRow(context, 'Videos', data.videoPosts),
            const SizedBox(height: 10),
            _mixRow(context, 'Reels', data.reelPosts),
            const SizedBox(height: 10),
            _mixRow(context, 'Image Posts', data.imagePosts),
            const SizedBox(height: 10),
            _mixRow(context, 'Text Posts', data.textPosts),
          ],
        ),
      ),
    );
  }

  Widget _mixRow(BuildContext context, String label, int value) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        Text(
          '$value',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _earningsCard(BuildContext context, _DashboardData data) {
    final theme = Theme.of(context);
    return TvFocusableAction(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _earningsRow(context, 'Available Balance',
                _formatUsd(data.availableBalanceUsd)),
            const SizedBox(height: 10),
            _earningsRow(context, 'Lifetime Earnings',
                _formatUsd(data.lifetimeEarningsUsd)),
            const SizedBox(height: 10),
            Text(
              'Earnings here come from the tracked creator revenue data already stored in Appwrite.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _earningsRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        Text(
          value,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  Widget _topPostCard(BuildContext context, _DashboardData data) {
    final theme = Theme.of(context);
    return TvFocusableAction(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.dividerColor),
        ),
        child: data.totalPosts == 0
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.topPostTitle ?? 'Untitled post',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _smallPill(context,
                          'Views ${_compactNumber(data.topPostViews)}'),
                      _smallPill(context,
                          'Likes ${_compactNumber(data.topPostLikes)}'),
                      _smallPill(context,
                          'Comments ${_compactNumber(data.topPostComments)}'),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _smallPill(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  String _compactNumber(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(value % 1000000 == 0 ? 0 : 1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}K';
    }
    return '$value';
  }

  String _formatUsd(double value) {
    return '\$${value.toStringAsFixed(2)}';
  }

  Future<void> _logout(BuildContext context) async {
    await AppwriteService.signOut();
    await AvatarCache.clearAll();
    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/signin', (route) => false);
  }
}

class _DashboardStat {
  final String label;
  final String value;
  final IconData icon;

  const _DashboardStat(this.label, this.value, this.icon);
}

class _DashboardData {
  final String displayName;
  final int totalPosts;
  final int followerCount;
  final int followingCount;
  final int totalLikes;
  final int totalComments;
  final int totalViews;
  final int totalImpressions;
  final int totalReposts;
  final int videoPosts;
  final int reelPosts;
  final int imagePosts;
  final int textPosts;
  final double availableBalanceUsd;
  final double lifetimeEarningsUsd;
  final int totalTrackedImpressions;
  final int referralCount;
  final String? topPostTitle;
  final int topPostViews;
  final int topPostLikes;
  final int topPostComments;

  const _DashboardData({
    required this.displayName,
    required this.totalPosts,
    required this.followerCount,
    required this.followingCount,
    required this.totalLikes,
    required this.totalComments,
    required this.totalViews,
    required this.totalImpressions,
    required this.totalReposts,
    required this.videoPosts,
    required this.reelPosts,
    required this.imagePosts,
    required this.textPosts,
    required this.availableBalanceUsd,
    required this.lifetimeEarningsUsd,
    required this.totalTrackedImpressions,
    required this.referralCount,
    required this.topPostTitle,
    required this.topPostViews,
    required this.topPostLikes,
    required this.topPostComments,
  });
}
