import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart'
    show Permission, RealtimeSubscription, Role;
import 'package:appwrite/models.dart' as aw;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cryptography/cryptography.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../widgets/voice_note_player.dart';
import '../widgets/voice_recorder.dart';
import '../widgets/verification_badge.dart';

import '../models/chat.dart';
import '../services/realtime_gateway.dart';
import '../services/chat_message_cache.dart';
import '../services/chat_preview_cache.dart';
import '../services/appwrite_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import '../main.dart';

class IndividualChatScreen extends StatefulWidget {
  final Chat chat;

  const IndividualChatScreen({super.key, required this.chat});

  @override
  State<IndividualChatScreen> createState() => _IndividualChatScreenState();
}

class _IndividualChatScreenState extends State<IndividualChatScreen>
    with WidgetsBindingObserver, RouteAware {
  static const int _messagePageSize = 30;
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Message> _messages = [];
  RealtimeSubscription? _messagesSub;
  late final VoidCallback _reconnectListener;
  String? _currentUserId;
  String? _resolvedChatId;
  bool _isLoadingOlderMessages = false;
  bool _hasMoreOlderMessages = true;
  String? _oldestLoadedMessageId;
  String _headerPartnerName = '';
  String _headerPartnerAvatar = '';
  bool _headerIsOnline = false;
  bool _isSending = false;
  bool _isLoadingMessages = false;
  bool _stickToBottom = true;
  bool _hasLoadedInitialMessages = false;
  bool _showScrollToBottom = false;
  bool _isRecordingVoice = false;
  bool _partnerIsVerified = false;
  bool _partnerIsAdmin = false;
  Message? _selectedMessage;
  Message? _replyingToMessage;
  Message? _editingMessage;

  List<String> _readByList(dynamic rawValue) {
    if (rawValue is List) {
      return rawValue
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    final raw = (rawValue as String?) ?? '';
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  MessageDeliveryStatus _deliveryStatusFromData(
    Map<String, dynamic> data, {
    required bool isSent,
    required bool isRead,
  }) {
    final raw = data['deliveryStatus'];
    final normalized = raw?.toString().trim().toLowerCase() ?? '';
    switch (normalized) {
      case 'pending':
        return MessageDeliveryStatus.pending;
      case 'sent':
        return MessageDeliveryStatus.sent;
      case 'delivered':
        return MessageDeliveryStatus.delivered;
      case 'read':
        return MessageDeliveryStatus.read;
      case 'failed':
        return MessageDeliveryStatus.failed;
    }
    if (isSent) {
      final readAt = (data['readAt'] as String?)?.trim() ?? '';
      if (readAt.isNotEmpty) return MessageDeliveryStatus.read;
      final deliveredAt = (data['deliveredAt'] as String?)?.trim() ?? '';
      if (deliveredAt.isNotEmpty) return MessageDeliveryStatus.delivered;
      return MessageDeliveryStatus.sent;
    }
    return MessageDeliveryStatus.sent;
  }

  bool _containsCurrentUser(dynamic rawValue) {
    if (_currentUserId == null) return false;
    return _readByList(rawValue).contains(_currentUserId);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_handleScroll);
    _primeCachedHeaderSnapshot();
    unawaited(_primeCachedMessages());
    unawaited(_init());
    _reconnectListener = () {
      _messagesSub?.close();
      _subscribeMessages();
    };
    RealtimeGateway.reconnectTrigger.addListener(_reconnectListener);
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
  void didPopNext() {
    _primeCachedHeaderSnapshot();
    unawaited(_primeCachedMessages());
    unawaited(_loadLatestMessages());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _primeCachedHeaderSnapshot();
      unawaited(_primeCachedMessages());
      unawaited(_loadLatestMessages());
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final nearBottom = position.extentAfter < 120;
    final nearTop = position.extentBefore < 120;
    if (_stickToBottom != nearBottom) {
      _stickToBottom = nearBottom;
    }
    if (nearTop && !_isLoadingOlderMessages && _hasMoreOlderMessages) {
      unawaited(_loadOlderMessages());
    }

    final scrolledUp = position.extentAfter > 300;
    if (_showScrollToBottom != scrolledUp) {
      setState(() {
        _showScrollToBottom = scrolledUp;
      });
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
          Expanded(child: _buildMessageArea()),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    if (_selectedMessage != null) {
      return _buildSelectionHeader();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : theme.colorScheme.surface;
    final textColor = theme.colorScheme.onSurface;
    final subtitleColor =
        isDark ? const Color(0xFF8696A0) : const Color(0xFF6B7280);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF202C33) : const Color(0xFFE5E7EB),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(Icons.arrow_back, size: 20, color: textColor),
                ),
              ),
              const SizedBox(width: 8),
              _buildPartnerAvatar(size: 36),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _headerPartnerName.isNotEmpty
                                ? _headerPartnerName
                                : widget.chat.partnerName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_partnerIsVerified) ...[
                          const SizedBox(width: 4),
                          VerificationBadge(
                            size: 14,
                            isPremium: _partnerIsAdmin,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _headerIsOnline
                          ? 'Online'
                          : (widget.chat.isOnline ? 'Online' : 'Last seen recently'),
                      style: TextStyle(fontSize: 11, color: subtitleColor),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.videocam, size: 22),
                color: textColor,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Video calling coming soon')),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.call, size: 20),
                color: textColor,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Voice calling coming soon')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionHeader() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1F2C34) : theme.colorScheme.primary.withOpacity(0.1);
    final textColor = theme.colorScheme.onSurface;

    final isMe = _selectedMessage?.isSent == true;

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF202C33) : const Color(0xFFE5E7EB),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close),
                color: textColor,
                onPressed: () {
                  setState(() {
                    _selectedMessage = null;
                  });
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '1 selected',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.reply),
                color: textColor,
                onPressed: () {
                  if (_selectedMessage != null) {
                    _onReplyToMessage(_selectedMessage!);
                  }
                },
              ),
              if (isMe && _selectedMessage?.mediaType == null)
                IconButton(
                  icon: const Icon(Icons.edit),
                  color: textColor,
                  onPressed: () {
                    if (_selectedMessage != null) {
                      _onEditMessage(_selectedMessage!);
                    }
                  },
                ),
              if (isMe)
                IconButton(
                  icon: const Icon(Icons.delete),
                  color: Colors.redAccent,
                  onPressed: () {
                    if (_selectedMessage != null) {
                      _onDeleteMessage(_selectedMessage!);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _onEditMessage(Message message) {
    setState(() {
      _editingMessage = message;
      _replyingToMessage = null;
      _selectedMessage = null;
      _messageController.text = message.content;
    });
  }

  void _onReplyToMessage(Message message) {
    setState(() {
      _replyingToMessage = message;
      _editingMessage = null;
      _selectedMessage = null;
    });
  }

  Future<void> _onDeleteMessage(Message message) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Message?'),
          content: const Text('Are you sure you want to delete this message for everyone?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() {
      _selectedMessage = null;
    });

    try {
      await AppwriteService.deleteMessage(message.id);
      setState(() {
        _messages.removeWhere((m) => m.id == message.id);
      });
      ChatMessageCache.removeMessage(_chatId, message.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete message')),
      );
    }
  }

  Future<void> _editMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _currentUserId == null || _editingMessage == null) return;
    final messageId = _editingMessage!.id;
    final messageToEdit = _editingMessage!;
    setState(() {
      _editingMessage = null;
    });
    _messageController.clear();

    final updated = Message(
      id: messageToEdit.id,
      content: text,
      mediaUrl: messageToEdit.mediaUrl,
      thumbnailUrl: messageToEdit.thumbnailUrl,
      mediaType: messageToEdit.mediaType,
      timestamp: messageToEdit.timestamp,
      isSent: messageToEdit.isSent,
      isRead: messageToEdit.isRead,
      deliveryStatus: messageToEdit.deliveryStatus,
      isEdited: true,
      replyToId: messageToEdit.replyToId,
      replyToContent: messageToEdit.replyToContent,
    );
    _upsertMessage(updated);

    await _updateEditedMessage(messageId, text);
  }

  Future<void> _updateEditedMessage(String messageId, String newText) async {
    try {
      final enc = await CryptoService.encryptMessage(
        chatId: _chatId,
        partnerUserId: widget.chat.partnerId,
        plaintext: newText,
      );
      if (enc == null) return;
      await AppwriteService.updateRow(
        AppwriteService.messagesCollectionId,
        messageId,
        {
          'ciphertext': enc['ciphertext'] ?? '',
          'nonce': enc['nonce'] ?? '',
          'mac': enc['mac'] ?? '',
          'isEdited': true,
        },
      );
    } catch (_) {}
  }

  Widget _buildReplyPreviewBar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDark ? const Color(0xFF1F2C34) : const Color(0xFFF3F4F6),
      child: Row(
        children: [
          const Icon(Icons.reply, size: 20, color: Color(0xFF29ABE2)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to message',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _replyingToMessage!.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () {
              setState(() {
                _replyingToMessage = null;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEditPreviewBar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDark ? const Color(0xFF1F2C34) : const Color(0xFFF3F4F6),
      child: Row(
        children: [
          const Icon(Icons.edit, size: 20, color: Color(0xFF29ABE2)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Editing message',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _editingMessage!.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () {
              setState(() {
                _editingMessage = null;
                _messageController.clear();
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPartnerAvatar({required double size}) {
    final avatarUrl = _headerPartnerAvatar.isNotEmpty
        ? _headerPartnerAvatar.trim()
        : widget.chat.partnerAvatar.trim();
    final hasAvatar = avatarUrl.isNotEmpty &&
        (avatarUrl.startsWith('http://') || avatarUrl.startsWith('https://'));

    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF29ABE2),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasAvatar
          ? Image.network(
              avatarUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.person, color: Colors.white, size: 20);
              },
            )
          : const Icon(Icons.person, color: Colors.white, size: 20),
    );
  }

  Widget _buildMessageArea() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B141A) : theme.colorScheme.background;
    return Container(
      color: bg,
      child: Column(
        children: [
          _buildEncryptionBanner(),
          Expanded(
            child: Stack(
              children: [
                ((_isLoadingMessages && _messages.isEmpty) ||
                        (!_hasLoadedInitialMessages && _messages.isEmpty))
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty
                        ? _buildEmptyConversationState()
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 12,
                            ),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final message = _messages[index];
                              return _buildMessageBubble(message);
                            },
                          ),
                if (_showScrollToBottom)
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: GestureDetector(
                      onTap: () {
                        _scrollToBottom(smooth: true);
                        setState(() {
                          _showScrollToBottom = false;
                        });
                      },
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF202C33) : Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.keyboard_double_arrow_down,
                          color: isDark ? Colors.white : Colors.black87,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyConversationState() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : theme.colorScheme.onSurface;
    final subtitleColor =
        isDark ? const Color(0xFF8696A0) : const Color(0xFF6B7280);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 44,
              color: subtitleColor,
            ),
            const SizedBox(height: 12),
            Text(
              'Start chatting',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start sending messages',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: subtitleColor,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEncryptionBanner() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF12212A) : const Color(0xFFE8F4FD);
    final border = isDark ? const Color(0xFF203641) : const Color(0xFFC8E1F6);
    final textColor =
        isDark ? const Color(0xFFD6F0FF) : const Color(0xFF0E4A73);

    return GestureDetector(
      onTap: _showEncryptionInfo,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(Icons.lock, size: 16, color: textColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'All messages are end-to-end encrypted',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            Icon(Icons.info_outline, size: 16, color: textColor),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Message message) {
    final isSent = message.isSent;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bubbleColor = isSent
        ? (isDark
            ? const Color(0xFF005C4B)
            : theme.colorScheme.primary.withOpacity(0.12))
        : (isDark ? const Color(0xFF202C33) : theme.colorScheme.surfaceVariant);
    final textColor = isDark
        ? Colors.white
        : (isSent ? theme.colorScheme.primary : theme.colorScheme.onSurface);

    final isSelected = _selectedMessage?.id == message.id;

    Widget bubbleContent = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isSent ? 16 : 2),
          bottomRight: Radius.circular(isSent ? 2 : 16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.replyToId != null && message.replyToContent != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : Colors.black.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reply',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message.replyToContent!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: textColor.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
          if (message.hasMedia) ...[
            _buildMediaMessage(message),
            if (message.content.isNotEmpty) const SizedBox(height: 8),
          ],
          if (message.content.isNotEmpty)
            Text(
              message.content,
              style: TextStyle(fontSize: 16, color: textColor),
            ),
          const SizedBox(height: 4),
          Text(
            _formatMessageTimestamp(message.timestamp) + (message.isEdited ? ' • Edited' : ''),
            style: TextStyle(
              fontSize: 11,
              color: textColor.withOpacity(isDark ? 0.7 : 0.8),
            ),
          ),
          if (isSent) ...[
            const SizedBox(height: 4),
            _buildMessageStatus(message),
          ],
        ],
      ),
    );

    bubbleContent = Dismissible(
      key: Key('reply-${message.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          _onReplyToMessage(message);
        }
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.transparent,
        child: const Icon(Icons.reply, color: Color(0xFF29ABE2)),
      ),
      child: bubbleContent,
    );

    return GestureDetector(
      onLongPress: () {
        setState(() {
          _selectedMessage = message;
        });
      },
      onTap: () {
        if (_selectedMessage != null) {
          setState(() {
            _selectedMessage = null;
          });
        }
      },
      child: Container(
        color: isSelected ? Colors.blue.withOpacity(0.15) : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        child: Row(
          mainAxisAlignment:
              isSent ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            bubbleContent,
          ],
        ),
      ),
    );
  }

  Widget _buildMessageStatus(Message message) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? const Color(0xFF8696A0) : const Color(0xFF6B7280);
    final green = const Color(0xFF22C55E);
    final status = message.deliveryStatus;

    switch (status) {
      case MessageDeliveryStatus.pending:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.access_time_rounded, size: 11, color: muted),
            const SizedBox(width: 3),
            Text(
              'Waiting',
              style: TextStyle(
                fontSize: 10,
                color: muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      case MessageDeliveryStatus.sent:
        return _buildTickStatus(muted, showDouble: false);
      case MessageDeliveryStatus.delivered:
        return _buildTickStatus(muted, showDouble: true);
      case MessageDeliveryStatus.read:
        return _buildTickStatus(green, showDouble: true);
      case MessageDeliveryStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 11, color: Colors.redAccent),
            const SizedBox(width: 3),
            Text(
              'Failed',
              style: TextStyle(
                fontSize: 10,
                color: Colors.redAccent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
    }
  }

  Widget _buildTickStatus(Color color, {required bool showDouble}) {
    final ticks = showDouble ? 2 : 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(ticks, (index) {
        return Padding(
          padding: EdgeInsets.only(left: index == 0 ? 0 : 1),
          child: Icon(
            Icons.check_rounded,
            size: 12,
            color: color,
          ),
        );
      }),
    );
  }

  Widget _buildMediaMessage(Message message) {
    if (message.mediaType == 'voice') {
      return VoiceNotePlayer(url: message.mediaUrl!);
    }

    if (message.isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GestureDetector(
          onTap: () => _openImagePreview(message.mediaUrl!),
          child: Image.network(
            message.mediaUrl!,
            width: 220,
            height: 220,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildBrokenMediaTile('Image'),
          ),
        ),
      );
    }

    if (message.isVideo) {
      return GestureDetector(
        onTap: () => _openVideoPreview(message.mediaUrl!),
        child: Container(
          width: 220,
          height: 180,
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(12),
            image: (message.thumbnailUrl != null &&
                    message.thumbnailUrl!.isNotEmpty)
                ? DecorationImage(
                    image: NetworkImage(message.thumbnailUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.28),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_circle_fill, color: Colors.white, size: 54),
                SizedBox(height: 8),
                Text(
                  'Video',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _buildBrokenMediaTile('Attachment');
  }

  Widget _buildBrokenMediaTile(String label) {
    return Container(
      width: 220,
      height: 120,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(child: Text(label)),
    );
  }

  String _formatMessageTimestamp(DateTime ts) {
    final local = ts.toLocal();
    var hour = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    const months = [
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
    final dateStr = '${months[local.month - 1]} ${local.day}, ${local.year}';
    return '$hour:$minute $ampm · $dateStr';
  }
  Widget _buildMessageInput() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1F2C34) : Colors.white;
    final fieldBg = isDark ? const Color(0xFF2A3942) : const Color(0xFFF9FAFB);
    final isRecording = _isRecordingVoice;
    final hasText = _messageController.text.trim().isNotEmpty;
    final canSend = !isRecording && !_isSending;

    if (isRecording) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: bg,
        child: Row(
          children: [
            Expanded(
              child: VoiceRecorder(
                onRecorded: (path) async {
                  setState(() => _isRecordingVoice = false);
                  if (path != null) {
                    await _sendVoiceMessage(path);
                  }
                },
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_replyingToMessage != null) _buildReplyPreviewBar(),
        if (_editingMessage != null) _buildEditPreviewBar(),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              top: BorderSide(
                color: isDark ? const Color(0xFF202C33) : const Color(0xFFE5E7EB),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () {},
                icon: const Icon(
                  Icons.sentiment_satisfied_alt_outlined,
                  size: 24,
                  color: Color(0xFF8696A0),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _messageController,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: _editingMessage != null ? 'Edit message...' : 'Type a message...',
                    hintStyle: const TextStyle(color: Color(0xFF8696A0)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(
                        color:
                            isDark ? Colors.transparent : const Color(0xFFE5E7EB),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(
                        color:
                            isDark ? Colors.transparent : const Color(0xFFE5E7EB),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(
                        color:
                            isDark ? Colors.transparent : const Color(0xFF1DA1F2),
                      ),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    filled: true,
                    fillColor: fieldBg,
                  ),
                  onChanged: (value) => setState(() {}),
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                ),
              ),
              IconButton(
                onPressed: _showAttachmentPicker,
                icon: const Icon(
                  Icons.attach_file,
                  size: 24,
                  color: Color(0xFF8696A0),
                ),
              ),
              GestureDetector(
                onTap: canSend
                    ? (hasText
                        ? (_editingMessage != null ? _editMessage : _sendMessage)
                        : () {
                            setState(() => _isRecordingVoice = true);
                          })
                    : null,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFF00A884),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    hasText
                        ? (_editingMessage != null ? Icons.check : Icons.send)
                        : Icons.mic,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _sendVoiceMessage(String path) async {
    if (_currentUserId == null || _isSending) return;
    setState(() => _isSending = true);
    final replyId = _replyingToMessage?.id;
    final replyContent = _replyingToMessage?.content;
    setState(() {
      _replyingToMessage = null;
    });
    try {
      final chatId = _chatId.isNotEmpty ? _chatId : await _ensureChatId();
      final now = DateTime.now();
      ChatPreviewCache.set(
        Chat(
          id: chatId,
          partnerId: widget.chat.partnerId,
          partnerName: widget.chat.partnerName,
          partnerAvatar: widget.chat.partnerAvatar,
          lastMessage: 'Voice message',
          timestamp: now,
          unreadCount: 0,
          isOnline: widget.chat.isOnline,
          lastSenderId: _currentUserId!,
          lastMessageStatus: MessageDeliveryStatus.pending.value,
        ),
      );
      final key = 'chat/$chatId/voice_${DateTime.now().millisecondsSinceEpoch}.aac';
      final stored = <String>[
        await StorageService.uploadFileAtPath(File(path), key)
      ];
      final mediaUrl = await StorageService.getSignedUrl(stored.first);

      final created = await AppwriteService.createDocument(
        AppwriteService.messagesCollectionId,
        {
          'chatId': chatId,
          'senderId': _currentUserId,
          'ciphertext': '',
          'nonce': '',
          'mac': '',
          'e2eeVersion': CryptoService.currentE2eeVersion,
          'mediaUrl': mediaUrl,
          'thumbnailUrl': '',
          'mediaType': 'voice',
          'timestamp': DateTime.now().toIso8601String(),
          'isRead': false,
          'isEdited': false,
          'readBy': _currentUserId!,
          'deliveryStatus': MessageDeliveryStatus.sent.value,
          'sentAt': DateTime.now().toIso8601String(),
          'deliveredAt': '',
          'readAt': '',
          'replyToId': replyId ?? '',
          'replyToContent': replyContent ?? '',
        },
        permissions: [
          Permission.read(Role.any()),
          Permission.write(Role.user(_currentUserId!)),
          Permission.write(Role.users()),
        ],
      );
      final createdMessage = await _decodeMessageData(
        chatId,
        created.$id,
        created.data,
      );
      if (createdMessage != null && mounted) {
        _upsertMessage(createdMessage);
      }

      unawaited(() async {
        try {
          await AppwriteService.updateRow(
            AppwriteService.chatsCollectionId,
            chatId,
            {
              'lastMessage': 'Voice message',
              'lastCiphertext': '',
              'lastNonce': '',
              'lastMac': '',
              'e2eeVersion': CryptoService.currentE2eeVersion,
              'lastSenderId': _currentUserId,
              'lastMessageAt': DateTime.now().toIso8601String(),
              'timestamp': DateTime.now().toIso8601String(),
              'unreadCount': 0,
              'lastMessageId': created.$id,
              'lastMessageStatus': MessageDeliveryStatus.sent.value,
              'lastMessageDeliveredAt': '',
              'lastMessageReadAt': '',
            },
          );
        } catch (_) {}
        final senderProfile =
            await AppwriteService.getProfileByUserId(_currentUserId!);
        final senderData = senderProfile?.data ?? <String, dynamic>{};
        final senderName =
            (senderData['displayName'] as String?)?.trim().isNotEmpty == true
                ? (senderData['displayName'] as String).trim()
                : ((senderData['username'] as String?)?.trim().isNotEmpty == true
                    ? (senderData['username'] as String).trim()
                    : 'New message');
        final senderAvatar = (senderData['avatarUrl'] as String?)?.trim() ?? '';
        await AppwriteService.sendChatPushNotification(
          recipientUserId: widget.chat.partnerId,
          chatId: chatId,
          senderUserId: _currentUserId!,
          senderName: senderName,
          senderAvatar: senderAvatar,
          body: 'Sent a voice message',
        );
      }());
      ChatPreviewCache.set(
        Chat(
          id: chatId,
          partnerId: widget.chat.partnerId,
          partnerName: widget.chat.partnerName,
          partnerAvatar: widget.chat.partnerAvatar,
          lastMessage: 'Voice message',
          timestamp: DateTime.now(),
          unreadCount: 0,
          isOnline: widget.chat.isOnline,
          lastSenderId: _currentUserId!,
          lastMessageId: created.$id,
          lastMessageStatus: MessageDeliveryStatus.sent.value,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send voice message: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _init() async {
    final me = await AppwriteService.getCurrentUser();
    if (me == null) return;
    _currentUserId = me.$id;
    await _ensureChatId();
    _subscribeMessages();
    await _primeCachedMessages();
    unawaited(_primeChatSession());
    unawaited(_loadLatestMessages());

    try {
      final profile = await AppwriteService.getProfileByUserId(widget.chat.partnerId);
      if (profile != null && mounted) {
        setState(() {
          _partnerIsVerified = profile.data['isVerified'] == true ||
              profile.data['verified'] == true ||
              profile.data['isAdmin'] == true;
          _partnerIsAdmin = profile.data['isAdmin'] == true;
        });
      }
    } catch (_) {}
  }

  Future<void> _primeCachedMessages() async {
    final cached = ChatMessageCache.get(_chatId);
    if (cached == null || !mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(cached.messages);
      _oldestLoadedMessageId = _messages.isNotEmpty ? _messages.first.id : null;
      _hasMoreOlderMessages = _messages.length >= _messagePageSize;
      _stickToBottom = true;
      _hasLoadedInitialMessages = _messages.isNotEmpty;
    });
    _scrollToBottom(smooth: false);
  }

  void _primeCachedHeaderSnapshot() {
    final cached = ChatPreviewCache.get(_chatId) ??
        ChatPreviewCache.get(widget.chat.id);
    final nextName = cached?.partnerName.trim() ?? '';
    final nextAvatar = cached?.partnerAvatar.trim() ?? '';
    final nextOnline = cached?.isOnline ?? widget.chat.isOnline;
    final isVerified = cached?.partnerIsVerified ?? false;
    final isAdmin = cached?.partnerIsAdmin ?? false;
    if (!mounted) {
      _headerPartnerName = nextName.isNotEmpty ? nextName : widget.chat.partnerName;
      _headerPartnerAvatar = nextAvatar.isNotEmpty
          ? nextAvatar
          : widget.chat.partnerAvatar;
      _headerIsOnline = nextOnline;
      _partnerIsVerified = isVerified;
      _partnerIsAdmin = isAdmin;
      return;
    }

    if (_headerPartnerName == nextName &&
        _headerPartnerAvatar == nextAvatar &&
        _headerIsOnline == nextOnline &&
        _partnerIsVerified == isVerified &&
        _partnerIsAdmin == isAdmin) {
      return;
    }

    setState(() {
      _headerPartnerName =
          nextName.isNotEmpty ? nextName : widget.chat.partnerName;
      _headerPartnerAvatar =
          nextAvatar.isNotEmpty ? nextAvatar : widget.chat.partnerAvatar;
      _headerIsOnline = nextOnline;
      _partnerIsVerified = isVerified;
      _partnerIsAdmin = isAdmin;
    });
  }

  Future<void> _primeChatSession() async {
    try {
      final chatId = await _ensureChatId();
      await CryptoService.ensureIdentityKeysAndPublish();
      await CryptoService.getChatKey(
        chatId: chatId,
        partnerUserId: widget.chat.partnerId,
      );
    } catch (_) {}
  }

  Future<void> _showEncryptionInfo() async {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'End-to-end encryption',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'This chat protects your private conversation from sender to receiver.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                _buildInfoBullet('Text messages in this chat'),
                _buildInfoBullet(
                    'Shared photos and videos in the chat experience'),
                _buildInfoBullet(
                    'Message content while it moves between devices'),
                _buildInfoBullet(
                    'Only people inside the chat should read the conversation'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoBullet(String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.check_circle, size: 16, color: Color(0xFF29ABE2)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  String get _chatId => _resolvedChatId ?? widget.chat.id;

  Future<String> _ensureChatId() async {
    if (_currentUserId == null) {
      throw StateError('User must be signed in to start a chat.');
    }
    final resolved =
        await AppwriteService.getChatId(_currentUserId!, widget.chat.partnerId);
    _resolvedChatId = resolved;
    return resolved;
  }

  Future<void> _loadLatestMessages() async {
    if (_currentUserId == null) return;
    if (_isLoadingMessages) return;
    _isLoadingMessages = true;
    try {
      final chatId = await _ensureChatId();
      final page = await AppwriteService.fetchMessagesForChat(
        chatId,
        limit: _messagePageSize,
      );
      if (page.rows.isEmpty) {
        _hasMoreOlderMessages = false;
        _oldestLoadedMessageId = null;
        if (mounted) {
          setState(() {
            _isLoadingMessages = false;
            _hasLoadedInitialMessages = true;
          });
        }
        return;
      }
      _hasMoreOlderMessages = page.rows.length == _messagePageSize;
      _oldestLoadedMessageId = page.rows.last.$id;

      // Build a lookup of cached messages so we can fall back to
      // cached plaintext when decryption fails (key not ready yet).
      final cachedEntry = ChatMessageCache.get(chatId);
      final cachedById = <String, Message>{};
      if (cachedEntry != null) {
        for (final m in cachedEntry.messages) {
          cachedById[m.id] = m;
        }
      }

      // Decode all messages in parallel, then merge results in one
      // setState call to avoid per-message rebuilds / pop-in.
      final futures = page.rows.map((row) async {
        final decoded = await _decodeMessageData(chatId, row.$id, row.data);
        if (decoded != null) return decoded;
        // Decryption failed – reuse cached plaintext if available.
        final cached = cachedById[row.$id];
        if (cached != null && cached.content.isNotEmpty) return cached;
        return null;
      });
      final decoded = await Future.wait(futures);
      final newMessages = decoded.whereType<Message>().toList();

      if (!mounted) return;

      // Merge newly decoded messages into the current list.
      final merged = <String, Message>{};
      for (final m in _messages) {
        merged[m.id] = m;
      }
      for (final m in newMessages) {
        merged[m.id] = m;
      }
      final sorted = merged.values.toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      setState(() {
        _messages
          ..clear()
          ..addAll(sorted);
        _isLoadingMessages = false;
        _hasLoadedInitialMessages = true;
      });

      // Persist to cache once after the full batch.
      ChatMessageCache.set(chatId, _messages);

      if (_stickToBottom) {
        _scrollToBottom(smooth: false);
      }

      // Mark incoming messages as delivered in the background.
      for (final row in page.rows) {
        final msg = merged[row.$id];
        if (msg != null) {
          unawaited(_markDeliveredIfNeeded(chatId, row.$id, row.data, msg));
        }
      }
      unawaited(_markMessagesRead(limit: _messagePageSize));
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingMessages = false;
          _hasLoadedInitialMessages = true;
        });
      }
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_currentUserId == null ||
        _isLoadingOlderMessages ||
        !_hasMoreOlderMessages ||
        _oldestLoadedMessageId == null) {
      return;
    }
    _isLoadingOlderMessages = true;
    try {
      final chatId = await _ensureChatId();
      final page = await AppwriteService.fetchMessagesForChat(
        chatId,
        limit: _messagePageSize,
        cursorId: _oldestLoadedMessageId,
      );
      if (page.rows.isEmpty) {
        _hasMoreOlderMessages = false;
        return;
      }
      _hasMoreOlderMessages = page.rows.length == _messagePageSize;
      _oldestLoadedMessageId = page.rows.last.$id;

      // Cache fallback lookup
      final cachedEntry = ChatMessageCache.get(chatId);
      final cachedById = <String, Message>{};
      if (cachedEntry != null) {
        for (final m in cachedEntry.messages) {
          cachedById[m.id] = m;
        }
      }

      final futures = page.rows.map((row) async {
        final decoded = await _decodeMessageData(chatId, row.$id, row.data);
        if (decoded != null) return decoded;
        final cached = cachedById[row.$id];
        if (cached != null && cached.content.isNotEmpty) return cached;
        return null;
      });
      final decoded = await Future.wait(futures);
      final newMessages = decoded.whereType<Message>().toList();

      if (!mounted || newMessages.isEmpty) return;

      final merged = <String, Message>{};
      for (final m in _messages) {
        merged[m.id] = m;
      }
      for (final m in newMessages) {
        merged[m.id] = m;
      }
      final sorted = merged.values.toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      setState(() {
        _messages
          ..clear()
          ..addAll(sorted);
      });
      ChatMessageCache.set(chatId, _messages);
    } catch (_) {} finally {
      _isLoadingOlderMessages = false;
    }
  }

  Future<Message?> _decodeMessageData(
    String chatId,
    String rowId,
    Map<String, dynamic> data,
  ) async {
    final mediaUrl = (data['mediaUrl'] as String?)?.trim();
    final thumbnailUrl = (data['thumbnailUrl'] as String?)?.trim();
    final mediaType = (data['mediaType'] as String?)?.trim();
    final content = (data['content'] as String?)?.trim() ?? '';
    final cipher = data['ciphertext'] as String? ?? '';
    final nonce = data['nonce'] as String? ?? '';
    final mac = data['mac'] as String? ?? '';

    String text = content;
    if (cipher.isNotEmpty && nonce.isNotEmpty && mac.isNotEmpty) {
      final keyBytes = await CryptoService.getChatKeyBytes(
        chatId: chatId,
        partnerUserId: widget.chat.partnerId,
      );
      if (keyBytes != null && keyBytes.isNotEmpty) {
        final dec = await compute(
          _decryptCipherMessage,
          <String, String>{
            'ciphertextB64': cipher,
            'nonceB64': nonce,
            'macB64': mac,
            'keyB64': base64Encode(keyBytes),
          },
        );
        if (dec != null && dec.isNotEmpty) {
          text = dec;
        }
      }
    }

    if (text.isEmpty && (mediaUrl == null || mediaUrl.isEmpty)) {
      return null;
    }

    final senderId = (data['senderId'] as String?) ?? '';
    final createdAtStr =
        data['timestamp'] as String? ?? data['createdAt'] as String?;
    final createdAt = DateTime.tryParse(createdAtStr ?? '') ?? DateTime.now();
    final readBy = _readByList(data['readBy']);
    final isRead = _containsCurrentUser(readBy);
    final isSent = senderId == _currentUserId;
    final deliveryStatus = _deliveryStatusFromData(
      data,
      isSent: isSent,
      isRead: isRead,
    );

    return Message(
      id: rowId,
      content: text,
      mediaUrl: mediaUrl?.isNotEmpty == true ? mediaUrl : null,
      thumbnailUrl: thumbnailUrl?.isNotEmpty == true ? thumbnailUrl : null,
      mediaType: mediaType?.isNotEmpty == true ? mediaType : null,
      timestamp: createdAt,
      isSent: isSent,
      isRead: isRead,
      deliveryStatus: deliveryStatus,
      isEdited: data['isEdited'] == true,
      replyToId: (data['replyToId'] as String?)?.isNotEmpty == true
          ? data['replyToId'] as String
          : null,
      replyToContent: (data['replyToContent'] as String?)?.isNotEmpty == true
          ? data['replyToContent'] as String
          : null,
    );
  }

  Future<void> _markDeliveredIfNeeded(
    String chatId,
    String rowId,
    Map<String, dynamic> data,
    Message message,
  ) async {
    if (_currentUserId == null || message.isSent) return;
    final senderId = (data['senderId'] as String?) ?? '';
    if (senderId == _currentUserId) return;
    final readBy = _readByList(data['readBy']);
    if (readBy.contains(_currentUserId)) return;
    final currentStatus = _deliveryStatusFromData(
      data,
      isSent: false,
      isRead: false,
    );
    if (currentStatus == MessageDeliveryStatus.delivered ||
        currentStatus == MessageDeliveryStatus.read) {
      return;
    }
    try {
      final fresh = await AppwriteService.getRow(
        AppwriteService.messagesCollectionId,
        rowId,
      );
      final freshReadBy = _readByList(fresh.data['readBy']);
      if (freshReadBy.contains(_currentUserId)) return;
      final freshStatus = _deliveryStatusFromData(
        fresh.data,
        isSent: false,
        isRead: false,
      );
      if (freshStatus == MessageDeliveryStatus.delivered ||
          freshStatus == MessageDeliveryStatus.read) {
        return;
      }
      await AppwriteService.updateRow(
        AppwriteService.messagesCollectionId,
        rowId,
        {
          ...fresh.data,
          'deliveryStatus': MessageDeliveryStatus.delivered.value,
          'deliveredAt': DateTime.now().toIso8601String(),
        },
      );
    } catch (_) {}
  }

  void _upsertMessage(Message message) {
    final index = _messages.indexWhere((item) => item.id == message.id);
    setState(() {
      if (index >= 0) {
        _messages[index] = message;
      } else {
        _messages.add(message);
      }
      _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      _stickToBottom = _stickToBottom || message.isSent;
    });
    ChatMessageCache.set(_chatId, _messages);
    if (message.isSent) {
      unawaited(_syncChatSummaryForOutgoingMessage(message));
    }
    if (_stickToBottom) {
      _scrollToBottom();
    }
  }

  Future<void> _syncChatSummaryForOutgoingMessage(Message message) async {
    if (_currentUserId == null) return;
    final chatId = _chatId;
    if (chatId.isEmpty) return;
    try {
      final row = await AppwriteService.getRow(
        AppwriteService.chatsCollectionId,
        chatId,
      );
      final data = row.data;
      if ((data['lastMessageId'] as String?)?.trim() != message.id) return;
      final status = message.deliveryStatus.value;
      await AppwriteService.updateRow(
        AppwriteService.chatsCollectionId,
        chatId,
        {
          ...data,
          'lastMessageStatus': status,
          if (status == MessageDeliveryStatus.read.value)
            'lastMessageReadAt': DateTime.now().toIso8601String(),
          if (status == MessageDeliveryStatus.delivered.value)
            'lastMessageDeliveredAt': DateTime.now().toIso8601String(),
          'lastSenderId': _currentUserId,
        },
      );
      final preview = ChatPreviewCache.get(chatId);
      if (preview != null) {
        ChatPreviewCache.set(
          Chat(
            id: preview.id,
            partnerId: preview.partnerId,
            partnerName: preview.partnerName,
            partnerAvatar: preview.partnerAvatar,
            lastMessage: preview.lastMessage,
            timestamp: preview.timestamp,
            unreadCount: preview.unreadCount,
            isOnline: preview.isOnline,
            lastSenderId: _currentUserId!,
            lastMessageId: preview.lastMessageId,
            lastMessageStatus: status,
            lastMessageDeliveredAt:
                status == MessageDeliveryStatus.delivered.value
                    ? DateTime.now().toIso8601String()
                    : preview.lastMessageDeliveredAt,
            lastMessageReadAt: status == MessageDeliveryStatus.read.value
                ? DateTime.now().toIso8601String()
                : preview.lastMessageReadAt,
          ),
        );
      }
    } catch (_) {}
  }

  void _scrollToBottom({bool smooth = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (smooth) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _subscribeMessages() {
    final channel =
        'databases.${AppwriteService.databaseId}.collections.${AppwriteService.messagesCollectionId}.documents';
    try {
      _messagesSub = AppwriteService.realtime.subscribe([channel]);
      _messagesSub?.stream.listen((event) async {
        if (!mounted) return;
        if (event.events.isEmpty) return;
        final payload = event.payload;
        final chatId = _chatId;
        if (chatId.isEmpty || payload['chatId'] != chatId) return;
        final eventName = event.events.first;
        if (!eventName.contains('.create') && !eventName.contains('.update')) {
          return;
        }
        final rowId = (payload[r'$id'] as String?) ??
            (payload['id'] as String?) ??
            '';
        if (rowId.isEmpty) return;
        final decoded = await _decodeMessageData(
          chatId,
          rowId,
          Map<String, dynamic>.from(payload),
        );
        if (decoded == null || !mounted) return;
        _upsertMessage(decoded);
        unawaited(
          _markDeliveredIfNeeded(
            chatId,
            rowId,
            Map<String, dynamic>.from(payload),
            decoded,
          ),
        );
      });
    } catch (_) {}
  }

  Future<void> _markMessagesRead({int limit = _messagePageSize}) async {
    if (_currentUserId == null) return;
    try {
      final chatId = await _ensureChatId();
      ChatMessageCache.markChatAsRead(chatId);
      final aw.RowList list =
          await AppwriteService.fetchMessagesForChat(chatId, limit: limit);
      for (final row in list.rows) {
        final data = row.data;
        final senderId = (data['senderId'] as String?) ?? '';
        if (senderId == _currentUserId) continue;
        final readBySet = _readByList(data['readBy']).toSet();
        if (readBySet.contains(_currentUserId)) continue;
        readBySet.add(_currentUserId!);
        await AppwriteService.updateRow(
          AppwriteService.messagesCollectionId,
          row.$id,
          {
            ...data,
            'readBy': readBySet.join(','),
            'isRead': true,
            'deliveryStatus': MessageDeliveryStatus.read.value,
            'deliveredAt': (data['deliveredAt'] as String?)?.isNotEmpty == true
                ? data['deliveredAt']
                : DateTime.now().toIso8601String(),
            'readAt': DateTime.now().toIso8601String(),
          },
        );
      }
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _currentUserId == null || _isSending) return;
    setState(() => _isSending = true);
    final replyId = _replyingToMessage?.id;
    final replyContent = _replyingToMessage?.content;
    setState(() {
      _replyingToMessage = null;
    });
    final now = DateTime.now();
    final optimistic = Message(
      id: 'local-${now.microsecondsSinceEpoch}',
      content: text,
      timestamp: now,
      isSent: true,
      isRead: false,
      deliveryStatus: MessageDeliveryStatus.pending,
      replyToId: replyId,
      replyToContent: replyContent,
    );
    setState(() {
      _messages.add(optimistic);
    });
    ChatPreviewCache.set(
      Chat(
        id: _chatId.isNotEmpty ? _chatId : widget.chat.id,
        partnerId: widget.chat.partnerId,
        partnerName: widget.chat.partnerName,
        partnerAvatar: widget.chat.partnerAvatar,
        lastMessage: text,
        timestamp: now,
        unreadCount: 0,
        isOnline: widget.chat.isOnline,
        lastSenderId: _currentUserId!,
        lastMessageStatus: MessageDeliveryStatus.pending.value,
      ),
    );
    _messageController.clear();
    _scrollToBottom();
    try {
      final chatId = _chatId.isNotEmpty ? _chatId : await _ensureChatId();
      final enc = await CryptoService.encryptMessage(
        chatId: chatId,
        partnerUserId: widget.chat.partnerId,
        plaintext: text,
      );
      if (enc == null) {
        throw StateError('Secure messaging is not ready on this device.');
      }

      final created = await AppwriteService.createDocument(
        AppwriteService.messagesCollectionId,
        {
          'chatId': chatId,
          'senderId': _currentUserId,
          'ciphertext': enc['ciphertext'] ?? '',
          'nonce': enc['nonce'] ?? '',
          'mac': enc['mac'] ?? '',
          'e2eeVersion': CryptoService.currentE2eeVersion,
          'mediaUrl': '',
          'thumbnailUrl': '',
          'mediaType': 'text',
          'timestamp': DateTime.now().toIso8601String(),
          'isRead': false,
          'isEdited': false,
          'readBy': _currentUserId!,
          'deliveryStatus': MessageDeliveryStatus.sent.value,
          'sentAt': DateTime.now().toIso8601String(),
          'deliveredAt': '',
          'readAt': '',
          'replyToId': replyId ?? '',
          'replyToContent': replyContent ?? '',
        },
        permissions: [
          Permission.read(Role.any()),
          Permission.write(Role.user(_currentUserId!)),
          Permission.write(Role.users()),
        ],
      );
      final createdMessage = await _decodeMessageData(
        chatId,
        created.$id,
        created.data,
      );
      if (createdMessage != null && mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == optimistic.id);
        });
        _upsertMessage(createdMessage);
      }
      unawaited(() async {
        try {
          await AppwriteService.updateRow(
            AppwriteService.chatsCollectionId,
            chatId,
            {
              'lastMessage': text,
              'lastCiphertext': enc['ciphertext'] ?? '',
              'lastNonce': enc['nonce'] ?? '',
              'lastMac': enc['mac'] ?? '',
              'e2eeVersion': CryptoService.currentE2eeVersion,
              'lastSenderId': _currentUserId,
              'lastMessageAt': DateTime.now().toIso8601String(),
              'timestamp': DateTime.now().toIso8601String(),
              'unreadCount': 0,
              'lastMessageId': created.$id,
              'lastMessageStatus': MessageDeliveryStatus.sent.value,
              'lastMessageDeliveredAt': '',
              'lastMessageReadAt': '',
            },
          );
        } catch (_) {}
        final senderProfile =
            await AppwriteService.getProfileByUserId(_currentUserId!);
        final senderData = senderProfile?.data ?? <String, dynamic>{};
        final senderName =
            (senderData['displayName'] as String?)?.trim().isNotEmpty == true
                ? (senderData['displayName'] as String).trim()
                : ((senderData['username'] as String?)?.trim().isNotEmpty == true
                    ? (senderData['username'] as String).trim()
                    : 'New message');
        final senderAvatar = (senderData['avatarUrl'] as String?)?.trim() ?? '';
        await AppwriteService.sendChatPushNotification(
          recipientUserId: widget.chat.partnerId,
          chatId: chatId,
          senderUserId: _currentUserId!,
          senderName: senderName,
          senderAvatar: senderAvatar,
          body: text,
        );
      }());
      ChatPreviewCache.set(
        Chat(
          id: chatId,
          partnerId: widget.chat.partnerId,
          partnerName: widget.chat.partnerName,
          partnerAvatar: widget.chat.partnerAvatar,
          lastMessage: text,
          timestamp: DateTime.now(),
          unreadCount: 0,
          isOnline: widget.chat.isOnline,
          lastSenderId: _currentUserId!,
          lastMessageId: created.$id,
          lastMessageStatus: MessageDeliveryStatus.sent.value,
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == optimistic.id);
          _messageController.text = text;
        });
        ChatMessageCache.set(_chatId, _messages);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _showAttachmentPicker() async {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Send image'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _pickAndSendImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Send video'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _pickAndSendVideo();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndSendImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    await _sendMediaMessage(picked, mediaType: 'image');
  }

  Future<void> _pickAndSendVideo() async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    await _sendMediaMessage(picked, mediaType: 'video');
  }

  Future<void> _sendMediaMessage(
    XFile file, {
    required String mediaType,
  }) async {
    if (_currentUserId == null || _isSending) return;
    setState(() => _isSending = true);
    final replyId = _replyingToMessage?.id;
    final replyContent = _replyingToMessage?.content;
    setState(() {
      _replyingToMessage = null;
    });
    try {
      final chatId = _chatId.isNotEmpty ? _chatId : await _ensureChatId();
      final now = DateTime.now();
      ChatPreviewCache.set(
        Chat(
          id: chatId,
          partnerId: widget.chat.partnerId,
          partnerName: widget.chat.partnerName,
          partnerAvatar: widget.chat.partnerAvatar,
          lastMessage: mediaType == 'image' ? 'Photo' : 'Video',
          timestamp: now,
          unreadCount: 0,
          isOnline: widget.chat.isOnline,
          lastSenderId: _currentUserId!,
          lastMessageStatus: MessageDeliveryStatus.pending.value,
        ),
      );
      final ext = p.extension(file.path).toLowerCase();
      final key =
          'chat/$chatId/${mediaType}_${DateTime.now().millisecondsSinceEpoch}$ext';
      final stored = kIsWeb
          ? await StorageService.uploadMultiplePostMedia([file], _currentUserId!)
          : <String>[
              await StorageService.uploadFileAtPath(File(file.path), key)
            ];
      final mediaUrl = await StorageService.getSignedUrl(stored.first);

      final created = await AppwriteService.createDocument(
        AppwriteService.messagesCollectionId,
        {
          'chatId': chatId,
          'senderId': _currentUserId,
          'ciphertext': '',
          'nonce': '',
          'mac': '',
          'e2eeVersion': CryptoService.currentE2eeVersion,
          'mediaUrl': mediaUrl,
          'thumbnailUrl': mediaType == 'image' ? mediaUrl : '',
          'mediaType': mediaType,
          'timestamp': DateTime.now().toIso8601String(),
          'isRead': false,
          'isEdited': false,
          'readBy': _currentUserId!,
          'deliveryStatus': MessageDeliveryStatus.sent.value,
          'sentAt': DateTime.now().toIso8601String(),
          'deliveredAt': '',
          'readAt': '',
          'replyToId': replyId ?? '',
          'replyToContent': replyContent ?? '',
        },
        permissions: [
          Permission.read(Role.any()),
          Permission.write(Role.user(_currentUserId!)),
          Permission.write(Role.users()),
        ],
      );
      final createdMessage = await _decodeMessageData(
        chatId,
        created.$id,
        created.data,
      );
      if (createdMessage != null && mounted) {
        _upsertMessage(createdMessage);
      }

      final previewBody = mediaType == 'image' ? 'Photo' : 'Video';
      unawaited(() async {
        try {
          await AppwriteService.updateRow(
            AppwriteService.chatsCollectionId,
            chatId,
            {
              'lastMessage': previewBody,
              'lastCiphertext': '',
              'lastNonce': '',
              'lastMac': '',
              'e2eeVersion': CryptoService.currentE2eeVersion,
              'lastSenderId': _currentUserId,
              'lastMessageAt': DateTime.now().toIso8601String(),
              'timestamp': DateTime.now().toIso8601String(),
              'unreadCount': 0,
              'lastMessageId': created.$id,
              'lastMessageStatus': MessageDeliveryStatus.sent.value,
              'lastMessageDeliveredAt': '',
              'lastMessageReadAt': '',
            },
          );
        } catch (_) {}
        final senderProfile =
            await AppwriteService.getProfileByUserId(_currentUserId!);
        final senderData = senderProfile?.data ?? <String, dynamic>{};
        final senderName =
            (senderData['displayName'] as String?)?.trim().isNotEmpty == true
                ? (senderData['displayName'] as String).trim()
                : ((senderData['username'] as String?)?.trim().isNotEmpty == true
                    ? (senderData['username'] as String).trim()
                    : 'New message');
        final senderAvatar = (senderData['avatarUrl'] as String?)?.trim() ?? '';
        final notificationBody = mediaType == 'image'
            ? '$senderName sent a photo'
            : '$senderName sent a video';
        await AppwriteService.sendChatPushNotification(
          recipientUserId: widget.chat.partnerId,
          chatId: chatId,
          senderUserId: _currentUserId!,
          senderName: senderName,
          senderAvatar: senderAvatar,
          body: notificationBody,
        );
      }());

      ChatPreviewCache.set(
        Chat(
          id: chatId,
          partnerId: widget.chat.partnerId,
          partnerName: widget.chat.partnerName,
          partnerAvatar: widget.chat.partnerAvatar,
          lastMessage: previewBody,
          timestamp: DateTime.now(),
          unreadCount: 0,
          isOnline: widget.chat.isOnline,
          lastSenderId: _currentUserId!,
          lastMessageId: created.$id,
          lastMessageStatus: MessageDeliveryStatus.sent.value,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send attachment: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _openImagePreview(String url) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: InteractiveViewer(
            child: Image.network(url, fit: BoxFit.contain),
          ),
        );
      },
    );
  }

  Future<void> _openVideoPreview(String url) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _ChatVideoPreviewScreen(url: url)),
    );
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    if (keyboardHeight > 0 && _stickToBottom) {
      _scrollToBottom(smooth: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RealtimeGateway.reconnectTrigger.removeListener(_reconnectListener);
    appRouteObserver.unsubscribe(this);
    _scrollController.removeListener(_handleScroll);
    _messagesSub?.close();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class _ChatVideoPreviewScreen extends StatefulWidget {
  final String url;

  const _ChatVideoPreviewScreen({required this.url});

  @override
  State<_ChatVideoPreviewScreen> createState() =>
      _ChatVideoPreviewScreenState();
}

class _ChatVideoPreviewScreenState extends State<_ChatVideoPreviewScreen> {
  VideoPlayerController? _controller;
  Future<void>? _initFuture;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _initFuture = _controller!.initialize().then((_) {
      _controller!.play();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: Center(
        child: FutureBuilder<void>(
          future: _initFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done ||
                _controller == null ||
                !_controller!.value.isInitialized) {
              return const CircularProgressIndicator(color: Colors.white);
            }
            return AspectRatio(
              aspectRatio: _controller!.value.aspectRatio == 0
                  ? 16 / 9
                  : _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            );
          },
        ),
      ),
      floatingActionButton: _controller == null
          ? null
          : FloatingActionButton(
              onPressed: () {
                if (_controller!.value.isPlaying) {
                  _controller!.pause();
                } else {
                  _controller!.play();
                }
                setState(() {});
              },
              child: Icon(
                _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            ),
    );
  }
}

Future<String?> _decryptCipherMessage(Map<String, String> payload) async {
  try {
    final cipherTextB64 = payload['ciphertextB64'] ?? '';
    final nonceB64 = payload['nonceB64'] ?? '';
    final macB64 = payload['macB64'] ?? '';
    final keyB64 = payload['keyB64'] ?? '';
    if (cipherTextB64.isEmpty ||
        nonceB64.isEmpty ||
        macB64.isEmpty ||
        keyB64.isEmpty) {
      return null;
    }

    final cipher = AesGcm.with256bits();
    final key = SecretKey(base64Decode(keyB64));
    final box = SecretBox(
      base64Decode(cipherTextB64),
      nonce: base64Decode(nonceB64),
      mac: Mac(base64Decode(macB64)),
    );
    final clearBytes = await cipher.decrypt(box, secretKey: key);
    return utf8.decode(clearBytes);
  } catch (_) {
    return null;
  }
}

