class RewardLiveState {
  final String id;
  final String status;
  final DateTime liveStartedAt;
  final int rewardIntervalSeconds;
  final int claimWindowSeconds;
  final int cyclePointPool;
  final int lastRewardCycle;
  final String? currentHostId;
  final String? currentHostName;
  final String? currentHostAvatar;
  final String? currentStreamId;
  final String activityMode;

  RewardLiveState({
    required this.id,
    required this.status,
    required this.liveStartedAt,
    this.rewardIntervalSeconds = 180,
    this.claimWindowSeconds = 15,
    this.cyclePointPool = 1000,
    this.lastRewardCycle = 0,
    this.currentHostId,
    this.currentHostName,
    this.currentHostAvatar,
    this.currentStreamId,
    this.activityMode = 'ACTIVE',
  });

  bool get hasHost => currentHostId != null && currentHostId!.isNotEmpty;
  bool get isActive => status == 'ACTIVE';

  factory RewardLiveState.fromMap(Map<String, dynamic> map) {
    DateTime startedAt;
    final rawStarted = map['live_started_at'] ?? map['liveStartedAt'];
    if (rawStarted is String) {
      startedAt = DateTime.tryParse(rawStarted)?.toUtc() ?? DateTime.now().toUtc();
    } else if (rawStarted is DateTime) {
      startedAt = rawStarted.toUtc();
    } else {
      startedAt = DateTime.now().toUtc();
    }

    return RewardLiveState(
      id: map['id']?.toString() ?? '00000000-0000-0000-0000-000000000001',
      status: (map['status']?.toString() ?? 'ACTIVE').toUpperCase(),
      liveStartedAt: startedAt,
      rewardIntervalSeconds: (map['reward_interval_seconds'] ?? map['rewardIntervalSeconds'] as num?)?.toInt() ?? 180,
      claimWindowSeconds: (map['claim_window_seconds'] ?? map['claimWindowSeconds'] as num?)?.toInt() ?? 15,
      cyclePointPool: (map['cycle_point_pool'] ?? map['cyclePointPool'] as num?)?.toInt() ?? 1000,
      lastRewardCycle: (map['last_reward_cycle'] ?? map['lastRewardCycle'] as num?)?.toInt() ?? 0,
      currentHostId: map['current_host_id'] ?? map['currentHostId'],
      currentHostName: map['current_host_name'] ?? map['currentHostName'],
      currentHostAvatar: map['current_host_avatar'] ?? map['currentHostAvatar'],
      currentStreamId: map['current_stream_id'] ?? map['currentStreamId'],
      activityMode: (map['activity_mode'] ?? map['activityMode']?.toString() ?? 'ACTIVE').toUpperCase(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'status': status,
      'live_started_at': liveStartedAt.toIso8601String(),
      'reward_interval_seconds': rewardIntervalSeconds,
      'claim_window_seconds': claimWindowSeconds,
      'cycle_point_pool': cyclePointPool,
      'last_reward_cycle': lastRewardCycle,
      'current_host_id': currentHostId,
      'current_host_name': currentHostName,
      'current_host_avatar': currentHostAvatar,
      'current_stream_id': currentStreamId,
      'activity_mode': activityMode,
    };
  }
}

class RewardDefinition {
  final String id;
  final String name;
  final String icon;
  final String category; // cute, animals, fantasy, vehicles, romantic, funny, spectacular
  final String animationType; // puppy_run, sports_car, dragon_fly, rocket_launch, unicorn_rainbow, cupid_arrow, dancing_banana, galaxy_portal, float_burst
  final int pointValue;
  final String rarity; // common, rare, epic, legendary, mythic
  final int defaultStock;
  final int weight;
  final bool enabled;
  final int displayOrder;

  RewardDefinition({
    required this.id,
    required this.name,
    required this.icon,
    this.category = 'cute',
    this.animationType = 'float_burst',
    required this.pointValue,
    this.rarity = 'common',
    this.defaultStock = 100,
    this.weight = 100,
    this.enabled = true,
    this.displayOrder = 0,
  });

