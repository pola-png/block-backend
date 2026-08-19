import 'dart:async';

import 'package:xapzap/models/database_models.dart' show Query;
import 'package:xapzap/models/database_models.dart' as aw;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../services/backend_service.dart';
import '../services/network_status_service.dart';

class AdminDesktopBootstrap extends StatelessWidget {
  final bool supported;

  const AdminDesktopBootstrap({super.key, required this.supported});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XapZap Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F62FE),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F62FE),
          brightness: Brightness.dark,
        ),
      ),
      home: supported
          ? const _NetworkOverlay(child: AdminDesktopApp())
          : const _UnsupportedDesktopScreen(),
    );
  }
}

class AdminDesktopApp extends StatefulWidget {
  const AdminDesktopApp({super.key});

  @override
  State<AdminDesktopApp> createState() => _AdminDesktopAppState();
}

class _AdminDesktopAppState extends State<AdminDesktopApp> {
  late Future<_AdminSessionState> _sessionFuture;

  @override
  void initState() {
    super.initState();
    _sessionFuture = _loadSession();
  }

  Future<_AdminSessionState> _loadSession() async {
    final user = await BackendService.getCurrentUser();
    if (user == null) {
      return const _AdminSessionState.signedOut();
    }
    final isAdmin = await BackendService.isCurrentUserAdmin();
    return _AdminSessionState(user: user, isAdmin: isAdmin);
  }

  Future<void> _refreshSession() async {
    setState(() {
      _sessionFuture = _loadSession();
    });
  }

  Future<void> _handleSignOut() async {
    await BackendService.signOut();
    if (!mounted) return;
    await _refreshSession();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AdminSessionState>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final session = snapshot.data ?? const _AdminSessionState.signedOut();
        if (session.user == null) {
          return AdminDesktopSignInScreen(
            onSignedIn: _refreshSession,
          );
        }
        if (!session.isAdmin) {
          return _AdminUnauthorizedScreen(
            email: session.user?.email,
            onSignOut: _handleSignOut,
          );
        }
        return AdminDesktopShell(
          user: session.user!,
          onSignOut: _handleSignOut,
        );
      },
    );
  }
}

class AdminDesktopSignInScreen extends StatefulWidget {
  final Future<void> Function() onSignedIn;

  const AdminDesktopSignInScreen({super.key, required this.onSignedIn});

  @override
  State<AdminDesktopSignInScreen> createState() =>
      _AdminDesktopSignInScreenState();
}

class _AdminDesktopSignInScreenState extends State<AdminDesktopSignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your admin email and password.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await BackendService.signIn(email, password);
      final isAdmin = await BackendService.isCurrentUserAdmin();
      if (!isAdmin) {
        await BackendService.signOut();
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _error = 'This account does not have admin access.';
        });
        return;
      }
      if (!mounted) return;
      await widget.onSignedIn();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Sign in failed. Check credentials and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            elevation: 0,
            margin: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: BorderSide(color: theme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'XapZap Admin Console',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Desktop-only control panel for admin operations, moderation, users, and platform monitoring.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Admin email',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: Text(_submitting ? 'Signing in...' : 'Sign in'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminDesktopShell extends StatefulWidget {
  final aw.User user;
  final Future<void> Function() onSignOut;

  const AdminDesktopShell({
    super.key,
    required this.user,
    required this.onSignOut,
  });

  @override
  State<AdminDesktopShell> createState() => _AdminDesktopShellState();
}

class _AdminDesktopShellState extends State<AdminDesktopShell> {
  int _selectedIndex = 0;
  int _refreshTick = 0;

