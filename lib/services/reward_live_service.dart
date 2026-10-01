import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/environment.dart';
import '../models/reward_live_model.dart';
import 'backend_service.dart';
import 'micro_job_service.dart';
import 'reward_live_media_service.dart';

class RewardLiveService {
  RewardLiveService._internal();
  static final RewardLiveService instance = RewardLiveService._internal();

  // State Notifiers
  final ValueNotifier<RewardLiveState?> liveStateNotifier = ValueNotifier<RewardLiveState?>(null);
  final ValueNotifier<List<RewardDefinition>> rewardDefinitionsNotifier = ValueNotifier<List<RewardDefinition>>([]);
  final ValueNotifier<List<RewardLiveParticipant>> inviteesNotifier = ValueNotifier<List<RewardLiveParticipant>>([]);
  final ValueNotifier<int> viewerCountNotifier = ValueNotifier<int>(12480);
  final ValueNotifier<bool> isHostLiveNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isMyUserHostNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isMyUserInviteeNotifier = ValueNotifier<bool>(false);

  // Synchronized server clock offset: estimatedServerNow = DateTime.now().toUtc() + _serverTimeOffset
  Duration _serverTimeOffset = Duration.zero;
  Duration get serverTimeOffset => _serverTimeOffset;

  RealtimeChannel? _liveStateChannel;
  RealtimeChannel? _inviteesChannel;
  Timer? _viewerJitterTimer;
  Timer? _serverTimeSyncTimer;
  bool _isInitialized = false;

  final Set<String> _claimedCyclesLocal = <String>{};

  // Active 50-Second Gift Rush Pool Notifier
  final ValueNotifier<List<GiftRushPoolItem>> rushPoolNotifier = ValueNotifier<List<GiftRushPoolItem>>([]);
  int _lastGeneratedRushCycle = -1;