  factory RewardDefinition.fromMap(Map<String, dynamic> map) {
    return RewardDefinition(
      id: map['id']?.toString() ?? 'reward_gift',
      name: map['name']?.toString() ?? 'Gift',
      icon: map['icon']?.toString() ?? '🎁',
      category: map['category']?.toString() ?? 'cute',
      animationType: map['animation_type'] ?? map['animation']?.toString() ?? 'float_burst',
      pointValue: (map['point_value'] ?? map['pointValue'] as num?)?.toInt() ?? 10,
      rarity: map['rarity']?.toString() ?? 'common',
      defaultStock: (map['default_stock'] ?? map['stock'] as num?)?.toInt() ?? 100,
      weight: (map['weight'] as num?)?.toInt() ?? 100,
      enabled: map['enabled'] == true || map['enabled'] == 1,
      displayOrder: (map['display_order'] ?? map['displayOrder'] as num?)?.toInt() ?? 0,
    );
  }
}

class GiftRushPoolItem {
  final RewardDefinition reward;
  int totalStock;
  int availableStock;
  double x;
  double y;
  double speedX;
  double speedY;
  final String instanceKey;

  GiftRushPoolItem({
    required this.reward,
    required this.totalStock,
    required this.availableStock,
    this.x = 0.5,
    this.y = 0.5,
    this.speedX = 0.0,
    this.speedY = 0.0,
    required this.instanceKey,
  });

  bool get isAvailable => availableStock > 0;

  void claimOne() {
    if (availableStock > 0) {
      availableStock--;
    }
  }

  void resetForNewCycle() {
    availableStock = totalStock;
  }
}

class RewardLiveParticipant {
  final String userId;
  final String displayName;
  final String username;
  final String avatarUrl;
  final bool isHost;
  final bool isInvitee;
  final bool micEnabled;
  final DateTime joinedAt;

  RewardLiveParticipant({
    required this.userId,
    required this.displayName,
    required this.username,
    required this.avatarUrl,
    this.isHost = false,
    this.isInvitee = true,
    this.micEnabled = true,
    required this.joinedAt,
  });

  factory RewardLiveParticipant.fromMap(Map<String, dynamic> map) {
    return RewardLiveParticipant(
      userId: map['user_id'] ?? map['userId'] ?? '',
      displayName: map['displayName'] ?? map['display_name'] ?? 'Participant',
      username: map['username'] ?? '',
      avatarUrl: map['avatarUrl'] ?? map['avatar_url'] ?? '',
      isHost: map['is_host'] == true || map['isHost'] == true,
      isInvitee: map['is_invitee'] == true || map['isInvitee'] == true,
      micEnabled: map['microphone_enabled'] != false,
      joinedAt: DateTime.tryParse(map['joined_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class RewardClaimResult {
  final bool success;
  final String status;
  final int points;
  final String? rewardId;
  final String? rewardName;
  final String? rewardIcon;
  final String? rarity;
  final int? cycleNumber;
  final double? newBalanceUsd;
  final String message;

  RewardClaimResult({
    required this.success,
    required this.status,
    this.points = 0,
    this.rewardId,
    this.rewardName,
    this.rewardIcon,
    this.rarity,
    this.cycleNumber,
    this.newBalanceUsd,
    this.message = '',
  });

  factory RewardClaimResult.fromMap(Map<String, dynamic> map) {
    return RewardClaimResult(
      success: map['success'] == true,
      status: map['status']?.toString() ?? (map['success'] == true ? 'SUCCESS' : 'ERROR'),
      points: (map['points'] as num?)?.toInt() ?? 0,
      rewardId: map['reward_id']?.toString(),
      rewardName: map['reward_name']?.toString(),
      rewardIcon: map['reward_icon']?.toString(),
      rarity: map['rarity']?.toString(),
      cycleNumber: (map['cycle_number'] as num?)?.toInt(),
      newBalanceUsd: (map['new_balance_usd'] as num?)?.toDouble(),
      message: map['message']?.toString() ?? '',
    );
  }
}