  void _refreshAll() {
    setState(() => _refreshTick++);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final destinations = <_AdminDestination>[
      const _AdminDestination('Overview', Icons.dashboard_outlined),
      const _AdminDestination('Users', Icons.people_alt_outlined),
      const _AdminDestination('Moderation', Icons.gavel_outlined),
      const _AdminDestination('Support', Icons.support_agent_outlined),
      const _AdminDestination('Payouts', Icons.payments_outlined),
      const _AdminDestination('Creators', Icons.workspace_premium_outlined),
      const _AdminDestination('Data', Icons.storage_outlined),
      const _AdminDestination('Operations', Icons.settings_suggest_outlined),
    ];

    final pages = <Widget>[
      AdminOverviewPanel(refreshTick: _refreshTick),
      AdminUsersPanel(refreshTick: _refreshTick),
      AdminModerationPanel(refreshTick: _refreshTick),
      AdminSupportReportsPanel(refreshTick: _refreshTick),
      AdminPayoutsPanel(refreshTick: _refreshTick),
      AdminCreatorToolsPanel(refreshTick: _refreshTick),
      AdminDataBrowserPanel(refreshTick: _refreshTick),
      AdminOperationsPanel(refreshTick: _refreshTick),
    ];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
            },
            labelType: NavigationRailLabelType.all,
            minWidth: 88,
            minExtendedWidth: 220,
            extended: true,
            destinations: destinations
                .map(
                  (item) => NavigationRailDestination(
                    icon: Icon(item.icon),
                    label: Text(item.label),
                  ),
                )
                .toList(growable: false),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _refreshAll,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: widget.onSignOut,
                        icon: const Icon(Icons.logout),
                        label: const Text('Sign out'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(
                      bottom: BorderSide(color: theme.dividerColor),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              destinations[_selectedIndex].label,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Admin-only desktop workspace for platform control and operations.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            widget.user.name.trim().isEmpty
                                ? 'Admin'
                                : widget.user.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            widget.user.email,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: KeyedSubtree(
                      key: ValueKey<int>(_selectedIndex),
                      child: pages[_selectedIndex],
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
}

class AdminOverviewPanel extends StatefulWidget {
  final int refreshTick;

  const AdminOverviewPanel({super.key, required this.refreshTick});

  @override
  State<AdminOverviewPanel> createState() => _AdminOverviewPanelState();
}

class _AdminOverviewPanelState extends State<AdminOverviewPanel> {
  late Future<_AdminOverviewData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant AdminOverviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) {
      _future = _load();
    }
  }

  Future<_AdminOverviewData> _load() async {
    Future<int> countOf(String tableId) async {
      final res = await BackendService.getDocuments(
        tableId,
        queries: <String>[Query.limit(1)],
      );
      return res.total;
    }

    final profileRes = await BackendService.listProfiles(limit: 8);
    final notificationsRes = await BackendService.getDocuments(
      BackendService.notificationsCollectionId,
      queries: <String>[Query.limit(8)],
    );

    final counts = await Future.wait<int>(<Future<int>>[
      countOf(BackendService.profilesCollectionId),
      countOf(BackendService.postsCollectionId),
      countOf(BackendService.commentsCollectionId),
      countOf(BackendService.reportsCollectionId),
      countOf(BackendService.notificationsCollectionId),
      countOf(BackendService.messagesCollectionId),
      countOf(BackendService.chatsCollectionId),
      countOf(BackendService.adImpressionsCollectionId),
    ]);

    return _AdminOverviewData(
      totalUsers: counts[0],
      totalPosts: counts[1],
      totalComments: counts[2],
      totalReports: counts[3],
      totalNotifications: counts[4],
      totalMessages: counts[5],
      totalChats: counts[6],
      totalAdImpressions: counts[7],
      recentProfiles: profileRes.rows,
      recentNotifications: notificationsRes.rows,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AdminOverviewData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _AdminErrorState(
            message: 'Failed to load admin overview.',
            onRetry: () => setState(() => _future = _load()),
          );
        }

        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _MetricCard('Users', '${data.totalUsers}', Icons.people_alt),
                _MetricCard('Posts', '${data.totalPosts}', Icons.article),
                _MetricCard(
                    'Comments', '${data.totalComments}', Icons.chat_bubble),
                _MetricCard('Reports', '${data.totalReports}', Icons.flag),
                _MetricCard('Notifications', '${data.totalNotifications}',
                    Icons.notifications),
                _MetricCard('Messages', '${data.totalMessages}', Icons.forum),
                _MetricCard('Chats', '${data.totalChats}', Icons.chat),
                _MetricCard('Ad impressions', '${data.totalAdImpressions}',
                    Icons.attach_money),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _AdminPanelCard(
                    title: 'Recent users',
                    child: Column(
                      children: data.recentProfiles.isEmpty
                          ? const <Widget>[
                              Padding(
                                padding: EdgeInsets.all(20),
                                child: Text('No user profiles found.'),
                              ),
                            ]
                          : data.recentProfiles
                              .map((row) => _SimpleRowTile(
                                    title: _displayName(row),
                                    subtitle:
                                        '@${(row.data['username'] ?? '').toString()}',
                                    trailing: _badgeText(
                                      row.data['isAdmin'] == true
                                          ? 'Admin'
                                          : 'Member',
                                    ),
                                  ))
                              .toList(growable: false),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _AdminPanelCard(
                    title: 'Recent notifications',
                    child: Column(
                      children: data.recentNotifications.isEmpty
                          ? const <Widget>[
                              Padding(
                                padding: EdgeInsets.all(20),
                                child: Text('No notification records found.'),
                              ),
                            ]
                          : data.recentNotifications
                              .map((row) => _SimpleRowTile(
                                    title: _rowText(
                                      row,
                                      <String>['title', 'type', 'message'],
                                      fallback: 'Notification',
                                    ),
                                    subtitle: _rowText(
                                      row,
                                      <String>['message', 'body', 'type'],
                                      fallback: 'No message body',
                                    ),
                                    trailing: _badgeText(
                                      _rowText(
                                        row,
                                        <String>['type', 'category'],
                                        fallback: 'event',
                                      ),
                                    ),
                                  ))
                              .toList(growable: false),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class AdminUsersPanel extends StatefulWidget {
  final int refreshTick;

  const AdminUsersPanel({super.key, required this.refreshTick});

  @override
  State<AdminUsersPanel> createState() => _AdminUsersPanelState();
}

class _AdminUsersPanelState extends State<AdminUsersPanel> {
  late Future<List<aw.Row>> _future;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AdminUsersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) {
      _future = _load();
    }
  }

  Future<List<aw.Row>> _load() async {
    final res = await BackendService.listProfiles(limit: 120);
    return res.rows;
  }

  Future<void> _toggleAdmin(aw.Row row, bool value) async {
    await BackendService.setAdminFlag(row.$id, value);
    if (!mounted) return;
    setState(() {
      row.data['isAdmin'] = value;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_displayName(row)} updated.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<aw.Row>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _AdminErrorState(
            message: 'Failed to load users.',
            onRetry: () => setState(() => _future = _load()),
          );
        }

        final query = _searchController.text.trim().toLowerCase();
        final allRows = snapshot.data ?? const <aw.Row>[];
        final filtered = allRows.where((row) {
          if (query.isEmpty) return true;
          final data = row.data;
          final haystack = <String>[
            (data['displayName'] ?? '').toString(),
            (data['username'] ?? '').toString(),
            (data['email'] ?? '').toString(),
            row.$id,
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        }).toList(growable: false);

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search users by name, username, email, or id',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _searchController.clear()),
                  icon: const Icon(Icons.clear),
                ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            _AdminPanelCard(
              title: 'Profiles (${filtered.length})',
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Display name')),
                    DataColumn(label: Text('Username')),
                    DataColumn(label: Text('Country')),
                    DataColumn(label: Text('Admin')),
                  ],
                  rows: filtered
                      .map(
                        (row) => DataRow(
                          cells: [
                            DataCell(Text(_displayName(row))),
                            DataCell(Text(
                              '@${(row.data['username'] ?? '').toString()}',
                            )),
                            DataCell(Text(
                              (row.data['country'] ?? '-').toString(),
                            )),
                            DataCell(
                              Switch(
                                value: row.data['isAdmin'] == true,
                                onChanged: (value) => _toggleAdmin(row, value),
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class AdminModerationPanel extends StatelessWidget {
  final int refreshTick;

  const AdminModerationPanel({super.key, required this.refreshTick});

  Future<List<aw.Row>> _loadPosts() async {
    final res = await BackendService.getDocuments(
      BackendService.postsCollectionId,
      queries: <String>[Query.limit(24)],
    );
    return res.rows;
  }

  Future<List<aw.Row>> _loadComments() async {
    final res = await BackendService.getDocuments(
      BackendService.commentsCollectionId,
      queries: <String>[Query.limit(24)],
    );
    return res.rows;
  }

  Future<void> _deletePost(BuildContext context, aw.Row row) async {
    await BackendService.deletePost(row.$id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Post deleted.')),
    );
  }

  Future<void> _deleteComment(BuildContext context, aw.Row row) async {
    await BackendService.deleteComment(row.$id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Comment deleted.')),
    );
  }

  Future<void> _addModerationNote(
    BuildContext context,
    aw.Row row,
    String tableId,
  ) async {
    final note = await _promptForText(
      context,
      title: 'Moderation note',
      label: 'Add internal moderation note',
      initialValue: (row.data['moderationNotes'] ?? '').toString(),
    );
    if (note == null) return;
    await BackendService.updateRow(
      tableId,
      row.$id,
      <String, dynamic>{
        'moderationNotes': note,
        'lastModeratedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Moderation note saved.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _AsyncPanel(
                title: 'Recent posts',
                loader: _loadPosts,
                emptyText: '',
                itemBuilder: (row) => _ActionRowTile(
                  title: _rowText(
                    row,
                    <String>['title', 'content', 'caption'],
                    fallback: 'Untitled post',
                  ),
                  subtitle: _rowText(
                    row,
                    <String>['username', 'postType'],
                    fallback: row.$id,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => _addModerationNote(
                        context,
                        row,
                        BackendService.postsCollectionId,
                      ),
                      child: const Text('Add note'),
                    ),
                    TextButton(
                      onPressed: () => _deletePost(context, row),
                      child: const Text('Delete'),
                    ),
                  ],
                  trailing: _badgeText('Likes ${_intValue(row.data['likes'])}'),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _AsyncPanel(
                title: 'Recent comments',
                loader: _loadComments,
                emptyText: 'No comments found.',
                itemBuilder: (row) => _ActionRowTile(
                  title: _rowText(
                    row,
                    <String>['content'],
                    fallback: 'Comment',
                  ),
                  subtitle: _rowText(
                    row,
                    <String>['username', 'userId'],
                    fallback: row.$id,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => _addModerationNote(
                        context,
                        row,
                        BackendService.commentsCollectionId,
                      ),
                      child: const Text('Add note'),
                    ),
                    TextButton(
                      onPressed: () => _deleteComment(context, row),
                      child: const Text('Delete'),
                    ),
                  ],
                  trailing: _badgeText('Likes ${_intValue(row.data['likes'])}'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class AdminSupportReportsPanel extends StatelessWidget {
  final int refreshTick;

  const AdminSupportReportsPanel({super.key, required this.refreshTick});

  Future<List<aw.Row>> _loadReports() async {
    final res = await BackendService.getDocuments(
      BackendService.reportsCollectionId,
      queries: <String>[Query.limit(60)],
    );
    return res.rows;
  }

  Future<List<aw.Row>> _loadSupportRequests() async {
    final res = await BackendService.getDocuments(
      BackendService.supportRequestsCollectionId,
      queries: <String>[Query.limit(60)],
    );
    return res.rows;
  }

  Future<void> _setRequestStatus(
    BuildContext context,
    aw.Row row,
    String tableId,
    String status,
  ) async {
    await BackendService.updateRow(
      tableId,
      row.$id,
      <String, dynamic>{
        'status': status,
        'resolvedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Updated to $status.')),
    );
  }

  Future<void> _addReportNote(BuildContext context, aw.Row row) async {
    final note = await _promptForText(
      context,
      title: 'Report note',
      label: 'Internal report note',
      initialValue: (row.data['moderationNotes'] ?? '').toString(),
    );
    if (note == null) return;
    await BackendService.updateRow(
      BackendService.reportsCollectionId,
      row.$id,
      <String, dynamic>{
        'moderationNotes': note,
        'lastModeratedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report note saved.')),
    );
  }

  Future<void> _replyToSupport(BuildContext context, aw.Row row) async {
    final reply = await _promptForText(
      context,
      title: 'Admin reply',
      label: 'Reply to support request',
      initialValue: (row.data['adminReply'] ?? '').toString(),
    );
    if (reply == null) return;
    await BackendService.updateRow(
      BackendService.supportRequestsCollectionId,
      row.$id,
      <String, dynamic>{
        'adminReply': reply,
        'repliedAt': DateTime.now().toUtc().toIso8601String(),
        'status': 'answered',
      },
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Support reply saved.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _AsyncPanel(
                title: 'Content reports',
                loader: _loadReports,
                emptyText: 'No reports found.',
                itemBuilder: (row) => _ActionRowTile(
                  title: _rowText(
                    row,
                    <String>['reason', 'reportReason', 'type'],
                    fallback: 'Report',
                  ),
                  subtitle: 'Target: ${_rowText(row, <String>[
                        'postId',
                        'userId'
                      ], fallback: row.$id)}',
                  actions: [
                    TextButton(
                      onPressed: () => _addReportNote(context, row),
                      child: const Text('Add note'),
                    ),
                    TextButton(
                      onPressed: () => _setRequestStatus(
                        context,
                        row,
                        BackendService.reportsCollectionId,
                        'reviewing',
                      ),
                      child: const Text('Reviewing'),
                    ),
                    TextButton(
                      onPressed: () => _setRequestStatus(
                        context,
                        row,
                        BackendService.reportsCollectionId,
                        'resolved',
                      ),
                      child: const Text('Resolve'),
                    ),
                  ],
                  trailing: _badgeText(
                    _rowText(
                      row,
                      <String>['status', 'type'],
                      fallback: 'open',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _AsyncPanel(
                title: 'Support requests',
                loader: _loadSupportRequests,
                emptyText: 'No support requests found.',
                itemBuilder: (row) => _ActionRowTile(
                  title: _rowText(
                    row,
                    <String>['subject', 'category'],
                    fallback: 'Support request',
                  ),
                  subtitle: '${_rowText(row, <String>[
                        'displayName',
                        'username',
                        'email'
                      ], fallback: row.$id)}\n${_rowText(row, <String>['message'], fallback: 'No message')}',
                  actions: [
                    TextButton(
                      onPressed: () => _replyToSupport(context, row),
                      child: const Text('Reply'),
                    ),
                    TextButton(
                      onPressed: () => _setRequestStatus(
                        context,
                        row,
                        BackendService.supportRequestsCollectionId,
                        'in_progress',
                      ),
                      child: const Text('In progress'),
                    ),
                    TextButton(
                      onPressed: () => _setRequestStatus(
                        context,
                        row,
                        BackendService.supportRequestsCollectionId,
                        'resolved',
                      ),
                      child: const Text('Resolve'),
                    ),
                  ],
                  trailing: _badgeText(
                    _rowText(
                      row,
                      <String>['status', 'category'],
                      fallback: 'open',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class AdminPayoutsPanel extends StatelessWidget {
  final int refreshTick;

  const AdminPayoutsPanel({super.key, required this.refreshTick});

  Future<List<aw.Row>> _loadPayouts() async {
    final res = await BackendService.getDocuments(
      BackendService.creatorPayoutsCollectionId,
      queries: <String>[Query.limit(60)],
    );
    return res.rows;
  }

  Future<List<aw.Row>> _loadBalances() async {
    final res = await BackendService.getDocuments(
      BackendService.creatorBalancesCollectionId,
      queries: <String>[Query.limit(60)],
    );
    return res.rows;
  }

  Future<void> _setPayoutStatus(
    BuildContext context,
    aw.Row row,
    String status,
  ) async {
    await BackendService.updateRow(
      BackendService.creatorPayoutsCollectionId,
      row.$id,
      <String, dynamic>{'status': status},
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Payout marked $status.')),
    );
  }

  Future<void> _addPayoutNote(BuildContext context, aw.Row row) async {
    final note = await _promptForText(
      context,
      title: 'Payout approval note',
      label: 'Add approval or payout note',
      initialValue: (row.data['approvalNotes'] ?? '').toString(),
    );
    if (note == null) return;
    await BackendService.updateRow(
      BackendService.creatorPayoutsCollectionId,
      row.$id,
      <String, dynamic>{
        'approvalNotes': note,
        'approvedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Payout note saved.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _AsyncPanel(
                title: 'Payout requests',
                loader: _loadPayouts,
                emptyText: 'No payout rows found.',
                itemBuilder: (row) => _ActionRowTile(
                  title: _rowText(
                    row,
                    <String>['creatorId', 'status'],
                    fallback: row.$id,
                  ),
                  subtitle: 'Amount: ${_rowText(row, <String>[
                        'amountUsd',
                        'amount'
                      ], fallback: '-')}',
                  actions: [
                    TextButton(
                      onPressed: () => _addPayoutNote(context, row),
                      child: const Text('Add note'),
                    ),
                    TextButton(
                      onPressed: () =>
                          _setPayoutStatus(context, row, 'processing'),
                      child: const Text('Processing'),
                    ),
                    TextButton(
                      onPressed: () => _setPayoutStatus(context, row, 'paid'),
                      child: const Text('Paid'),
                    ),
                  ],
                  trailing: _badgeText(
                    _rowText(row, <String>['status'], fallback: 'requested'),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _AsyncPanel(
                title: 'Creator balances',
                loader: _loadBalances,
                emptyText: 'No balance rows found.',
                itemBuilder: (row) => _SimpleRowTile(
                  title: _rowText(
                    row,
                    <String>['creatorId'],
                    fallback: row.$id,
                  ),
                  subtitle: 'Available: ${_rowText(row, <String>[
                        'availableBalanceUsd'
                      ], fallback: '0')}',
                  trailing: _badgeText(
                    'Lifetime ${_rowText(row, <String>[
                          'lifetimeEarningsUsd'
                        ], fallback: '0')}',
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class AdminCreatorToolsPanel extends StatefulWidget {
  final int refreshTick;

  const AdminCreatorToolsPanel({super.key, required this.refreshTick});

  @override
  State<AdminCreatorToolsPanel> createState() => _AdminCreatorToolsPanelState();
}

class _AdminCreatorToolsPanelState extends State<AdminCreatorToolsPanel> {
  final TextEditingController _creatorIdController = TextEditingController();
  Future<_CreatorSupportData?>? _future;

  @override
  void dispose() {
    _creatorIdController.dispose();
    super.dispose();
  }

  Future<_CreatorSupportData?> _loadCreator(String creatorId) async {
    final trimmed = creatorId.trim();
    if (trimmed.isEmpty) return null;
    final profile = await BackendService.getProfileByUserId(trimmed) ??
        await BackendService.getRow(
          BackendService.profilesCollectionId,
          trimmed,
        );
    final summary =
        await BackendService.fetchCreatorEarningsSummary(creatorId: trimmed);
    final balance = await BackendService.getLatestCreatorBalance(trimmed);
    final referrals = await BackendService.fetchReferralFollows(trimmed);
    return _CreatorSupportData(
      creatorId: trimmed,
      profile: profile,
      earningsSummary: summary,
      balance: balance,
      referralCount: referrals.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: _creatorIdController,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: 'Creator user id',
            suffixIcon: IconButton(
              onPressed: () {
                setState(() {
                  _future = _loadCreator(_creatorIdController.text);
                });
              },
              icon: const Icon(Icons.search),
            ),
          ),
          onSubmitted: (_) {
            setState(() {
              _future = _loadCreator(_creatorIdController.text);
            });
          },
        ),
        const SizedBox(height: 16),
        if (_future != null)
          FutureBuilder<_CreatorSupportData?>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data;
              if (data == null) {
                return const _AdminPanelCard(
                  title: 'Creator support',
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                        'Enter a creator user id to inspect account data.'),
                  ),
                );
              }
              return _AdminPanelCard(
                title: 'Creator support summary',
                child: Column(
                  children: [
                    _kvRow('Creator id', data.creatorId),
                    _kvRow('Display name', _displayName(data.profile)),
                    _kvRow(
                      'Username',
                      '@${(data.profile.data['username'] ?? '').toString()}',
                    ),
                    _kvRow(
                      'Tracked impressions',
                      '${_intValue(data.earningsSummary['impressions'])}',
                    ),
                    _kvRow(
                      'Creator earnings USD',
                      '${data.earningsSummary['creatorEarningsUsd'] ?? 0}',
                    ),
                    _kvRow(
                      'Referral earnings USD',
                      '${data.earningsSummary['referralEarningsUsd'] ?? 0}',
                    ),
                    _kvRow(
                      'Available balance USD',
                      '${data.balance?.data['availableBalanceUsd'] ?? 0}',
                    ),
                    _kvRow('Referral count', '${data.referralCount}'),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

class AdminDataBrowserPanel extends StatefulWidget {
  final int refreshTick;

  const AdminDataBrowserPanel({super.key, required this.refreshTick});

  @override
  State<AdminDataBrowserPanel> createState() => _AdminDataBrowserPanelState();
}

class _AdminDataBrowserPanelState extends State<AdminDataBrowserPanel> {
  String _tableId = BackendService.postsCollectionId;
  late Future<List<aw.Row>> _future;
  final TextEditingController _searchController = TextEditingController();
  String _sortField = 'id';
  bool _descending = true;

  static const List<String> _tableIds = [
    BackendService.profilesCollectionId,
    BackendService.postsCollectionId,
    BackendService.commentsCollectionId,
    BackendService.reportsCollectionId,
    BackendService.supportRequestsCollectionId,
    BackendService.notificationsCollectionId,
    BackendService.messagesCollectionId,
    BackendService.chatsCollectionId,
    BackendService.creatorBalancesCollectionId,
    BackendService.creatorPayoutsCollectionId,
    BackendService.adImpressionsCollectionId,
  ];

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<aw.Row>> _load() async {
    final res = await BackendService.getDocuments(
      _tableId,
      queries: <String>[Query.limit(50)],
    );
    return res.rows;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _tableId,
                decoration: const InputDecoration(
                  labelText: 'Database table',
                  border: OutlineInputBorder(),
                ),
                items: _tableIds
                    .map(
                      (table) => DropdownMenuItem(
                        value: table,
                        child: Text(table),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _tableId = value;
                    _future = _load();
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: () => setState(() => _future = _load()),
              icon: const Icon(Icons.refresh),
              label: const Text('Load'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Filter rows by id, field name, or value',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _searchController.clear()),
                    icon: const Icon(Icons.clear),
                  ),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                initialValue: _sortField,
                decoration: const InputDecoration(
                  labelText: 'Sort by',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'id', child: Text('Row id')),
                  DropdownMenuItem(
                    value: 'createdAt',
                    child: Text('createdAt'),
                  ),
                  DropdownMenuItem(
                    value: 'updatedAt',
                    child: Text('updatedAt'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _sortField = value);
                },
              ),
            ),
            const SizedBox(width: 12),
            FilterChip(
              selected: _descending,
              label: Text(_descending ? 'Descending' : 'Ascending'),
              onSelected: (_) => setState(() => _descending = !_descending),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<aw.Row>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _AdminErrorState(
                message: 'Failed to load table data.',
                onRetry: () => setState(() => _future = _load()),
              );
            }
            final rows = List<aw.Row>.from(snapshot.data ?? const <aw.Row>[]);
            rows.sort((a, b) {
              final left = _sortValue(a, _sortField);
              final right = _sortValue(b, _sortField);
              final result = left.compareTo(right);
              return _descending ? -result : result;
            });
            final query = _searchController.text.trim().toLowerCase();
            final filtered = rows.where((row) {
              if (query.isEmpty) return true;
              final haystack =
                  '${row.$id} ${row.data.keys.join(' ')} ${row.data.values.join(' ')}'
                      .toLowerCase();
              return haystack.contains(query);
            }).toList(growable: false);
            return _AdminPanelCard(
              title: 'Rows (${filtered.length})',
              child: Column(
                children: filtered.isEmpty
                    ? const [
                        Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('No rows found.'),
                        ),
                      ]
                    : filtered
                        .map(
                          (row) => ExpansionTile(
                            title: Text(row.$id),
                            subtitle: Text(
                              row.data.keys.take(4).join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: SelectableText(
                                  row.data.toString(),
                                ),
                              ),
                            ],
                          ),
                        )
                        .toList(growable: false),
              ),
            );
          },
        ),
      ],
    );
  }
}

class AdminOperationsPanel extends StatefulWidget {
  final int refreshTick;

  const AdminOperationsPanel({super.key, required this.refreshTick});

  @override
  State<AdminOperationsPanel> createState() => _AdminOperationsPanelState();
}

class _AdminOperationsPanelState extends State<AdminOperationsPanel> {
  bool _syncing = false;
  String? _syncStatus;

  Future<void> _runAdmobSync() async {
    setState(() {
      _syncing = true;
      _syncStatus = null;
    });
    try {
      final result = await BackendService.syncAdmobRevenue();
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _syncStatus = result == null ? 'No sync response returned.' : '$result';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _syncStatus = 'AdMob sync failed.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _AdminPanelCard(
          title: 'Environment',
          child: Column(
            children: [
              _kvRow('Site URL', dotenv.env['XAPZAP_SITE_URL'] ?? '-'),
              _kvRow(
                'Block/filter function',
                dotenv.env['BLOCK_FILTER_FUNCTION_ID'] ?? '-',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _AdminPanelCard(
          title: 'Backend actions',
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilledButton.icon(
                  onPressed: _syncing ? null : _runAdmobSync,
                  icon: const Icon(Icons.sync),
                  label: Text(_syncing ? 'Syncing...' : 'Sync AdMob revenue'),
                ),
                if (_syncStatus != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _syncStatus!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AsyncPanel extends StatefulWidget {
  final String title;
  final Future<List<aw.Row>> Function() loader;
  final String emptyText;
  final Widget Function(aw.Row row) itemBuilder;

  const _AsyncPanel({
    required this.title,
    required this.loader,
    required this.emptyText,
    required this.itemBuilder,
  });

  @override
  State<_AsyncPanel> createState() => _AsyncPanelState();
}

class _AsyncPanelState extends State<_AsyncPanel> {
  late Future<List<aw.Row>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loader();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<aw.Row>>(
      future: _future,
      builder: (context, snapshot) {
        return _AdminPanelCard(
          title: widget.title,
          child: Builder(
            builder: (context) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Failed to load ${widget.title.toLowerCase()}.'),
                );
              }
              final rows = snapshot.data ?? const <aw.Row>[];
              if (rows.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(widget.emptyText),
                );
              }
              return Column(
                children: rows.map(widget.itemBuilder).toList(growable: false),
              );
            },
          ),
        );
      },
    );
  }
}

class _AdminErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _AdminErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminUnauthorizedScreen extends StatelessWidget {
  final String? email;
  final Future<void> Function() onSignOut;

  const _AdminUnauthorizedScreen({
    required this.email,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.admin_panel_settings_outlined, size: 52),
                  const SizedBox(height: 16),
                  Text(
                    'Admin access required',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    email == null
                        ? 'This account does not have admin access.'
                        : '$email is signed in, but admin access is not enabled for it.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: onSignOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnsupportedDesktopScreen extends StatelessWidget {
  const _UnsupportedDesktopScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'The admin console is intended for Windows, macOS, or Linux desktop builds.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _NetworkOverlay extends StatelessWidget {
  final Widget child;

  const _NetworkOverlay({required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NetworkBannerState>(
      valueListenable: NetworkStatusService.bannerState,
      builder: (context, bannerState, _) {
        final isVisible = bannerState != NetworkBannerState.hidden;
        final isOffline = bannerState == NetworkBannerState.offline;
        final bannerColor =
            isOffline ? const Color(0xFFB3261E) : const Color(0xFF10B981);
        final bannerText = isOffline ? 'No network' : 'Back online';
        return Stack(
          children: [
            child,
            if (isVisible)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Material(
                  color: bannerColor,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Text(
                        bannerText,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _MetricCard(this.title, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 210,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminPanelCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _AdminPanelCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const Divider(height: 1),
          child,
        ],
      ),
    );
  }
}

class _SimpleRowTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _SimpleRowTile({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
    );
  }
}

class _ActionRowTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> actions;
  final Widget? trailing;

  const _ActionRowTile({
    required this.title,
    required this.subtitle,
    required this.actions,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      isThreeLine: true,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(subtitle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: actions,
          ),
        ],
      ),
      trailing: trailing,
    );
  }
}

class _AdminDestination {
  final String label;
  final IconData icon;

  const _AdminDestination(this.label, this.icon);
}

class _AdminSessionState {
  final aw.User? user;
  final bool isAdmin;

  const _AdminSessionState({
    this.user,
    required this.isAdmin,
  });

  const _AdminSessionState.signedOut()
      : user = null,
        isAdmin = false;
}

class _AdminOverviewData {
  final int totalUsers;
  final int totalPosts;
  final int totalComments;
  final int totalReports;
  final int totalNotifications;
  final int totalMessages;
  final int totalChats;
  final int totalAdImpressions;
  final List<aw.Row> recentProfiles;
  final List<aw.Row> recentNotifications;

  const _AdminOverviewData({
    required this.totalUsers,
    required this.totalPosts,
    required this.totalComments,
    required this.totalReports,
    required this.totalNotifications,
    required this.totalMessages,
    required this.totalChats,
    required this.totalAdImpressions,
    required this.recentProfiles,
    required this.recentNotifications,
  });
}

class _CreatorSupportData {
  final String creatorId;
  final aw.Row profile;
  final Map<String, dynamic> earningsSummary;
  final aw.Row? balance;
  final int referralCount;

  const _CreatorSupportData({
    required this.creatorId,
    required this.profile,
    required this.earningsSummary,
    required this.balance,
    required this.referralCount,
  });
}

Widget _badgeText(String text) {
  return Builder(
    builder: (context) {
      final theme = Theme.of(context);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withOpacity(0.10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    },
  );
}

Widget _kvRow(String label, String value) {
  return ListTile(
    title: Text(label),
    subtitle: SelectableText(value),
  );
}

String _displayName(aw.Row row) {
  final data = row.data;
  final displayName = (data['displayName'] ?? '').toString().trim();
  return displayName;
}

String _rowText(aw.Row row, List<String> keys, {required String fallback}) {
  for (final key in keys) {
    final value = row.data[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return fallback;
}

int _intValue(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

String _sortValue(aw.Row row, String field) {
  switch (field) {
    case 'createdAt':
      return (row.data['createdAt'] ?? row.$createdAt).toString();
    case 'updatedAt':
      return (row.data['updatedAt'] ?? row.$updatedAt).toString();
    case 'id':
    default:
      return row.$id;
  }
}

Future<String?> _promptForText(
  BuildContext context, {
  required String title,
  required String label,
  String initialValue = '',
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        minLines: 4,
        maxLines: 8,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (result == null || result.trim().isEmpty) return null;
  return result.trim();
}
