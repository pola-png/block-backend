import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/backend_service.dart';
import '../services/ad_revenue_service.dart';
import '../services/micro_job_service.dart';
import 'withdrawal_settings_screen.dart';
import 'payout_verification_screen.dart';

class MonetizationScreen extends StatefulWidget {
  const MonetizationScreen({super.key});

  @override
  State<MonetizationScreen> createState() => _MonetizationScreenState();
}

class _MonetizationScreenState extends State<MonetizationScreen> {
  static const double _minimumPayoutUsd = 10.0;
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
  int? _hoveredBarIndex;

  // Verification state (Level 1 users must verify before receiving payouts)
  int _userLevel = 1;
  bool _isVerified = false;
  String _verificationStatus = 'unverified';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final user = await BackendService.getCurrentUser();
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _isGuest = true;
          _loading = false;
        });
        return;
      }
      if (mounted) {
        setState(() {
          _isGuest = false;
        });
      }

      // Load user level and verification status
      final supabaseUser = Supabase.instance.client.auth.currentUser;
      if (supabaseUser != null) {
        final level = await MicroJobService.getUserLevel(supabaseUser.id);
        final profileRes = await Supabase.instance.client
            .from('profiles')
            .select('is_verified, verification_status')
            .eq('id', supabaseUser.id)
            .maybeSingle();
        if (mounted) {
          setState(() {
            _userLevel = level;
            _isVerified = profileRes?['is_verified'] == true;
            _verificationStatus =
                profileRes?['verification_status'] as String? ?? 'unverified';
          });
        }
      }
      final totals = await AdRevenueService.getTotalsByFormat();
      final counts = await AdRevenueService.getCountsByFormat();
      final earningsSummary = await BackendService.fetchCreatorEarningsSummary(
        creatorId: user.$id,
      );
      final balanceRow =
          await BackendService.getLatestCreatorBalance(user.$id);
      final recentEarnings = await BackendService.fetchCreatorEarningsDaily(
        creatorId: user.$id,
        limit: 7,
      );
      final recentPayouts = await BackendService.fetchCreatorPayouts(
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
    } catch (e) {
      debugPrint('Error loading monetization summary: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
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
        title: const Text('Monetization'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0.5,
        surfaceTintColor: Colors.transparent,
        actions: [
          if (!_isGuest)
            IconButton(
              icon: const Icon(Icons.wallet),
              tooltip: 'Withdraw Coordinates',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const WithdrawalSettingsScreen()),
                );
              },
            ),
        ],
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
                        const SizedBox(height: 16),
                        _buildEarningsWaveCard(theme),
                        const SizedBox(height: 16),
                        _buildPayoutRules(theme),
                        const SizedBox(height: 16),
                        _buildBreakdown(theme),
                        const SizedBox(height: 16),
                        _buildRecentEarnings(theme),
                        const SizedBox(height: 16),
                        _buildPayouts(theme),
                        const SizedBox(height: 16),
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
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)] // Slate 800 -> 900
              : [const Color(0xFFF1F5F9), Colors.white], // Slate 100 -> White
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white10 : theme.dividerColor.withOpacity(0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
          )
        ],
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
                      'TOTAL REVENUE EARNED',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '\$${(_creatorEarningsUsd + (_creatorBalanceUsd ?? 0)).toStringAsFixed(3)}',
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                        fontSize: 36,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Aggregated Ad, Referral & Job yields',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.account_balance_wallet_rounded, size: 28, color: Colors.pinkAccent),
                tooltip: 'Payout Settings',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const WithdrawalSettingsScreen()),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _heroMiniStat(
                  theme,
                  'Pending Balance',
                  '\$${balance.toStringAsFixed(3)}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _heroMiniStat(
                  theme,
                  'Referrals Yield',
                  '\$${_referralEarningsUsd.toStringAsFixed(3)}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEarningsWaveCard(ThemeData theme) {
    if (_recentEarnings.isEmpty) return const SizedBox.shrink();
    
    final isDark = theme.brightness == Brightness.dark;
    final maxVal = _recentEarnings
        .map((e) => _toDouble(e['creatorEarningsUsd']))
        .fold(0.001, (prev, curr) => curr > prev ? curr : prev);
        
    final hIndex = _hoveredBarIndex;
    final hoveredData = hIndex != null ? _recentEarnings[hIndex] : null;

    return Container(
      padding: const EdgeInsets.all(18),
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
                "Earnings Waveform",
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (hoveredData != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "${hoveredData['reportDate']}: \$${_toDouble(hoveredData['creatorEarningsUsd']).toStringAsFixed(3)}",
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                )
              else
                Text(
                  "Tap columns to scan metrics",
                  style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                )
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(_recentEarnings.length, (idx) {
                final val = _toDouble(_recentEarnings[idx]['creatorEarningsUsd']);
                final ratio = (val / maxVal).clamp(0.12, 1.0);
                final isHovered = hIndex == idx;
                
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) {
                      setState(() {
                        _hoveredBarIndex = idx;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Container(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: ratio,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        theme.colorScheme.primary,
                                        isHovered ? Colors.cyan.shade400 : theme.colorScheme.primary.withOpacity(0.5),
                                      ],
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                    ),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _recentEarnings[idx]['reportDate']?.toString().split('-').last ?? '',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: isHovered ? FontWeight.bold : FontWeight.normal,
                              color: isHovered ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                            ),
                          )
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

  Widget _buildPayoutRules(ThemeData theme) {
    final balance = _currentBalanceUsd;
    final ready = _isPayoutReady;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white10 : theme.dividerColor.withOpacity(0.5)),
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
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Monthly payout releases run on the 27th.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (ready)
                _buildRuleChip(
                  theme,
                  'Eligible',
                  Colors.green,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildRuleStat(
                  theme,
                  'Minimum Payout',
                  '\$${_minimumPayoutUsd.toStringAsFixed(2)}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildRuleStat(
                  theme,
                  'Payout Date',
                  _nextPayoutDate.day.toString(),
                  suffix: _monthLabel(_nextPayoutDate),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildRuleStat(
                  theme,
                  'Current Balance',
                  '\$${balance.toStringAsFixed(3)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ── Verification Gate: Level 1 users who have hit the minimum ──
          if (ready && _userLevel == 1 && !_isVerified)
            _buildVerificationGateCard(theme)
          else
            Text(
              ready
                  ? 'Your balance is above the minimum payout threshold. It will be included in the monthly payout run.'
                  : 'Your balance stays on your account and rolls forward until it reaches the minimum payout threshold.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVerificationGateCard(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    Color statusColor;
    String statusLabel;
    String bodyText;

    if (_verificationStatus == 'id_pending') {
      statusColor = Colors.amber.shade700;
      statusLabel = 'ID Under Review';
      bodyText =
          'Your Government ID has been submitted and is under review. Payouts will be released once verification is approved (24–48 hrs).';
    } else if (_verificationStatus == 'fee_paid') {
      statusColor = Colors.blue;
      statusLabel = 'Fee Paid — Upload ID';
      bodyText =
          'You have paid the verification fee. Please upload your Government ID to complete identity verification and unlock payouts.';
    } else {
      statusColor = Colors.redAccent;
      statusLabel = 'Verification Required';
      bodyText =
          'Your balance has reached the payout threshold! To receive your earnings, you must complete a one-time identity verification — this includes a \$2.00 KYC fee and a Government ID upload.';
    }

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(isDark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withOpacity(0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _verificationStatus == 'id_pending'
                    ? Icons.hourglass_top_rounded
                    : _verificationStatus == 'fee_paid'
                        ? Icons.credit_score_rounded
                        : Icons.verified_user_outlined,
                color: statusColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                statusLabel,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            bodyText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_verificationStatus != 'id_pending') ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: statusColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.shield_rounded, size: 18),
                label: Text(
                  _verificationStatus == 'fee_paid'
                      ? 'Upload Government ID'
                      : 'Complete Identity Verification',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const PayoutVerificationScreen(),
                    ),
                  ).then((_) => _loadData());
                },
              ),
            ),
          ],
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
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white10 : theme.dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Daily logs breakdown',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          ..._recentEarnings.map((row) {
            final reportDate = row['reportDate']?.toString() ?? '';
            final placement = row['placement']?.toString() ?? '';
            final earnings = _toDouble(row['creatorEarningsUsd']);
            final impressions = row['impressions']?.toString() ?? '0';
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
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
                    '\$${earnings.toStringAsFixed(3)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
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
    final isDark = theme.brightness == Brightness.dark;
    if (_recentPayouts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? Colors.white10 : theme.dividerColor.withOpacity(0.5)),
        ),
        child: Text(
          'No payout history yet. Balances roll over until they reach \$${_minimumPayoutUsd.toStringAsFixed(2)}.',
          style: const TextStyle(fontSize: 12),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white10 : theme.dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Payout history',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          ..._recentPayouts.map((row) {
            final amount = _toDouble(row['amountUsd']);
            final status = row['status']?.toString() ?? 'requested';
            final requestedAt = row['requestedAt']?.toString() ?? '';
            final method = row['payoutMethod']?.toString() ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          requestedAt.isEmpty
                              ? 'Payout request'
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: color,
          fontSize: 10,
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
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white10 : theme.dividerColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          if (suffix != null) ...[
            const SizedBox(height: 2),
            Text(
              suffix,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 9,
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
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white10 : theme.dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Earnings by format',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
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
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$count eligible impressions',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\$${creatorEarnings.toStringAsFixed(3)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: theme.colorScheme.primary,
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
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white10 : theme.dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How payouts work',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          const Text('• Ads run before Watch/Reels videos.', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          const Text('• We calculate ad revenue per impression.', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          const Text('• 45% of eligible ad revenue goes into your creator earnings.', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 10),
          Text(
            'Estimates here reflect recorded ad revenue; actual payouts depend on live ad rates and platform reports.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroMiniStat(ThemeData theme, String label, String value) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white10 : theme.dividerColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(ThemeData theme, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: color == Colors.white ? Colors.white : color,
          fontSize: 9.5,
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
