import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/reward_live_model.dart';
import '../../screens/monetization_screen.dart';
import '../../services/backend_service.dart';
import '../../services/micro_job_service.dart';
import '../../services/reward_live_service.dart';

class RewardLiveHostHeader extends StatefulWidget {
  final RewardLiveState? liveState;
  final VoidCallback? onOpenHostSheet;

  const RewardLiveHostHeader({
    super.key,
    required this.liveState,
    this.onOpenHostSheet,
  });

  @override
  State<RewardLiveHostHeader> createState() => _RewardLiveHostHeaderState();
}

class _RewardLiveHostHeaderState extends State<RewardLiveHostHeader> {
  bool _isFollowing = false;
  bool _followLoading = false;
  String? _checkedHostId;

  @override
  void didUpdateWidget(covariant RewardLiveHostHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hostId = widget.liveState?.currentHostId;
    if (hostId != _checkedHostId && hostId != null) {
      _checkFollowState(hostId);
    }
  }

  @override
  void initState() {
    super.initState();
    final hostId = widget.liveState?.currentHostId;
    if (hostId != null) {
      _checkFollowState(hostId);
    }
  }

  Future<void> _checkFollowState(String hostId) async {
    _checkedHostId = hostId;
    final currentUid = Supabase.instance.client.auth.currentUser?.id;
    if (currentUid == null || currentUid == hostId) {
      setState(() => _isFollowing = false);
      return;
    }
    try {
      final following = await BackendService.isFollowing(currentUid, hostId);
      if (!mounted) return;
      setState(() => _isFollowing = following);
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    final hostId = widget.liveState?.currentHostId;
    final currentUid = Supabase.instance.client.auth.currentUser?.id;
    if (hostId == null || currentUid == null || hostId == currentUid || _followLoading) return;

    setState(() => _followLoading = true);
    try {
      if (_isFollowing) {
        await BackendService.unfollowUser(hostId);
        if (mounted) setState(() => _isFollowing = false);
      } else {
        await BackendService.followUser(hostId);
        if (mounted) setState(() => _isFollowing = true);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasHost = widget.liveState?.hasHost == true;
    final hostName = widget.liveState?.currentHostName ?? 'Reward Live';
    final hostAvatar = widget.liveState?.currentHostAvatar;
    final currentUid = Supabase.instance.client.auth.currentUser?.id;
    final isMe = currentUid != null && widget.liveState?.currentHostId == currentUid;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            // 1. Host Badge & Info Card (Left)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: const Color(0xFF1DA1F2),
                    backgroundImage: hostAvatar?.isNotEmpty == true ? CachedNetworkImageProvider(hostAvatar!) : null,
                    child: hostAvatar?.isNotEmpty != true
                        ? const Icon(Icons.stream, size: 14, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 85),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          hostName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          hasHost ? 'Host' : '24/7 Room',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasHost && !isMe) ...[
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: _followLoading ? null : _toggleFollow,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _isFollowing ? Colors.white24 : const Color(0xFF1DA1F2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _isFollowing ? 'Following' : 'Follow',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Spacer(),

            // 2. Current User's Earning Balance (Center, Clickable to open Monetization)
            ValueListenableBuilder<double>(
              valueListenable: MicroJobService.userBalanceNotifier,
              builder: (context, balance, _) {
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MonetizationScreen(),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.6), width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF22C55E), size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '\$${balance.toStringAsFixed(4)}',
                          style: const TextStyle(
                            color: Color(0xFF22C55E),
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const Spacer(),

            // 3. LIVE pill + Viewers Counter (Right)
            ValueListenableBuilder<int>(
              valueListenable: RewardLiveService.instance.viewerCountNotifier,
              builder: (context, viewers, _) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.15)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B30),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Icon(Icons.remove_red_eye, color: Colors.white70, size: 13),
                      const SizedBox(width: 3),
                      Text(
                        _formatViewerCount(viewers),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatViewerCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
  }
}
