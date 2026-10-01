import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/reward_live_model.dart';
import '../../services/backend_service.dart';

class RewardLiveVoiceParticipants extends StatelessWidget {
  final List<RewardLiveParticipant> invitees;
  final VoidCallback? onJoinVoice;
  final VoidCallback? onLeaveVoice;
  final bool isMyUserInvitee;

  const RewardLiveVoiceParticipants({
    super.key,
    required this.invitees,
    this.onJoinVoice,
    this.onLeaveVoice,
    this.isMyUserInvitee = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isMyUserInvitee) {
      return Container(
        height: 48,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF00E676).withOpacity(0.18),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF00E676).withOpacity(0.5), width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.mic, color: Color(0xFF00E676), size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '🎙️ You are on Voice Stage (+500 pts/cycle)',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            TextButton.icon(
              onPressed: onLeaveVoice,
              icon: const Icon(Icons.close, color: Colors.redAccent, size: 14),
              label: const Text('Leave Stage', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 48,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          // Voice Room Title / Counter Pill
          InkWell(
            onTap: onJoinVoice,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF00E676).withOpacity(0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.mic, color: Color(0xFF00E676), size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'Invitees (${invitees.length}/50)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Scrollable Participant Avatars
          Expanded(
            child: invitees.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Stage is open (tap Join Voice Stage below)',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: invitees.length,
                    itemBuilder: (context, index) {
                      final participant = invitees[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: _VoiceParticipantTile(participant: participant),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _VoiceParticipantTile extends StatefulWidget {
  final RewardLiveParticipant participant;

  const _VoiceParticipantTile({required this.participant});

  @override
  State<_VoiceParticipantTile> createState() => _VoiceParticipantTileState();
}

class _VoiceParticipantTileState extends State<_VoiceParticipantTile> {
  bool _isFollowing = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _checkFollow();
  }

  Future<void> _checkFollow() async {
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null || me == widget.participant.userId) return;
    try {
      final following = await BackendService.isFollowing(me, widget.participant.userId);
      if (mounted) setState(() => _isFollowing = following);
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null || me == widget.participant.userId || _loading) return;

    setState(() => _loading = true);
    try {
      if (_isFollowing) {
        await BackendService.unfollowUser(widget.participant.userId);
        if (mounted) setState(() => _isFollowing = false);
      } else {
        await BackendService.followUser(widget.participant.userId);
        if (mounted) setState(() => _isFollowing = true);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showParticipantDetails(BuildContext context) {
    final me = Supabase.instance.client.auth.currentUser?.id;
    final isMe = me != null && me == widget.participant.userId;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161824),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                CircleAvatar(
                  radius: 36,
                  backgroundImage: widget.participant.avatarUrl.isNotEmpty
                      ? CachedNetworkImageProvider(widget.participant.avatarUrl)
                      : null,
                  child: widget.participant.avatarUrl.isEmpty
                      ? const Icon(Icons.person, size: 36, color: Colors.white)
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.participant.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.participant.username.isNotEmpty)
                  Text(
                    '@${widget.participant.username}',
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                const SizedBox(height: 16),
                if (!isMe)
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _toggleFollow();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isFollowing ? Colors.white24 : const Color(0xFF1DA1F2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        _isFollowing ? 'Unfollow' : 'Follow Participant',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showParticipantDetails(context),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF00E676), width: 1.5),
        ),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF1E2438),
              backgroundImage: widget.participant.avatarUrl.isNotEmpty
                  ? CachedNetworkImageProvider(widget.participant.avatarUrl)
                  : null,
              child: widget.participant.avatarUrl.isEmpty
                  ? const Icon(Icons.person, size: 18, color: Colors.white70)
                  : null,
            ),
            Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Color(0xFF00E676),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic, size: 8, color: Colors.black),
            ),
          ],
        ),
      ),
    );
  }
}
