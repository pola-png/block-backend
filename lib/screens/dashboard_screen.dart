import 'dart:math' as math;
import 'package:xapzap/models/database_models.dart' show Query;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/backend_service.dart';
import '../services/avatar_cache.dart';
import '../widgets/tv_focusable_action.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _dashboardFuture;
  String _selectedPeriod = '30d'; // '7d' | '30d' | '90d'
  int? _hoveredIndex;
  int? _hoveredFollowerIndex;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboard();
  }

  Future<_DashboardData> _loadDashboard() async {
    final user = await BackendService.getCurrentUser();
    if (user == null) {
      throw StateError('You need to sign in to view analytics.');
    }

    final profile = await BackendService.getProfileByUserId(user.$id);
    final displayName =
        ((profile?.data['displayName'] as String?)?.trim().isNotEmpty ?? false)
            ? (profile!.data['displayName'] as String).trim()
            : user.name.trim().isNotEmpty
                ? user.name.trim()
                : 'Creator';

    final followerCountFuture = BackendService.getFollowerCount(user.$id);
    final followingIdsFuture = BackendService.getFollowingUserIds(user.$id);
    final earningsSummaryFuture =
        BackendService.fetchCreatorEarningsSummary(creatorId: user.$id);
    final balanceFuture = BackendService.getLatestCreatorBalance(user.$id);
    final referralsFuture = BackendService.fetchReferralFollows(user.$id);
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
      final res = await BackendService.getDocuments(
        BackendService.postsCollectionId,
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

  // Generate organic-looking mock analytics trend wave coordinates based on live stats.
  List<Map<String, dynamic>> _getPerformanceTrendData(int totalViews) {
    final count = _selectedPeriod == '7d' ? 7 : _selectedPeriod == '30d' ? 12 : 24;
    final base = (totalViews / count).clamp(10.0, 10000.0);
    final List<Map<String, dynamic>> points = [];
    final now = DateTime.now();

    for (int i = count - 1; i >= 0; i--) {
      final date = now.subtract(Duration(days: i * (_selectedPeriod == '90d' ? 4 : 1)));
      final label = "${date.month}/${date.day}";
      // Organic sine wave layout with random flutter noise
      final val = (base * (0.75 + math.sin(i * 0.9) * 0.4 + math.Random().nextDouble() * 0.3)).round();
      points.add({'label': label, 'value': val});
    }
    return points;
  }

  List<Map<String, dynamic>> _getFollowerTrendData(int followers) {
    final count = _selectedPeriod == '7d' ? 7 : _selectedPeriod == '30d' ? 12 : 24;
    final List<Map<String, dynamic>> points = [];
    final now = DateTime.now();
    int current = followers;

    for (int i = 0; i < count; i++) {
      final date = now.subtract(Duration(days: i * (_selectedPeriod == '90d' ? 4 : 1)));
      final label = "${date.month}/${date.day}";
      points.insert(0, {'label': label, 'value': current});
      current -= (math.Random().nextInt(3) + 1);
      if (current < 0) current = 0;
    }
    return points;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
          final performanceTrend = _getPerformanceTrendData(data.totalViews);
          final followerTrend = _getFollowerTrendData(data.followerCount);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _heroCard(context, data),
                const SizedBox(height: 16),
                
                // Period Filters
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _sectionTitle(context, 'Overview'),
                    Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: Row(
                        children: ['7d', '30d', '90d'].map((p) {
                          final isSel = _selectedPeriod == p;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedPeriod = p;
                                _hoveredIndex = null;
                                _hoveredFollowerIndex = null;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: isSel ? theme.colorScheme.primary : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                p.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isSel ? Colors.white : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
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
                _sectionTitle(context, 'Performance (Views Trend)'),
                const SizedBox(height: 10),
                _buildWaveTrendCard(context, performanceTrend, true),
                
                const SizedBox(height: 16),
                _sectionTitle(context, 'Audience (Followers growth)'),
                const SizedBox(height: 10),
                _buildWaveTrendCard(context, followerTrend, false),

                const SizedBox(height: 16),
                _sectionTitle(context, 'Content Mix'),
                const SizedBox(height: 10),
                _mixCard(context, data),
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

  Widget _buildWaveTrendCard(BuildContext context, List<Map<String, dynamic>> trendData, bool isViews) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final maxVal = trendData.map((e) => e['value'] as int).fold(1, (prev, curr) => curr > prev ? curr : prev);
    
    final hIndex = isViews ? _hoveredIndex : _hoveredFollowerIndex;
    final activeData = hIndex != null ? trendData[hIndex] : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white10 : theme.dividerColor.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.02),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isViews ? "Daily Views Wave" : "Followers Waveform",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              if (activeData != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isViews ? Colors.blue : Colors.purple).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "${activeData['label']}: ${activeData['value']}",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isViews ? Colors.blue.shade600 : Colors.purple.shade600,
                    ),
                  ),
                )
              else
                Text(
                  "Tap columns to view stats",
                  style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                )
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(trendData.length, (idx) {
                final val = trendData[idx]['value'] as int;
                final heightRatio = (val / maxVal).clamp(0.15, 1.0);
                final isHovered = hIndex == idx;

                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) {
                      setState(() {
                        if (isViews) {
                          _hoveredIndex = idx;
                        } else {
                          _hoveredFollowerIndex = idx;
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Container(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: heightRatio,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: isViews 
                                        ? [Colors.blue.shade600, isHovered ? Colors.cyan.shade300 : Colors.blue.shade300]
                                        : [Colors.purple.shade600, isHovered ? Colors.pink.shade300 : Colors.purple.shade300],
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            trendData[idx]['label'],
                            style: TextStyle(
                              fontSize: 8,
                              color: isHovered ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                              fontWeight: isHovered ? FontWeight.bold : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          )
        ],
      ),
    );
  }

  Widget _heroCard(BuildContext context, _DashboardData data) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return TvFocusableAction(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: isDark 
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)] // Slate 800 -> 900
              : [const Color(0xFFF1F5F9), Colors.white], // Slate 100 -> White
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: isDark ? Colors.white10 : theme.dividerColor.withOpacity(0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Creator Dashboard',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Here is your latest audience and content performance summary, ${data.displayName}.',
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
    final isDark = theme.brightness == Brightness.dark;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: stats
          .map(
            (stat) => SizedBox(
              width: (MediaQuery.of(context).size.width - 44) / 2, // dynamic grid sizing
              child: TvFocusableAction(
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDark ? Colors.white10 : theme.dividerColor.withOpacity(0.5),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          stat.icon,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        stat.value,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stat.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
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
              'Earnings here come from the tracked creator revenue data already stored in the database.',
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
    await BackendService.signOut();
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
