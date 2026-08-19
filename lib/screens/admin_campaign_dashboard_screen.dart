import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminCampaignDashboardScreen extends StatefulWidget {
  final bool showAppBar;
  const AdminCampaignDashboardScreen({super.key, this.showAppBar = true});

  @override
  State<AdminCampaignDashboardScreen> createState() => _AdminCampaignDashboardScreenState();
}

class _AdminCampaignDashboardScreenState extends State<AdminCampaignDashboardScreen> {
  List<Map<String, dynamic>> _campaigns = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllCampaigns();
  }

  Future<void> _loadAllCampaigns() async {
    try {
      final res = await Supabase.instance.client
          .from('video_campaigns')
          .select()
          .order('created_at', ascending: false);

      setState(() {
        _campaigns = List<Map<String, dynamic>>.from(res);
      });
    } catch (e) {
      debugPrint('Error loading campaigns: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateCampaignStatus(String id, String status) async {
    try {
      await Supabase.instance.client
          .from('video_campaigns')
          .update({'status': status})
          .eq('id', id);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Campaign status updated to $status!'),
          backgroundColor: Colors.green,
        ),
      );

      _loadAllCampaigns();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showEditDialog(Map<String, dynamic> campaign) async {
    final titleController = TextEditingController(text: campaign['campaign_type'] ?? '');
    final urlController = TextEditingController(text: campaign['video_url'] ?? '');
    final durationController = TextEditingController(text: (campaign['duration_minutes'] ?? 0).toString());
    final targetReviewsController = TextEditingController(text: (campaign['target_reviews'] ?? 0).toString());

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Video Campaign'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(labelText: 'Video URL'),
                ),
                TextField(
                  controller: durationController,
                  decoration: const InputDecoration(labelText: 'Duration (Minutes)'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: targetReviewsController,
                  decoration: const InputDecoration(labelText: 'Target Reviews'),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await Supabase.instance.client
                      .from('video_campaigns')
                      .update({
                        'video_url': urlController.text.trim(),
                        'duration_minutes': int.parse(durationController.text.trim()),
                        'target_reviews': int.parse(targetReviewsController.text.trim()),
                      })
                      .eq('id', campaign['id']);

                  if (mounted) {
                    Navigator.pop(context);
                    _loadAllCampaigns();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Campaign edited successfully!'), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error saving changes: $e'), backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin Campaigns')),
        body: const Center(child: CircularProgressIndicator(color: Colors.pinkAccent)),
      );
    }

    final pending = _campaigns.where((c) => c['status'] == 'pending').toList();
    final active = _campaigns.where((c) => c['status'] == 'active' || c['status'] == 'paused').toList();
    final completed = _campaigns.where((c) => c['status'] == 'completed' || c['status'] == 'rejected').toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: widget.showAppBar
            ? AppBar(
                title: const Text('Admin Campaign Panel', style: TextStyle(fontWeight: FontWeight.bold)),
                bottom: const TabBar(
                  tabs: [
                    Tab(text: 'Pending'),
                    Tab(text: 'Active / Paused'),
                    Tab(text: 'History'),
                  ],
                ),
              )
            : AppBar(
                toolbarHeight: 0,
                elevation: 0,
                backgroundColor: Colors.transparent,
                bottom: const TabBar(
                  tabs: [
                    Tab(text: 'Pending'),
                    Tab(text: 'Active / Paused'),
                    Tab(text: 'History'),
                  ],
                ),
              ),
        body: TabBarView(
          children: [
            _buildCampaignList(pending),
            _buildCampaignList(active),
            _buildCampaignList(completed),
          ],
        ),
      ),
    );
  }

  Widget _buildCampaignList(List<Map<String, dynamic>> list) {
    if (list.isEmpty) {
      return const Center(child: Text('No campaigns found in this category.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final campaign = list[index];
        final id = campaign['id'] as String;
        final status = campaign['status'] as String;
        final reviewsComp = campaign['reviews_completed'] as int? ?? 0;
        final targetReviews = campaign['target_reviews'] as int? ?? 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      campaign['campaign_type'] ?? 'Ad Review Campaign',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    _buildStatusBadge(status),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Video URL: ${campaign['video_url']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Duration: ${campaign['duration_minutes']} mins', style: const TextStyle(fontSize: 13)),
                    Text('Reviews: $reviewsComp / $targetReviews', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Total Paid: \$${(campaign['total_paid'] as num?)?.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, color: Colors.green, fontWeight: FontWeight.bold)),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Edit'),
                      onPressed: () => _showEditDialog(campaign),
                    ),
                    const SizedBox(width: 8),
                    if (status == 'pending') ...[
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                        onPressed: () => _updateCampaignStatus(id, 'active'),
                        child: const Text('Approve'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                        onPressed: () => _updateCampaignStatus(id, 'rejected'),
                        child: const Text('Reject'),
                      ),
                    ],
                    if (status == 'active')
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                        onPressed: () => _updateCampaignStatus(id, 'paused'),
                        child: const Text('Pause'),
                      ),
                    if (status == 'paused')
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                        onPressed: () => _updateCampaignStatus(id, 'active'),
                        child: const Text('Activate'),
                      ),
                    if (status == 'active' || status == 'paused') ...[
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade800, foregroundColor: Colors.white),
                        onPressed: () => _updateCampaignStatus(id, 'completed'),
                        child: const Text('Stop'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = Colors.grey;
    if (status == 'active') color = Colors.green;
    if (status == 'pending') color = Colors.blue;
    if (status == 'paused') color = Colors.orange;
    if (status == 'completed') color = Colors.grey.shade700;
    if (status == 'rejected') color = Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }
}
