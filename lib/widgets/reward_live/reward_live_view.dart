import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../models/reward_live_model.dart';
import '../../services/ad_gate_service.dart';
import '../../services/ad_helper.dart';
import '../../services/gift_sound_service.dart';
import '../../services/reward_live_service.dart';
import '../../screens/perform_tasks_screen.dart';
import 'reward_live_animation_layer.dart';
import 'reward_live_countdown_widget.dart';
import 'reward_live_host_header.dart';
import 'reward_live_middle_notice.dart';
import 'reward_live_video_surface.dart';
import 'reward_live_voice_participants.dart';
import 'become_host_sheet.dart';

class RewardLiveView extends StatefulWidget {
  const RewardLiveView({super.key});

  @override
  State<RewardLiveView> createState() => _RewardLiveViewState();
}

class _RewardLiveViewState extends State<RewardLiveView>
    with AutomaticKeepAliveClientMixin<RewardLiveView> {
  @override
  bool get wantKeepAlive => true;

  final RewardLiveService _service = RewardLiveService.instance;
  bool _isClaimWindowActive = false;

  // Banner Ad State
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _isClaimWindowActive = _service.calculateSecondsRemaining() > 60;
    GiftSoundService.instance.init();
    _service.initialize();
    _loadBannerAd();
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: AdHelper.banner,
      size: AdSize.banner,
      request: AdHelper.financialRequest,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _isBannerAdLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('[RewardLive] Banner Ad failed to load: $error');
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    GiftSoundService.instance.dispose();
    _service.flushPendingCycleReward();
    super.dispose();
  }

  Future<void> _handleRewardTapped(RewardDefinition reward, Offset screenPos) async {
    // 1. Play sound immediately on tap for all gifts
    GiftSoundService.instance.playGiftSound(reward);

    // 2. Claim reward in memory pool
    final cycle = _service.calculateCurrentCycle();
    await _service.claimReward(
      cycleNumber: cycle,
      rewardId: reward.id,
      specificReward: reward,
    );
  }

  void _onClaimWindowStateChanged(bool isActive) {
    if (!mounted) return;
    if (_isClaimWindowActive == isActive) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final wasActive = _isClaimWindowActive;
      setState(() => _isClaimWindowActive = isActive);
      if (wasActive && !isActive) {
        // 2-Min Gift Showing Window finished -> Show Rewarded Ad after the 2-minute countdown!
        XapZapAdGateService.instance.showRewardedAd(placement: 'reward_live_window_end');
        _service.flushPendingCycleReward();
      }
    });
  }

  void _openBecomeHostSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BecomeHostSheet(
        onHostStarted: () {
          _service.fetchLiveState();
        },
        onVoiceJoined: () {
          _service.fetchActiveInvitees();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. VIDEO SURFACE / 24/7 AMBIENT LIVE STAGE (Full Screen Background)
          Positioned.fill(
            child: ValueListenableBuilder<RewardLiveState?>(
              valueListenable: _service.liveStateNotifier,
              builder: (context, state, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: _service.isMyUserHostNotifier,
                  builder: (context, isMeHost, _) {
                    return RewardLiveVideoSurface(
                      liveState: state,
                      isMyUserHost: isMeHost,
                    );
                  },
                );
              },
            ),
          ),

          // 2. INTERACTIVE FLOATING 3D REWARDS ANIMATION LAYER (Full Screen Overlay)
          Positioned.fill(
            child: ValueListenableBuilder<RewardLiveState?>(
              valueListenable: _service.liveStateNotifier,
              builder: (context, state, _) {
                final cycle = _service.calculateCurrentCycle(state);
                final reward = _service.getDeterministicRewardForCycle(cycle);

                return RewardLiveAnimationLayer(
                  isClaimWindowActive: _isClaimWindowActive,
                  currentCycleReward: reward,
                  onRewardTapped: _handleRewardTapped,
                );
              },
            ),
          ),

          // 3. TOP HOST HEADER & BANNER AD COLUMN
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Host Header & Viewers Count
                ValueListenableBuilder<RewardLiveState?>(
                  valueListenable: _service.liveStateNotifier,
                  builder: (context, state, _) {
                    return RewardLiveHostHeader(
                      liveState: state,
                      onOpenHostSheet: _openBecomeHostSheet,
                    );
                  },
                ),

                // Prominent Banner Ad below Reward Live & Viewers Count
                if (_isBannerAdLoaded && _bannerAd != null)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12, width: 0.8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    width: _bannerAd!.size.width.toDouble(),
                    height: _bannerAd!.size.height.toDouble(),
                    child: AdWidget(ad: _bannerAd!),
                  ),
              ],
            ),
          ),

          // 4. FAINT TRANSPARENT NOTICE OVERLAY IN THE MIDDLE OF THE SCREEN
          const Positioned.fill(
            child: RewardLiveMiddleNoticeOverlay(),
          ),

          // 5. VOICE PARTICIPANTS TRAY (Max 50)
          Positioned(
            left: 0,
            right: 0,
            bottom: 194,
            child: ValueListenableBuilder<List<RewardLiveParticipant>>(
              valueListenable: _service.inviteesNotifier,
              builder: (context, invitees, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: _service.isMyUserInviteeNotifier,
                  builder: (context, isInvitee, _) {
                    return RewardLiveVoiceParticipants(
                      invitees: invitees,
                      isMyUserInvitee: isInvitee,
                      onJoinVoice: () => _service.requestJoinVoice(),
                      onLeaveVoice: () => _service.leaveVoice(),
                    );
                  },
                );
              },
            ),
          ),

          // 6. TASKS BUTTON (Positioned Above Countdown Card)
          Positioned(
            right: 14,
            bottom: 148,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PerformTasksScreen()),
                  );
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF161B2E), Color(0xFF2A1B4E)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.85), width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withOpacity(0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.assignment_turned_in_rounded, color: Color(0xFFFFD700), size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Other Tasks & Jobs',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFFFD700), size: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 7. ISOLATED REWARD COUNTDOWN WIDGET
          Positioned(
            left: 0,
            right: 0,
            bottom: 64,
            child: RewardLiveCountdownWidget(
              onClaimWindowStateChanged: _onClaimWindowStateChanged,
            ),
          ),

          // 7. BOTTOM ACTION BAR (Host Live / Voice Invitees)
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: Row(
              children: [
                // 1. Host Action Button
                ValueListenableBuilder<bool>(
                  valueListenable: _service.isMyUserHostNotifier,
                  builder: (context, isHost, _) {
                    if (isHost) {
                      return Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await _service.leaveHost();
                          },
                          icon: const Icon(Icons.call_end, color: Colors.white, size: 16),
                          label: const Text('End Host', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 3,
                          ),
                        ),
                      );
                    }

                    return Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _openBecomeHostSheet,
                        icon: const Icon(Icons.videocam_rounded, color: Colors.white, size: 18),
                        label: const Text('Host Live', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE53935),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 3,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),

                // 2. Voice Invitees Action Button
                ValueListenableBuilder<bool>(
                  valueListenable: _service.isMyUserInviteeNotifier,
                  builder: (context, isInvitee, _) {
                    return Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (isInvitee) {
                            _service.leaveVoice();
                          } else {
                            _service.requestJoinVoice();
                          }
                        },
                        icon: Icon(
                          isInvitee ? Icons.mic_off : Icons.mic,
                          color: isInvitee ? Colors.redAccent : const Color(0xFF00E676),
                          size: 18,
                        ),
                        label: Text(
                          isInvitee ? 'Leave Voice' : 'Join Voice Stage',
                          style: TextStyle(
                            color: isInvitee ? Colors.redAccent : const Color(0xFF00E676),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isInvitee
                              ? Colors.redAccent.withOpacity(0.15)
                              : const Color(0xFF00E676).withOpacity(0.15),
                          foregroundColor: isInvitee ? Colors.redAccent : const Color(0xFF00E676),
                          side: BorderSide(
                            color: isInvitee
                                ? Colors.redAccent.withOpacity(0.4)
                                : const Color(0xFF00E676).withOpacity(0.4),
                            width: 1.2,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

