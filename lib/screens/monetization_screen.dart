import 'package:flutter/material.dart';
import '../services/appwrite_service.dart';
import '../services/ad_revenue_service.dart';

class MonetizationScreen extends StatefulWidget {
  const MonetizationScreen({super.key});

  @override
  State<MonetizationScreen> createState() => _MonetizationScreenState();
}

class _MonetizationScreenState extends State<MonetizationScreen> {
  static const double _minimumPayoutUsd = 50.0;
  static const int _payoutDayOfMonth = 27;

  bool _loading = true;
  bool _isGuest = true;
  double _creatorEarningsUsd = 0;
  double _referralEarningsUsd = 0;
  double? _creatorBalanceUsd;
  int _earningsRowCount = 0;
  Map<String, int> _countsByFormat = {};
  Map<String, int> _microsByFormat = {};
  List<Map<String, dynamic>> _recentEarnings = [];
  List<Map<String, dynamic>> _recentPayouts = [];
  final double _creatorShare = 0.45; // 45% to uploader

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final user = await AppwriteService.getCurrentUser();
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _isGuest = true;
          _loading = false;
        });
        return;
      }
      final totals = await AdRevenueService.getTotalsByFormat();
      final counts = await AdRevenueService.getCountsByFormat();
      final earningsSummary = await AppwriteService.fetchCreatorEarningsSummary(
        creatorId: user.$id,
      );
      final balanceRow =
          await AppwriteService.getLatestCreatorBalance(user.$id);
      final recentEarnings = await AppwriteService.fetchCreatorEarningsDaily(
        creatorId: user.$id,
        limit: 5,
      );
      final recentPayouts = await AppwriteService.fetchCreatorPayouts(
        creatorId: user.$id,
        limit: 5,
      );
      if (!mounted) return;
      setState(() {
        _isGuest = false;
        _microsByFormat = totals;
        _countsByFormat = counts;
        _creatorEarningsUsd = _toDouble(earningsSummary['creatorEarningsUsd']);
        _referralEarningsUsd =
            _toDouble(earningsSummary['referralEarningsUsd']);
        _earningsRowCount = _toInt(earningsSummary['rows']);
        _creatorBalanceUsd = _parseCreatorBalance(balanceRow);
        _recentEarnings = recentEarnings.rows.map((row) {
          final data = row.data;
          return <String, dynamic>{
            'reportDate': data['reportDate'] ?? '',
            'placement': data['placement'] ?? '',
            'adUnitId': data['adUnitId'] ?? '',
            'creatorEarningsUsd': data['creatorEarningsUsd'] ?? 0,
            'referralEarningsUsd': data['referralEarningsUsd'] ?? 0,
            'impressions': data['impressions'] ?? 0,
          };
        }).toList(growable: false);
        _recentPayouts = recentPayouts.rows.map((row) {
          final data = row.data;
          return <String, dynamic>{
            'requestedAt': data['requestedAt'] ?? '',
            'paidAt': data['paidAt'] ?? '',
            'amountUsd': data['amountUsd'] ?? 0,
            'status': data['status'] ?? 'requested',
            'payoutMethod': data['payoutMethod'] ?? '',
            'notes': data['notes'] ?? '',
          };
        }).toList(growable: false);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _currentBalanceUsd => _creatorBalanceUsd ?? 0;
  bool get _isPayoutReady => _currentBalanceUsd >= _minimumPayoutUsd;

  DateTime get _nextPayoutDate {
    final now = DateTime.now();
    final thisMonthPayout = DateTime(now.year, now.month, _payoutDayOfMonth);
    if (now.day <= _payoutDayOfMonth) {
      return thisMonthPayout;
    }
    return DateTime(now.year, now.month + 1, _payoutDayOfMonth);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monetize'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Container(
        width: double.infinity,
        color: theme.colorScheme.background,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _isGuest
                ? _buildGuest(theme)
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                      children: [
                        _buildHero(theme),
                        const SizedBox(height: 14),
                        _buildPayoutRules(theme),
                        const SizedBox(height: 14),
                        _buildBreakdown(theme),
                        const SizedBox(height: 14),
                        _buildRecentEarnings(theme),
                        const SizedBox(height: 14),
                        _buildPayouts(theme),
                        const SizedBox(height: 14),
                        _buildLegend(theme),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildGuest(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.45),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_outline,
                size: 34,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Sign in to see monetization stats',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Once you publish eligible content, we will track creator earnings from eligible ads and pay your share to you.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/signin'),
              icon: const Icon(Icons.login),
              label: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(ThemeData theme) {
    final balance = _currentBalanceUsd;
    final ready = _isPayoutReady;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total earnings',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white.withOpacity(0.88),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '\$${_creatorEarningsUsd.toStringAsFixed(2)}',
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 34,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Creator earnings + referral earnings',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tracking $_earningsRowCount earning records',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withOpacity(0.82),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _statusPill(
                theme,
                ready ? 'Ready for payout' : 'Building balance',
                ready ? Colors.greenAccent : Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _heroMiniStat(
                  theme,
                  'Pending balance',
                  '\$${balance.toStringAsFixed(2)}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _heroMiniStat(
                  theme,
                  'Referral',
                  '\$${_referralEarningsUsd.toStringAsFixed(2)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _heroAction(
                theme,
                icon: Icons.campaign_outlined,
                label: 'Ads manager',
                onTap: () => Navigator.of(context).pushNamed('/boosts'),
              ),
              const SizedBox(width: 10),
              _heroAction(
                theme,
                icon: Icons.refresh,
                label: 'Refresh',
                onTap: _loadData,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPayoutRules(ThemeData theme) {
    final balance = _currentBalanceUsd;
    final ready = _isPayoutReady;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.surface,
            theme.colorScheme.surfaceVariant.withOpacity(0.35),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payout rules',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Monthly payouts run on the 27th.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _buildRuleChip(
                theme,
                ready ? 'Eligible' : 'Carry over',
                ready ? Colors.green : theme.colorScheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildRuleStat(
                theme,
                'Minimum payout',
                '\$${_minimumPayoutUsd.toStringAsFixed(2)}',
              ),
              _buildRuleStat(
                theme,
                'Next payout date',
                _nextPayoutDate.day.toString(),
                suffix: _monthLabel(_nextPayoutDate),
              ),
              _buildRuleStat(
                theme,
                'Current balance',
                '\$${balance.toStringAsFixed(2)}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            ready
                ? 'Your balance is above the minimum payout threshold. It will be included in the monthly payout run.'
                : 'Your balance stays on your account and rolls forward until it reaches the minimum payout threshold.',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'The payout history below shows each monthly payout.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentEarnings(ThemeData theme) {
    if (_recentEarnings.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.dividerColor),
        ),
        child: const Text('No earnings recorded yet.'),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent earnings',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ..._recentEarnings.map((row) {
            final reportDate = row['reportDate']?.toString() ?? '';
            final placement = row['placement']?.toString() ?? '';
            final earnings = _toDouble(row['creatorEarningsUsd']);
            final impressions = row['impressions']?.toString() ?? '0';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reportDate.isEmpty
                              ? placement
                              : '$reportDate • $placement',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$impressions impressions',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '\$${earnings.toStringAsFixed(2)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPayouts(ThemeData theme) {
    if (_recentPayouts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.dividerColor),
        ),
        child: const Text(
          'No payout history yet. Balances roll over until they reach \$50.00.',
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Payout history',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 10),
          ..._recentPayouts.map((row) {
            final amount = _toDouble(row['amountUsd']);
            final status = row['status']?.toString() ?? 'requested';
            final requestedAt = row['requestedAt']?.toString() ?? '';
            final method = row['payoutMethod']?.toString() ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          requestedAt.isEmpty
                              ? 'Payout'
                              : 'Requested $requestedAt',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [status, if (method.isNotEmpty) method].join(' • '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '\$${amount.toStringAsFixed(2)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRuleChip(ThemeData theme, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _buildRuleStat(
    ThemeData theme,
    String label,
    String value, {
    String? suffix,
  }) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.25),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          if (suffix != null) ...[
            const SizedBox(height: 2),
            Text(
              suffix,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBreakdown(ThemeData theme) {
    if (_countsByFormat.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.dividerColor),
        ),
        child: const Text('No creator earnings by format yet.'),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Earnings by format',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 10),
          ..._countsByFormat.entries.map((entry) {
            final format = entry.key;
            final count = entry.value;
            final micros = _microsByFormat[format] ?? 0;
            final creatorEarnings = (micros / 1e6) * _creatorShare;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          format,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$count eligible impressions',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\$${creatorEarnings.toStringAsFixed(2)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildLegend(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How payouts work',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text('• Ads run before Watch/Reels videos.'),
          const Text('• We calculate ad revenue per impression.'),
          const Text(
              '• 45% of eligible ad revenue goes into your creator earnings.'),
          Text(
            'Estimates here reflect recorded ad revenue; actual payouts depend on live ad rates and platform reports.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroMiniStat(ThemeData theme, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withOpacity(0.78),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(ThemeData theme, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: color == Colors.white ? Colors.white : color,
        ),
      ),
    );
  }

  Widget _heroAction(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.14)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _parseCreatorBalance(dynamic row) {
    if (row == null) return 0;
    final data = row.data as Map<String, dynamic>;
    return _toDouble(data['balanceUsd']);
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value.toString()) ?? 0;
  }

  String _monthLabel(DateTime date) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[date.month - 1];
  }
}
