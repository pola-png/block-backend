import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:share_plus/share_plus.dart';

import '../services/backend_service.dart';

class ReferralsScreen extends StatefulWidget {
  const ReferralsScreen({super.key});

  @override
  State<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends State<ReferralsScreen> {
  bool _loading = true;
  String? _error;
  String? _referralCode;
  List<Map<String, dynamic>> _referrals = <Map<String, dynamic>>[];
  double _referralEarningsUsd = 0.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _siteBaseUrl() {
    final raw = dotenv.env['XAPZAP_SITE_URL']?.trim();
    if (raw == null || raw.isEmpty) return 'https://www.xapzap.com';
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  String _buildReferralLink(String code) {
    return '${_siteBaseUrl()}/auth/signup?ref=${Uri.encodeComponent(code)}';
  }

  Future<void> _load() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final user = await BackendService.getCurrentUser();
      if (user == null) {
        if (!mounted) return;
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/signin', (route) => false);
        return;
      }

      final profile = await BackendService.getProfileByUserId(user.$id);
      final code =
          (profile?.data['username'] as String?)?.trim().isNotEmpty == true
              ? (profile?.data['username'] as String).trim()
              : user.$id;
      final referrals = await BackendService.fetchReferralFollows(user.$id);
      final earningsSummary =
          await BackendService.fetchCreatorEarningsSummary(creatorId: user.$id);
      final referralEarnings =
          (earningsSummary['referralEarningsUsd'] as num?)?.toDouble() ?? 0.0;

      if (!mounted) return;
      setState(() {
        _referralCode = code;
        _referrals = referrals;
        _referralEarningsUsd = referralEarnings;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load referrals right now. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _copyLink() async {
    final code = _referralCode;
    if (code == null || code.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(
        text: _buildReferralLink(code),
        subject: 'Join me on XapZap',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Referrals'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildStatsCard(theme),
                const SizedBox(height: 16),
                _buildLinkCard(theme),
                const SizedBox(height: 16),
                _buildPeopleCard(theme),
                const SizedBox(height: 16),
                _buildHowItWorksCard(theme),
              ],
            ),
    );
  }

  Widget _buildLinkCard(ThemeData theme) {
    final code = _referralCode ?? '';
    final link = code.isEmpty ? '' : _buildReferralLink(code);
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
          Text('Your referral link',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'Share this link. New signups can follow you automatically.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SelectableText(
            link.isEmpty ? 'Loading...' : link,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: link.isEmpty ? null : _copyLink,
              child: const Text('Share referral link'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeopleCard(ThemeData theme) {
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
          Row(
            children: [
              Icon(Icons.people_outline, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'People you referred',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_error != null) ...[
            Text(_error!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error)),
          ] else if (_referrals.isEmpty) ...[
            Text(
              'No referrals yet. Share your link to get started.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ] else ...[
            for (final item in _referrals)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Builder(
                  builder: (context) {
                    final displayName =
                        (item['displayName'] as String?)?.trim() ?? '';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        backgroundImage:
                            (item['avatarUrl'] as String?)?.isNotEmpty == true
                                ? NetworkImage(item['avatarUrl'] as String)
                                : null,
                        child:
                            (item['avatarUrl'] as String?)?.isNotEmpty == true
                                ? null
                                : Text(displayName.isNotEmpty
                                    ? displayName[0].toUpperCase()
                                    : ''),
                      ),
                      title: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsCard(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFFF1F5F9), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : theme.dividerColor.withOpacity(0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(
            children: [
              Text(
                'Total Referrals',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_referrals.length}',
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Container(
            height: 40,
            width: 1,
            color: isDark ? Colors.white24 : theme.dividerColor.withOpacity(0.5),
          ),
          Column(
            children: [
              Text(
                'Referral Earnings',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '\$${_referralEarningsUsd.toStringAsFixed(3)}', // Match the 3-decimal sub-cent standard
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksCard(ThemeData theme) {
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
          Text('How it works',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _bullet(theme, 'Share your personal invite link with creators.'),
          _bullet(theme, 'New creators register automatically using your code.'),
          _bullet(theme, 'Earn a continuous 10% bonus from the earnings of the people you referred!'),
        ],
      ),
    );
  }

  Widget _bullet(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: theme.textTheme.bodyMedium),
          Expanded(
            child: Text(text, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
