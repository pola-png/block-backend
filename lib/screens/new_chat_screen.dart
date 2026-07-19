import 'package:flutter/material.dart';

import '../services/appwrite_service.dart';
import '../models/chat.dart';
import '../services/profile_preview_cache.dart';
import 'individual_chat_screen.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<ProfilePreview> _profiles = <ProfilePreview>[];
  List<ProfilePreview> _filteredProfiles = <ProfilePreview>[];
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    final cached = ProfilePreviewCache.getAll();
    if (cached.isNotEmpty) {
      _profiles = List<ProfilePreview>.from(cached);
      _filteredProfiles = List<ProfilePreview>.from(cached);
    }
    _loadProfiles();
    _searchController.addListener(_filterUsers);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    final me = await AppwriteService.getCurrentUser();
    if (me == null) return;
    _currentUserId = me.$id;

    try {
      final list = await AppwriteService.getDocuments(
        AppwriteService.profilesCollectionId,
        queries: [],
      );
      if (!mounted) return;
      final previews = list.rows
          .where((row) => (row.data['userId'] as String?) != me.$id)
          .map(
            (row) => ProfilePreview(
              userId: (row.data['userId'] as String?) ?? row.$id,
              displayName: (row.data['displayName'] as String?) ?? '',
              username: (row.data['username'] as String?) ?? '',
              avatarUrl: (row.data['avatarUrl'] as String?) ?? '',
            ),
          )
          .where((preview) => preview.userId.isNotEmpty)
          .toList(growable: false);
      setState(() {
        _profiles = previews;
        _filteredProfiles = List<ProfilePreview>.from(previews);
      });
      ProfilePreviewCache.setAll(previews);
    } catch (_) {}
  }

  void _filterUsers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredProfiles = _profiles.where((row) {
        return row.displayName.toLowerCase().contains(query) ||
            row.username.toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Chat'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search for people',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredProfiles.length,
              itemBuilder: (context, index) {
                final row = _filteredProfiles[index];
                final userId = row.userId;
                final displayName = row.displayName;
                final avatar = row.avatarUrl;

                return ListTile(
                  leading: CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFF29ABE2),
                    backgroundImage:
                        avatar.isNotEmpty && avatar.startsWith('http')
                            ? NetworkImage(avatar)
                            : null,
                    child: avatar.isEmpty && displayName.isNotEmpty
                        ? Text(displayName[0])
                        : null,
                  ),
                  title: Text(displayName),
                  onTap: () => _startChatWith(userId, displayName, avatar),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startChatWith(
      String partnerId, String partnerName, String avatar) async {
    if (_currentUserId == null) {
      final me = await AppwriteService.getCurrentUser();
      if (me == null) return;
      _currentUserId = me.$id;
    }
    try {
      final chatId =
          await AppwriteService.getChatId(_currentUserId!, partnerId);
      final chat = Chat(
        id: chatId,
        partnerId: partnerId,
        partnerName: partnerName,
        partnerAvatar: avatar,
        lastMessage: '',
        timestamp: DateTime.now(),
        unreadCount: 0,
        isOnline: false,
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => IndividualChatScreen(chat: chat)),
      );
    } catch (_) {}
  }
}