  // Default Reward Live State fallback (3-minute cycle: 2-min active gift drop + 1-min preparation)
  static final RewardLiveState defaultFallbackState = RewardLiveState(
    id: '00000000-0000-0000-0000-000000000001',
    status: 'ACTIVE',
    liveStartedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 10)),
    rewardIntervalSeconds: 180, // 3 minutes total
    claimWindowSeconds: 120,    // 2 minutes active gift drop window
    cyclePointPool: 100,
    activityMode: 'ACTIVE',
  );

  // Strictly the 20 Official XapZap Gifts (Capped <= 100 points, 10,000 pts = $1.00 USD)
  static final List<RewardDefinition> defaultDefinitions = [
    RewardDefinition(id: 'xapzap_universe', name: 'XapZap Universe', icon: '🌌', category: 'spectacular', animationType: 'galaxy_portal', pointValue: 100, rarity: 'mythic', defaultStock: 2, weight: 10),
    RewardDefinition(id: 'thunder_falcon', name: 'Thunder Falcon', icon: '🦅', category: 'animals', animationType: 'dragon_fly', pointValue: 40, rarity: 'epic', defaultStock: 2, weight: 25),
    RewardDefinition(id: 'fire_phoenix', name: 'Fire Phoenix', icon: '🔥', category: 'fantasy', animationType: 'dragon_fly', pointValue: 50, rarity: 'legendary', defaultStock: 2, weight: 20),
    RewardDefinition(id: 'leon_and_lion', name: 'Leon and Lion', icon: '🦁', category: 'animals', animationType: 'dragon_fly', pointValue: 35, rarity: 'epic', defaultStock: 2, weight: 30),
    RewardDefinition(id: 'zeus', name: 'Zeus', icon: '⚡', category: 'spectacular', animationType: 'galaxy_portal', pointValue: 90, rarity: 'mythic', defaultStock: 2, weight: 12),
    RewardDefinition(id: 'lion', name: 'Lion', icon: '🦁', category: 'animals', animationType: 'puppy_run', pointValue: 30, rarity: 'rare', defaultStock: 2, weight: 35),
    RewardDefinition(id: 'golden_sports_car', name: 'Golden Sports Car', icon: '🚗', category: 'vehicles', animationType: 'sports_car', pointValue: 60, rarity: 'legendary', defaultStock: 2, weight: 18),
    RewardDefinition(id: 'dragon_flame', name: 'Dragon Flame', icon: '🔥', category: 'fantasy', animationType: 'dragon_fly', pointValue: 70, rarity: 'legendary', defaultStock: 2, weight: 15),
    RewardDefinition(id: 'dragon_phoenix', name: 'Dragon/Phoenix', icon: '🐉', category: 'fantasy', animationType: 'dragon_fly', pointValue: 80, rarity: 'mythic', defaultStock: 2, weight: 14),
    RewardDefinition(id: 'castle_fantasy', name: 'Castle Fantasy', icon: '🏰', category: 'fantasy', animationType: 'galaxy_portal', pointValue: 45, rarity: 'epic', defaultStock: 2, weight: 25),
    RewardDefinition(id: 'dolphin', name: 'Dolphin', icon: '🐬', category: 'animals', animationType: 'puppy_jump', pointValue: 20, rarity: 'rare', defaultStock: 2, weight: 45),
    RewardDefinition(id: 'rocket', name: 'Rocket', icon: '🚀', category: 'vehicles', animationType: 'rocket_launch', pointValue: 55, rarity: 'legendary', defaultStock: 2, weight: 20),
    RewardDefinition(id: 'interstellar', name: 'Interstellar', icon: '🌌', category: 'spectacular', animationType: 'galaxy_portal', pointValue: 85, rarity: 'mythic', defaultStock: 2, weight: 12),
    RewardDefinition(id: 'falcon', name: 'Falcon', icon: '🦅', category: 'animals', animationType: 'dragon_fly', pointValue: 25, rarity: 'rare', defaultStock: 2, weight: 40),
    RewardDefinition(id: 'sports_car', name: 'Sports Car', icon: '🏎️', category: 'vehicles', animationType: 'sports_car', pointValue: 35, rarity: 'rare', defaultStock: 2, weight: 35),
    RewardDefinition(id: 'unicorn_fantasy', name: 'Unicorn Fantasy', icon: '🦄', category: 'fantasy', animationType: 'unicorn_rainbow', pointValue: 50, rarity: 'legendary', defaultStock: 2, weight: 22),
    RewardDefinition(id: 'private_jet', name: 'Private Jet', icon: '✈️', category: 'vehicles', animationType: 'sports_car', pointValue: 65, rarity: 'legendary', defaultStock: 2, weight: 16),
    RewardDefinition(id: 'whale_diving', name: 'Whale Diving', icon: '🐋', category: 'animals', animationType: 'puppy_jump', pointValue: 30, rarity: 'rare', defaultStock: 2, weight: 35),
    RewardDefinition(id: 'fireworks', name: 'Fireworks', icon: '🎆', category: 'spectacular', animationType: 'float_burst', pointValue: 20, rarity: 'uncommon', defaultStock: 2, weight: 50),
    RewardDefinition(id: 'galaxy', name: 'Galaxy', icon: '🌌', category: 'spectacular', animationType: 'galaxy_portal', pointValue: 75, rarity: 'legendary', defaultStock: 2, weight: 15),
  ];

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    liveStateNotifier.value = defaultFallbackState;
    rewardDefinitionsNotifier.value = defaultDefinitions;

    Future.wait([
      syncServerTime().catchError((_) {}),
      fetchLiveState().catchError((_) {}),
      fetchRewardDefinitions().catchError((_) {}),
      fetchActiveInvitees().catchError((_) {}),
    ]);
    _subscribeRealtime();

    // Periodic lightweight server-time re-synchronization (every 5 minutes)
    _serverTimeSyncTimer?.cancel();
    _serverTimeSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) => syncServerTime());

    // Ambient viewer count simulation
    _viewerJitterTimer?.cancel();
    final random = Random();
    _viewerJitterTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      final change = random.nextInt(9) - 4;
      viewerCountNotifier.value = (viewerCountNotifier.value + change).clamp(11800, 14200);
    });
  }

  // -------------------------------------------------------------
  // SERVER TIME SYNCHRONIZATION
  // -------------------------------------------------------------
  Future<void> syncServerTime() async {
    try {
      final clientBefore = DateTime.now().toUtc();
      final res = await Supabase.instance.client.rpc('get_server_time');
      final clientAfter = DateTime.now().toUtc();
      if (res != null) {
        final serverTime = DateTime.tryParse(res.toString())?.toUtc();
        if (serverTime != null) {
          final roundTripHalf = clientAfter.difference(clientBefore) ~/ 2;
          final adjustedClientNow = clientAfter.subtract(roundTripHalf);
          _serverTimeOffset = serverTime.difference(adjustedClientNow);
        }
      }
    } catch (_) {
      // Keep existing offset or 0 if unreachable
    }
  }

  DateTime getEstimatedServerNow() {
    return DateTime.now().toUtc().add(_serverTimeOffset);
  }

  // -------------------------------------------------------------
  // DETERMINISTIC CYCLE CALCULATIONS (Client-Side)
  // -------------------------------------------------------------
  int calculateCurrentCycle([RewardLiveState? state]) {
    final live = state ?? liveStateNotifier.value ?? defaultFallbackState;
    final now = getEstimatedServerNow();
    final elapsedSeconds = now.difference(live.liveStartedAt).inSeconds;
    if (elapsedSeconds < 0) return 0;
    return elapsedSeconds ~/ live.rewardIntervalSeconds;
  }

  DateTime calculateNextRewardTimestamp([RewardLiveState? state]) {
    final live = state ?? liveStateNotifier.value ?? defaultFallbackState;
    final currentCycle = calculateCurrentCycle(live);
    return live.liveStartedAt.add(Duration(seconds: (currentCycle + 1) * live.rewardIntervalSeconds));
  }

  int calculateSecondsRemaining([RewardLiveState? state]) {
    final nextTime = calculateNextRewardTimestamp(state);
    final now = getEstimatedServerNow();
    final diff = nextTime.difference(now).inSeconds;
    return diff > 0 ? diff : 0;
  }

  RewardDefinition getDeterministicRewardForCycle(int cycleNumber) {
    final list = rewardDefinitionsNotifier.value.isNotEmpty
        ? rewardDefinitionsNotifier.value
        : defaultDefinitions;

    if (list.isEmpty) return defaultDefinitions.first;

    final state = liveStateNotifier.value ?? defaultFallbackState;
    final seed = Object.hash(state.id, cycleNumber).abs();

    final totalWeight = list.fold<int>(0, (sum, item) => sum + (item.enabled ? item.weight : 0));
    if (totalWeight <= 0) return list.first;

    final target = seed % totalWeight;
    int cumulative = 0;
    for (final def in list) {
      if (!def.enabled) continue;
      cumulative += def.weight;
      if (target < cumulative) {
        return def;
      }
    }
    return list.first;
  }

  bool isCycleClaimedLocally(int cycleNumber) {
    final state = liveStateNotifier.value ?? defaultFallbackState;
    final key = '${state.id}_$cycleNumber';
    return _claimedCyclesLocal.contains(key);
  }

  // -------------------------------------------------------------
  // FETCH REWARD LIVE STATE FROM SUPABASE
  // -------------------------------------------------------------
  Future<void> fetchLiveState() async {
    try {
      final res = await Supabase.instance.client
          .from('reward_live_state')
          .select('*')
          .eq('status', 'ACTIVE')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (res != null) {
        final state = RewardLiveState.fromMap(res);
        liveStateNotifier.value = state;
        _updateUserHostState(state);
      } else {
        // Auto-seed default live state row if DB table is currently empty
        try {
          final defaultRow = {
            'id': defaultFallbackState.id,
            'status': 'ACTIVE',
            'live_started_at': DateTime.now().toUtc().subtract(const Duration(minutes: 10)).toIso8601String(),
            'reward_interval_seconds': 180,
            'claim_window_seconds': 120,
            'cycle_point_pool': 100,
            'activity_mode': 'ACTIVE',
          };
          final inserted = await Supabase.instance.client
              .from('reward_live_state')
              .upsert(defaultRow)
              .select()
              .maybeSingle();
          if (inserted != null) {
            final state = RewardLiveState.fromMap(inserted);
            liveStateNotifier.value = state;
            _updateUserHostState(state);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> fetchRewardDefinitions() async {
    try {
      final res = await Supabase.instance.client
          .from('reward_definitions')
          .select('*')
          .eq('enabled', true)
          .order('display_order', ascending: true);

      if (res.isNotEmpty) {
        final defs = res.map((m) => RewardDefinition.fromMap(m)).toList();
        rewardDefinitionsNotifier.value = defs;
      }
    } catch (_) {}
  }

  Future<void> fetchActiveInvitees() async {
    try {
      final state = liveStateNotifier.value ?? defaultFallbackState;
      final res = await Supabase.instance.client
          .from('reward_live_invitees')
          .select('id, live_id, user_id, status, joined_at, microphone_enabled, camera_enabled')
          .eq('live_id', state.id)
          .eq('status', 'ACTIVE')
          .order('joined_at', ascending: true)
          .limit(50);

      final userIds = res.map((m) => m['user_id']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
      final profilesMap = <String, Map<String, dynamic>>{};

      if (userIds.isNotEmpty) {
        final profilesRes = await Supabase.instance.client
            .from('profiles')
            .select('id, username, display_name, avatar_url')
            .inFilter('id', userIds);

        for (final p in profilesRes) {
          final id = p['id']?.toString() ?? '';
          if (id.isNotEmpty) profilesMap[id] = p;
        }
      }

      final participants = res.map((item) {
        final uid = item['user_id']?.toString() ?? '';
        final prof = profilesMap[uid];
        return RewardLiveParticipant(
          userId: uid,
          displayName: (prof?['display_name'] as String?)?.trim() ?? (prof?['username'] as String?)?.trim() ?? 'Guest',
          username: (prof?['username'] as String?)?.trim() ?? '',
          avatarUrl: (prof?['avatar_url'] as String?)?.trim() ?? '',
          joinedAt: DateTime.tryParse(item['joined_at']?.toString() ?? '') ?? DateTime.now(),
          micEnabled: item['microphone_enabled'] != false,
        );
      }).toList();

      inviteesNotifier.value = participants;

      final currentUid = Supabase.instance.client.auth.currentUser?.id;
      if (currentUid != null) {
        isMyUserInviteeNotifier.value = participants.any((p) => p.userId == currentUid);
      }

      // Sync LiveKit media session
      LiveKitMediaSessionManager.instance.syncPublishersState(
        hasHost: state.hasHost,
        activeInviteesCount: participants.length,
        streamId: state.currentStreamId,
      );
    } catch (_) {}
  }

  void _updateUserHostState(RewardLiveState state) {
    final currentUid = Supabase.instance.client.auth.currentUser?.id;
    isHostLiveNotifier.value = state.hasHost;
    isMyUserHostNotifier.value = currentUid != null && state.currentHostId == currentUid;

    // Sync LiveKit Media Session
    LiveKitMediaSessionManager.instance.syncPublishersState(
      hasHost: state.hasHost,
      activeInviteesCount: inviteesNotifier.value.length,
      streamId: state.currentStreamId,
    );
  }

  // -------------------------------------------------------------
  // REALTIME SUBSCRIPTIONS
  // -------------------------------------------------------------
  void _subscribeRealtime() {
    try {
      _liveStateChannel?.unsubscribe();
      _liveStateChannel = Supabase.instance.client.channel('public:reward_live_state');
      _liveStateChannel?.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'reward_live_state',
        callback: (payload) {
          final rec = payload.newRecord;
          if (rec.isNotEmpty) {
            final state = RewardLiveState.fromMap(rec);
            liveStateNotifier.value = state;
            _updateUserHostState(state);
          }
        },
      ).subscribe();

      _inviteesChannel?.unsubscribe();
      _inviteesChannel = Supabase.instance.client.channel('public:reward_live_invitees');
      _inviteesChannel?.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'reward_live_invitees',
        callback: (_) {
          fetchActiveInvitees();
        },
      ).subscribe();
    } catch (_) {}
  }

  // -------------------------------------------------------------
  // 2-MINUTE GIFT RUSH POOL GENERATOR (Split across 2 mins, 4 appearances per gift)
  // -------------------------------------------------------------
  List<GiftRushPoolItem> generateGiftRushPoolForCycle(int cycleNumber) {
    if (_lastGeneratedRushCycle == cycleNumber && rushPoolNotifier.value.isNotEmpty) {
      return rushPoolNotifier.value;
    }
    _lastGeneratedRushCycle = cycleNumber;

    final catalog = rewardDefinitionsNotifier.value.isNotEmpty
        ? rewardDefinitionsNotifier.value
        : defaultDefinitions;

    final random = Random(Object.hash(liveStateNotifier.value?.id ?? '0', cycleNumber));

    // 1. Full shuffled sequence across all 20 gifts for rich variety
    final allGifts = List<RewardDefinition>.from(catalog)..shuffle(random);

    // 2. Schedule 3 sequential appearance rounds of all gifts (3 rounds * 20 gifts = 60 appearances)
    const int roundsCount = 3;
    final List<GiftRushPoolItem> sequence = [];

    int globalIndex = 0;
    for (int round = 1; round <= roundsCount; round++) {
      final roundGifts = List<RewardDefinition>.from(allGifts)..shuffle(Random(cycleNumber * 100 + round));
      for (final def in roundGifts) {
        sequence.add(GiftRushPoolItem(
          reward: def,
          totalStock: 5,     // Ample stock per gift appearance
          availableStock: 5, // Ample stock per gift appearance
          x: 0.20 + (random.nextDouble() * 0.55),
          y: 0.25 + (random.nextDouble() * 0.40),
          speedX: (random.nextBool() ? 1 : -1) * (0.0018 + random.nextDouble() * 0.0018),
          speedY: (random.nextBool() ? 1 : -1) * (0.0014 + random.nextDouble() * 0.0016),
          instanceKey: '${def.id}_cycle_${cycleNumber}_r${round}_$globalIndex',
        ));
        globalIndex++;
      }
    }

    rushPoolNotifier.value = sequence;
    return sequence;
  }

  // -------------------------------------------------------------
  // REWARD CLAIM (Direct Real-time Sync to creator_balances)
  // -------------------------------------------------------------
  Future<RewardClaimResult> claimReward({
    required int cycleNumber,
    required String rewardId,
    RewardDefinition? specificReward,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return RewardClaimResult(
        success: false,
        status: 'UNAUTHENTICATED',
        message: 'Please sign in to claim rewards.',
      );
    }

    final reward = specificReward ?? getDeterministicRewardForCycle(cycleNumber);

    // Find and decrement in active rush pool
    final pool = rushPoolNotifier.value;
    final poolItem = pool.firstWhere(
      (item) => item.reward.id == reward.id,
      orElse: () => pool.isNotEmpty ? pool.first : GiftRushPoolItem(
        reward: reward,
        totalStock: 100,
        availableStock: 100,
        instanceKey: 'fallback',
      ),
    );

    if (poolItem.availableStock <= 0) {
      return RewardClaimResult(
        success: false,
        status: 'SOLD_OUT',
        message: '${reward.name} is all out for this drop!',
      );
    }

    // Decrement stock in rush pool
    poolItem.claimOne();
    rushPoolNotifier.value = List<GiftRushPoolItem>.from(pool);

    final points = reward.pointValue;
    final rewardAmountUsd = points / 10000.0; // 10,000 pts = $1.00 USD

    // Directly write to creator_balances in Supabase in real-time
    final state = liveStateNotifier.value ?? defaultFallbackState;
    final uniqueTx = 'rush_${state.id}_${cycleNumber}_${reward.id}_${DateTime.now().millisecondsSinceEpoch}';
    unawaited(MicroJobService.rewardUser(uniqueTx, rewardAmountUsd));

    return RewardClaimResult(
      success: true,
      status: 'SUCCESS',
      points: points,
      rewardId: reward.id,
      rewardName: reward.name,
      rewardIcon: reward.icon,
      rarity: reward.rarity,
      cycleNumber: cycleNumber,
      newBalanceUsd: MicroJobService.userBalanceNotifier.value,
      message: '+${reward.pointValue} Points Claimed!',
    );
  }

  // -------------------------------------------------------------
  // FLUSH ACCUMULATED REWARDS TO DB AT THE END OF EACH ROUND
  // -------------------------------------------------------------
  Future<void> flushPendingCycleReward() async {
    // Balances are synced directly on claim, reload from DB to ensure consistency
    await MicroJobService.reloadUserBalance();
  }

  // -------------------------------------------------------------
  // HOST MANAGEMENT (Entry Fee: 1,000 Points = $0.10 USD)
  // -------------------------------------------------------------
  Future<Map<String, dynamic>> requestBecomeHost() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return {'success': false, 'error': 'Please sign in first.'};
    }

    // Host entry fee: 1,000 points = $0.10 USD
    const hostFeePoints = 1000;
    const hostFeeUsd = hostFeePoints / 10000.0; // $0.10

    final userBal = MicroJobService.userBalanceNotifier.value;
    if (userBal < hostFeeUsd) {
      return {
        'success': false,
        'error': 'You need at least 1,000 Points (\$0.10) to start hosting. Current balance: \$${userBal.toStringAsFixed(4)} (${(userBal * 10000).toInt()} pts).',
      };
    }

    final state = liveStateNotifier.value ?? defaultFallbackState;
    final token = Supabase.instance.client.auth.currentSession?.accessToken;

    try {
      final url = Uri.parse('${Environment.supabaseUrl}/functions/v1/reward-live-host');
      final res = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token ?? Environment.supabaseAnonKey}',
          'apikey': Environment.supabaseAnonKey,
        },
        body: jsonEncode({
          'action': 'request_host',
          'live_id': state.id,
          'user_id': user.id,
        }),
      );

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        final token = data['livekit_token'] as String?;
        final url = data['livekit_url'] as String? ?? 'wss://xapzap-bu7rsekx.livekit.cloud';
        LiveKitMediaSessionManager.instance.setMediaToken(token, url);
        if (token != null && token.isNotEmpty) {
          await LiveKitMediaSessionManager.instance.connectLiveKitRoom(
            url: url,
            token: token,
            isHost: true,
          );
        }
        await MicroJobService.deductUserBalance(hostFeeUsd);
        await fetchLiveState();
      }
      return data;
    } catch (e) {
      try {
        final prof = await BackendService.getProfileByUserId(user.id);
        final dName = (prof?.data['displayName'] as String?)?.trim() ?? 'Host';
        final avatar = (prof?.data['avatarUrl'] as String?)?.trim() ?? '';
        final streamId = 'stream_${state.id}_${DateTime.now().millisecondsSinceEpoch}';

        await Supabase.instance.client
            .from('reward_live_state')
            .update({
              'current_host_id': user.id,
              'current_host_name': dName,
              'current_host_avatar': avatar,
              'current_stream_id': streamId,
              'activity_mode': 'ACTIVE',
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', state.id);

        await MicroJobService.deductUserBalance(hostFeeUsd);
        await fetchLiveState();
        return {'success': true, 'status': 'ACTIVE', 'stream_id': streamId};
      } catch (err) {
        return {'success': false, 'error': err.toString()};
      }
    }
  }

  Future<void> leaveHost() async {
    final state = liveStateNotifier.value ?? defaultFallbackState;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    await LiveKitMediaSessionManager.instance.disconnectLiveKitRoom();

    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    try {
      final url = Uri.parse('${Environment.supabaseUrl}/functions/v1/reward-live-host');
      await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token ?? Environment.supabaseAnonKey}',
          'apikey': Environment.supabaseAnonKey,
        },
        body: jsonEncode({
          'action': 'leave_host',
          'live_id': state.id,
          'user_id': user.id,
        }),
      );
    } catch (_) {
      await Supabase.instance.client
          .from('reward_live_state')
          .update({
            'current_host_id': null,
            'current_host_name': null,
            'current_host_avatar': null,
            'current_stream_id': null,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', state.id)
          .eq('current_host_id', user.id);
    }

    await fetchLiveState();
  }

  // -------------------------------------------------------------
  // INVITEE MANAGEMENT (Entry Fee: 500 Points = $0.05 USD)
  // -------------------------------------------------------------
  Future<Map<String, dynamic>> requestJoinVoice() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return {'success': false, 'error': 'Please sign in first.'};
    }

    // Invitee entry fee: 500 points = $0.05 USD
    const inviteeFeePoints = 500;
    const inviteeFeeUsd = inviteeFeePoints / 10000.0; // $0.05

    final userBal = MicroJobService.userBalanceNotifier.value;
    if (userBal < inviteeFeeUsd) {
      return {
        'success': false,
        'error': 'You need at least 500 Points (\$0.05) to join voice stage. Current balance: \$${userBal.toStringAsFixed(4)} (${(userBal * 10000).toInt()} pts).',
      };
    }

    final state = liveStateNotifier.value ?? defaultFallbackState;
    final token = Supabase.instance.client.auth.currentSession?.accessToken;

    try {
      final url = Uri.parse('${Environment.supabaseUrl}/functions/v1/reward-live-host');
      final res = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token ?? Environment.supabaseAnonKey}',
          'apikey': Environment.supabaseAnonKey,
        },
        body: jsonEncode({
          'action': 'request_invitee',
          'live_id': state.id,
          'user_id': user.id,
        }),
      );

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        final token = data['livekit_token'] as String?;
        final url = data['livekit_url'] as String? ?? 'wss://xapzap-bu7rsekx.livekit.cloud';
        LiveKitMediaSessionManager.instance.setMediaToken(token, url);
        if (token != null && token.isNotEmpty) {
          await LiveKitMediaSessionManager.instance.connectLiveKitRoom(
            url: url,
            token: token,
            isInvitee: true,
          );
        }
        await MicroJobService.deductUserBalance(inviteeFeeUsd);
        await fetchActiveInvitees();
      }
      return data;
    } catch (e) {
      try {
        await Supabase.instance.client
            .from('reward_live_invitees')
            .upsert(
              {
                'live_id': state.id,
                'user_id': user.id,
                'status': 'ACTIVE',
                'joined_at': DateTime.now().toUtc().toIso8601String(),
                'microphone_enabled': true,
                'camera_enabled': false,
              },
              onConflict: 'live_id,user_id',
            );
        await MicroJobService.deductUserBalance(inviteeFeeUsd);
        await fetchActiveInvitees();
        return {'success': true, 'status': 'ACTIVE'};
      } catch (err) {
        return {'success': false, 'error': err.toString()};
      }
    }
  }

  Future<void> leaveVoice() async {
    final state = liveStateNotifier.value ?? defaultFallbackState;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    await LiveKitMediaSessionManager.instance.disconnectLiveKitRoom();

    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    try {
      final url = Uri.parse('${Environment.supabaseUrl}/functions/v1/reward-live-host');
      await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token ?? Environment.supabaseAnonKey}',
          'apikey': Environment.supabaseAnonKey,
        },
        body: jsonEncode({
          'action': 'leave_invitee',
          'live_id': state.id,
          'user_id': user.id,
        }),
      );
    } catch (_) {
      await Supabase.instance.client
          .from('reward_live_invitees')
          .update({
            'status': 'LEFT',
            'left_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('live_id', state.id)
          .eq('user_id', user.id);
    }

    await fetchActiveInvitees();
  }

  void dispose() {
    _serverTimeSyncTimer?.cancel();
    _viewerJitterTimer?.cancel();
    _liveStateChannel?.unsubscribe();
    _inviteesChannel?.unsubscribe();
  }
}
