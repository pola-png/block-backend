import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:xapzap/models/database_models.dart' as aw;
import '../models/chat.dart';
import '../services/backend_service.dart';
import '../services/chat_preview_cache.dart';
import '../services/chat_prefetch_service.dart';
import '../services/profile_preview_cache.dart';
import '../services/storage_service.dart';
import '../services/crypto_service.dart';
import '../services/chat_message_cache.dart';
import '../main.dart';
import 'individual_chat_screen.dart';
import 'new_chat_screen.dart';
import '../widgets/verification_badge.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with WidgetsBindingObserver, RouteAware {
  final TextEditingController _searchController = TextEditingController();
  List<Chat> _chats = <Chat>[];
  List<Chat> _filteredChats = [];
  RealtimeSubscription? _messagesSub;
  Timer? _timeRefreshTimer;
  String? _currentUserId;
  bool _isLoading = true;
  bool _isHydrating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CryptoService.ensureIdentityKeysAndPublish();
    final cachedChats = ChatPreviewCache.getAll();
    if (cachedChats.isNotEmpty) {
      _chats = cachedChats;
      _applyFilter();
      _isLoading = false;
    }
    _loadChats();
    _subscribeMessages();
    _timeRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _searchController.addListener(() {
      if (!mounted) return;
      setState(_applyFilter);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    _messagesSub?.close();
    _timeRefreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    String query = _searchController.text.toLowerCase();
    _filteredChats = _chats
        .where((chat) => chat.partnerName.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _loadChats() async {
    final me = await BackendService.getCurrentUser();
    if (me == null) return;
    _currentUserId = me.$id;

    try {
      final aw.RowList list = await BackendService.fetchChatsForUser(me.$id);
      final chats = list.rows
          .map((row) => _buildChatPreview(row, me.$id))
          .whereType<Chat>()
          .toList(growable: false)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (!mounted) return;
      setState(() {
        _chats = chats;
        _applyFilter();
        _isLoading = false;
      });
      ChatPreviewCache.setAll(chats);
      unawaited(ChatPrefetchService.preloadInbox());
      unawaited(_hydrateChats(list.rows, me.$id));
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Chat? _buildChatPreview(aw.Row row, String meId) {
    final data = row.data;
    // memberIds is stored as a comma-separated string.
    final rawIds = (data['memberIds'] as String?) ?? '';
    final userIds = rawIds
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (userIds.length < 2) return null;
    final partnerId =
        userIds.firstWhere((id) => id != meId, orElse: () => meId);
    if (partnerId == meId) return null;

    final lastMessage = _previewLastMessage(row);
    final timestamp = _chatTimestampFromRow(data);
    final cached = ChatMessageCache.get(row.$id);
    final unread = cached != null
        ? cached.messages.where((m) => !m.isSent && !m.isRead).length
        : _chatUnreadCountFromRow(data);
    final cachedProfile = BackendService.peekCachedProfileByUserId(partnerId);
    final cachedData = cachedProfile?.data ?? const <String, dynamic>{};
    final profilePreview =
        ProfilePreviewCache.getByUserId(partnerId);
    final cachedName = profilePreview?.displayName.trim().isNotEmpty == true
        ? profilePreview!.displayName.trim()
        : (cachedData['displayName'] as String?)?.trim();
    final cachedAvatarRaw = profilePreview?.avatarUrl.trim().isNotEmpty == true
        ? profilePreview!.avatarUrl.trim()
        : (cachedData['avatarUrl'] as String?)?.trim() ?? '';
    final cachedAvatar = cachedAvatarRaw.startsWith('http://') ||
            cachedAvatarRaw.startsWith('https://')
        ? cachedAvatarRaw
        : '';

    final isVerified = cachedData['isVerified'] == true ||
        cachedData['verified'] == true ||
        cachedData['isAdmin'] == true;
    final isAdmin = cachedData['isAdmin'] == true;

    return Chat(
      id: row.$id,
      partnerId: partnerId,
      partnerName: cachedName?.isNotEmpty == true ? cachedName! : '',
      partnerAvatar: cachedAvatar,
      lastMessage: lastMessage,
      timestamp: timestamp,
      unreadCount: unread,
      isOnline: false,
      lastSenderId: (data['lastSenderId'] as String?) ?? '',
      lastMessageStatus: _lastMessageStatusFromRow(data, meId),
      lastMessageId: (data['lastMessageId'] as String?) ?? '',
      lastMessageDeliveredAt: (data['lastMessageDeliveredAt'] as String?) ?? '',
      lastMessageReadAt: (data['lastMessageReadAt'] as String?) ?? '',
      partnerIsVerified: isVerified,
      partnerIsAdmin: isAdmin,
    );
  }

  Future<void> _hydrateChats(List<aw.Row> rows, String meId) async {
    if (_isHydrating) return;
    _isHydrating = true;
    try {
      for (final row in rows) {
        if (!mounted) return;
        final data = row.data;
        final rawIds = (data['memberIds'] as String?) ?? '';
        final userIds = rawIds
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (userIds.length < 2) continue;
        final partnerId =
            userIds.firstWhere((id) => id != meId, orElse: () => meId);
        if (partnerId == meId) continue;

        final profile = await BackendService.getProfileByUserId(partnerId);
        final pdata = profile?.data ?? <String, dynamic>{};
        String avatar = (pdata['avatarUrl'] as String?)?.trim() ?? '';
        if (avatar.isNotEmpty && !avatar.startsWith('http')) {
          try {
            avatar = await StorageService.getSignedUrl(avatar);
          } catch (_) {}
        }
        final displayName = (pdata['displayName'] as String?)?.trim() ?? '';
        final hydratedLastMessage = await _hydrateLastMessage(row, partnerId);
        final cached = ChatMessageCache.get(row.$id);
        final unread = cached != null
            ? cached.messages.where((m) => !m.isSent && !m.isRead).length
            : _chatUnreadCountFromRow(data);

        final isVerified = pdata['isVerified'] == true ||
            pdata['verified'] == true ||
            pdata['isAdmin'] == true;
        final isAdmin = pdata['isAdmin'] == true;

        if (!mounted) return;
        _updateChat(
          row.$id,
          (current) => Chat(
            id: current.id,
            partnerId: current.partnerId,
            partnerName: displayName.isNotEmpty ? displayName : current.partnerName,
            partnerAvatar: avatar.isNotEmpty ? avatar : current.partnerAvatar,
            lastMessage: hydratedLastMessage.isNotEmpty
                ? hydratedLastMessage
                : current.lastMessage,
            timestamp: current.timestamp,
            unreadCount: unread,
            isOnline: current.isOnline,
            lastSenderId: (data['lastSenderId'] as String?) ?? current.lastSenderId,
            lastMessageStatus: current.lastMessageStatus,
            lastMessageId: current.lastMessageId,
            lastMessageDeliveredAt: current.lastMessageDeliveredAt,
            lastMessageReadAt: current.lastMessageReadAt,
            partnerIsVerified: isVerified,
            partnerIsAdmin: isAdmin,
          ),
        );
      }
    } finally {
      _isHydrating = false;
    }
  }

  String _previewLastMessage(aw.Row row) {
    final data = row.data;
    final lastMessage = (data['lastMessage'] as String?)?.trim() ?? '';
    if (lastMessage.isNotEmpty) return lastMessage;

    final cipher = (data['lastCiphertext'] as String?) ?? '';
    final nonce = (data['lastNonce'] as String?) ?? '';
    final mac = (data['lastMac'] as String?) ?? '';
    if (cipher.isEmpty || nonce.isEmpty || mac.isEmpty) return '';

    // Decryption is done later in the background hydrate pass.
    return '';
  }

  Future<String> _hydrateLastMessage(aw.Row row, String partnerId) async {
    final data = row.data;
    final lastMessage = (data['lastMessage'] as String?)?.trim() ?? '';
    if (lastMessage.isNotEmpty) return lastMessage;

    final cipher = (data['lastCiphertext'] as String?) ?? '';
    final nonce = (data['lastNonce'] as String?) ?? '';
    final mac = (data['lastMac'] as String?) ?? '';
    if (cipher.isEmpty || nonce.isEmpty || mac.isEmpty) return '';

    final decrypted = await CryptoService.decryptMessage(
      chatId: row.$id,
      partnerUserId: partnerId,
      ciphertextB64: cipher,
      nonceB64: nonce,
      macB64: mac,
    );
    return decrypted?.trim() ?? '';
  }

  DateTime _chatTimestampFromRow(Map<String, dynamic> data) {
    final rawLastMessageAt = data['lastMessageAt'] as String?;
    final rawTimestamp = data['timestamp'] as String?;
    final rawCreatedAt = data['createdAt'] as String?;
    final parsed = DateTime.tryParse(rawLastMessageAt ?? '') ??
        DateTime.tryParse(rawTimestamp ?? '') ??
        DateTime.tryParse(rawCreatedAt ?? '');
    if (parsed == null) return DateTime.fromMillisecondsSinceEpoch(0);
    return parsed.isUtc ? parsed.toLocal() : parsed;
  }

  int _chatUnreadCountFromRow(Map<String, dynamic> data) {
    final raw = data['unreadCount'];
    if (raw is int) return raw;
    return int.tryParse('$raw') ?? 0;
  }

  String _lastMessageStatusFromRow(Map<String, dynamic> data, String meId) {
    final senderId = (data['lastSenderId'] as String?)?.trim() ?? '';
    if (senderId != meId) return '';
    final raw = (data['lastMessageStatus'] as String?)?.trim().toLowerCase() ?? '';
    if (raw.isNotEmpty) return raw;
    if ((data['lastMessageReadAt'] as String?)?.trim().isNotEmpty == true) {
      return MessageDeliveryStatus.read.value;
    }
    if ((data['lastMessageDeliveredAt'] as String?)?.trim().isNotEmpty == true) {
      return MessageDeliveryStatus.delivered.value;
    }
    return MessageDeliveryStatus.sent.value;
  }

  void _updateChat(String chatId, Chat Function(Chat current) update) {
    final index = _chats.indexWhere((chat) => chat.id == chatId);
    if (index < 0) return;
    final next = update(_chats[index]);
    setState(() {
      _chats[index] = next;
      _applyFilter();
    });
    ChatPreviewCache.set(next);
  }

  void _subscribeMessages() {
    final channel =
        'databases.${BackendService.databaseId}.collections.${BackendService.messagesCollectionId}.documents';
    try {
      _messagesSub = BackendService.realtime.subscribe([channel]);
      _messagesSub?.stream.listen((event) async {
        if (!mounted) return;
        if (event.events.isEmpty) return;
        final name = event.events.first;
        final payload = event.payload;
        if (name.contains('.create') || name.contains('.update')) {
          final chatId = (payload['chatId'] as String?)?.trim() ?? '';
          if (chatId.isNotEmpty) {
            final senderId = (payload['senderId'] as String?) ?? '';
            final user = await BackendService.getCurrentUser();
            if (user != null) {
              final readBy = payload['readBy'] is List
                  ? (payload['readBy'] as List).map((e) => e.toString().trim()).toList()
                  : ((payload['readBy'] as String?) ?? '').split(',').map((e) => e.trim()).toList();
              final timestampStr = payload['timestamp'] as String? ?? payload['createdAt'] as String? ?? '';
              final timestamp = DateTime.tryParse(timestampStr) ?? DateTime.now();
              
              final isSent = senderId == user.$id;
              final isRead = readBy.contains(user.$id);
              
              final msg = Message(
                id: payload['\$id'] as String? ?? '',
                content: (payload['content'] as String?) ?? '',
                mediaUrl: payload['mediaUrl'] as String?,
                thumbnailUrl: payload['thumbnailUrl'] as String?,
                mediaType: payload['mediaType'] as String?,
                timestamp: timestamp,
                isSent: isSent,
                isRead: isRead,
                deliveryStatus: MessageDeliveryStatusX.fromRaw(
                  payload['deliveryStatus'],
                  isRead: isRead,
                  isSent: isSent,
                ),
              );
              ChatMessageCache.addOrUpdateMessage(chatId, msg);
            }
          }
          await _loadChats();
        }
      });
    } catch (_) {}
  }

  @override
  void didPopNext() {
    // Refresh when returning from a pushed screen such as a profile or chat.
    unawaited(_loadChats());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadChats());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          _buildHeader(),
          _buildSearchBar(),
          Expanded(
            child: _isLoading && _chats.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _buildChatList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;

    return Container(
      height: 56, // h-14
      padding: const EdgeInsets.symmetric(horizontal: 16), // px-4
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF202C33) : const Color(0xFFE5E7EB),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween, // justify-between
        children: [
          Text(
            'Chats',
            style: TextStyle(
              fontSize: 24, // text-2xl
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          IconButton(
            onPressed: _startNewChat,
            icon: Icon(
              LucideIcons.edit,
              size: 24,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final fieldBg = isDark ? const Color(0xFF202C33) : const Color(0xFFF9FAFB);
    final hintColor =
        isDark ? const Color(0xFF8696A0) : const Color(0xFF6B7280);

    return Container(
      padding: const EdgeInsets.all(16),
      color: bg,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search chats',
          hintStyle: TextStyle(color: hintColor),
          prefixIcon: Icon(LucideIcons.search, color: hintColor),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(
              color: isDark ? const Color(0xFF202C33) : const Color(0xFFE5E7EB),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(
              color: isDark ? const Color(0xFF202C33) : const Color(0xFFE5E7EB),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(
              color: isDark ? const Color(0xFF00A884) : const Color(0xFF29ABE2),
            ),
          ),
          filled: true,
          fillColor: fieldBg,
        ),
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
      ),
    );
  }

  Widget _buildChatList() {
    return ListView.separated(
      itemCount: _filteredChats.length,
      separatorBuilder: (context, index) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        return Divider(
          height: 0,
          thickness: 0.6,
          indent: 76,
          color: isDark ? const Color(0xFF202C33) : const Color(0xFFE5E7EB),
        );
      },
      itemBuilder: (context, index) {
        final chat = _filteredChats[index];
        return _buildChatItem(chat);
      },
    );
  }

  Widget _buildChatItem(Chat chat) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final titleColor = isDark ? Colors.white : Colors.black;
    final subtitleColor =
        isDark ? const Color(0xFF8696A0) : const Color(0xFF6B7280);
    final timeColor = subtitleColor;
    final showStatus =
        _currentUserId != null && chat.lastSenderId == _currentUserId;

    return GestureDetector(
      onTap: () => _navigateToChat(chat),
      child: Container(
        padding: const EdgeInsets.all(16), // p-4
        color: bg,
        child: Row(
          children: [
            // User Avatar - h-12 w-12 (48px)
            _buildChatAvatar(chat.partnerAvatar),
            const SizedBox(width: 12), // space-x-3
            // Chat Details - flex-1 min-w-0
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          chat.partnerName,
                          style: TextStyle(
                            fontSize: 16, // text-base
                            fontWeight: FontWeight.w500, // font-medium
                            color: titleColor,
                          ),
                          overflow: TextOverflow.ellipsis, // truncate
                        ),
                      ),
                      if (chat.partnerIsVerified) ...[
                        const SizedBox(width: 4),
                        VerificationBadge(
                          size: 14,
                          isPremium: chat.partnerIsAdmin,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (chat.lastMessage.isNotEmpty)
                    Text(
                      chat.lastMessage,
                      style: TextStyle(
                        fontSize: 14, // text-sm
                        color: subtitleColor, // text-muted-foreground
                      ),
                      overflow: TextOverflow.ellipsis, // truncate
                    ),
                  if (showStatus && chat.lastMessageStatus.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _buildChatStatus(chat.lastMessageStatus),
                  ],
                ],
              ),
            ),
            // Timestamp & Status
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatTimestamp(chat.timestamp),
                  style: TextStyle(
                    fontSize: 12, // text-xs
                    color: timeColor, // text-muted-foreground
                  ),
                ),
                if (chat.unreadCount > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: const BoxDecoration(
                      color: Color(0xFF29ABE2), // bg-primary
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${chat.unreadCount}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatAvatar(String avatarUrl) {
    final trimmed = avatarUrl.trim();
    final hasAvatar = trimmed.isNotEmpty &&
        (trimmed.startsWith('http://') || trimmed.startsWith('https://'));

    return Container(
      width: 48,
      height: 48,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF1F2A33),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasAvatar
          ? Image.network(
              trimmed,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildChatStatus(String status) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? const Color(0xFF8696A0) : const Color(0xFF6B7280);
    const green = Color(0xFF22C55E);
    switch (status.toLowerCase()) {
      case 'pending':
        return Icon(Icons.access_time_rounded, size: 11, color: muted);
      case 'sent':
        return _buildTicks(muted, doubleTick: false);
      case 'delivered':
        return _buildTicks(muted, doubleTick: true);
      case 'read':
        return _buildTicks(green, doubleTick: true);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTicks(Color color, {required bool doubleTick}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(doubleTick ? 2 : 1, (index) {
        return Padding(
          padding: EdgeInsets.only(left: index == 0 ? 0 : 1),
          child: Icon(
            Icons.check_rounded,
            size: 11,
            color: color,
          ),
        );
      }),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference =
        timestamp.isAfter(now) ? Duration.zero : now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inSeconds > 5) {
      return '${difference.inSeconds}s ago';
    } else {
      return 'Just now';
    }
  }

  void _startNewChat() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NewChatScreen()),
    );
  }

  void _navigateToChat(Chat chat) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IndividualChatScreen(chat: chat),
      ),
    );
  }
}

