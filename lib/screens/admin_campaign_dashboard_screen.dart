import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/micro_job_service.dart';

class AdminCampaignDashboardScreen extends StatefulWidget {
  final bool showAppBar;
  const AdminCampaignDashboardScreen({super.key, this.showAppBar = true});

  @override
  State<AdminCampaignDashboardScreen> createState() => _AdminCampaignDashboardScreenState();
}

class _AdminCampaignDashboardScreenState extends State<AdminCampaignDashboardScreen> {
  List<Map<String, dynamic>> _campaigns = [];
  List<Map<String, dynamic>> _websiteTasks = [];
  bool _isLoading = true;
  final TextEditingController _urlInputController = TextEditingController();
  final TextEditingController _payoutInputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _urlInputController.dispose();
    _payoutInputController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    final baseVal = await MicroJobService.getTotalPayoutBase();
    _payoutInputController.text = baseVal.toStringAsFixed(2);
    await Future.wait([
      _loadAllCampaigns(),
      _loadWebsiteTasks(),
    ]);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadAllCampaigns() async {
    try {
      final res = await Supabase.instance.client
          .from('video_campaigns')
          .select()
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _campaigns = List<Map<String, dynamic>>.from(res);
        });
      }
    } catch (e) {
      debugPrint('Error loading campaigns: $e');
    }
  }

  Future<void> _loadWebsiteTasks() async {
    try {
      final res = await Supabase.instance.client
          .from('website_tasks')
          .select()
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _websiteTasks = res.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading website tasks: $e');
      try {
        final prefs = await SharedPreferences.getInstance();
        final localList = prefs.getStringList('local_website_tasks') ?? [];
        final List<Map<String, dynamic>> fallback = [];
        for (final url in localList) {
          final isVisible = prefs.getBool('visibility_$url') ?? true;
          fallback.add({
            'url': url,
            'is_visible': isVisible,
            'id': url.hashCode.toString(),
          });
        }
        if (mounted) {
          setState(() {
            _websiteTasks = fallback;
          });
        }
      } catch (_) {}
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

  Future<void> _addWebsiteTask(String url) async {
    if (url.trim().isEmpty) return;
    try {
      await Supabase.instance.client
          .from('website_tasks')
          .insert({'url': url.trim(), 'is_visible': true});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Website task added successfully!'), backgroundColor: Colors.green),
      );
      _urlInputController.clear();
      _loadWebsiteTasks();
    } catch (e) {
      debugPrint('Error adding website task: $e');
      try {
        final prefs = await SharedPreferences.getInstance();
        final localList = prefs.getStringList('local_website_tasks') ?? [];
        if (!localList.contains(url.trim())) {
          localList.add(url.trim());
          await prefs.setStringList('local_website_tasks', localList);
          await prefs.setBool('visibility_${url.trim()}', true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved locally (Supabase table error)!'), backgroundColor: Colors.orange),
          );
          _urlInputController.clear();
          _loadWebsiteTasks();
        }
      } catch (_) {}
    }
  }

  Future<void> _deleteWebsiteTask(String url) async {
    final originalTasks = List<Map<String, dynamic>>.from(_websiteTasks);
    setState(() {
      _websiteTasks.removeWhere((t) => t['url'] == url);
    });

    try {
      await Supabase.instance.client
          .from('website_tasks')
          .delete()
          .eq('url', url);
      
      final prefs = await SharedPreferences.getInstance();
      final localList = prefs.getStringList('local_website_tasks') ?? [];
      if (localList.contains(url)) {
        localList.remove(url);
        await prefs.setStringList('local_website_tasks', localList);
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Website task deleted successfully!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      setState(() {
        _websiteTasks = originalTasks;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting website task: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _toggleWebsiteTaskVisibility(String url, bool currentVisibility) async {
    setState(() {
      final index = _websiteTasks.indexWhere((t) => t['url'] == url);
      if (index != -1) {
        _websiteTasks[index]['is_visible'] = !currentVisibility;
      }
    });

    try {
      await Supabase.instance.client
          .from('website_tasks')
          .update({'is_visible': !currentVisibility})
          .eq('url', url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Visibility status updated!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      // Fallback/rollback
      setState(() {
        final index = _websiteTasks.indexWhere((t) => t['url'] == url);
        if (index != -1) {
          _websiteTasks[index]['is_visible'] = currentVisibility;
        }
      });
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('visibility_$url', !currentVisibility);
        setState(() {
          final index = _websiteTasks.indexWhere((t) => t['url'] == url);
          if (index != -1) {
            _websiteTasks[index]['is_visible'] = !currentVisibility;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Updated visibility status locally!'), backgroundColor: Colors.orange),
        );
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating visibility: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggleWebsiteTaskDirect(String url, bool currentDirect) async {
    setState(() {
      final index = _websiteTasks.indexWhere((t) => t['url'] == url);
      if (index != -1) {
        _websiteTasks[index]['is_direct'] = !currentDirect;
      }
    });

    try {
      await Supabase.instance.client
          .from('website_tasks')
          .update({'is_direct': !currentDirect})
          .eq('url', url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Direct mode updated!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      // Fallback/rollback
      setState(() {
        final index = _websiteTasks.indexWhere((t) => t['url'] == url);
        if (index != -1) {
          _websiteTasks[index]['is_direct'] = currentDirect;
        }
      });
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('direct_$url', !currentDirect);
        setState(() {
          final index = _websiteTasks.indexWhere((t) => t['url'] == url);
          if (index != -1) {
            _websiteTasks[index]['is_direct'] = !currentDirect;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Updated direct mode locally!'), backgroundColor: Colors.orange),
        );
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating direct mode: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildWebsiteTasksPanel() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Configure App Total Payouts (USD)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _payoutInputController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            hintText: 'Enter base total payout amount...',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          final val = double.tryParse(_payoutInputController.text.trim());
                          if (val != null) {
                            await MicroJobService.saveTotalPayoutBase(val);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Total Payout updated successfully!'), backgroundColor: Colors.green),
                              );
                            }
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter a valid numeric value.'), backgroundColor: Colors.red),
                            );
                          }
                        },
                        child: const Text('Update'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add Website Visit Job',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _urlInputController,
                          decoration: const InputDecoration(
                            hintText: 'Enter target website URL...',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          if (_urlInputController.text.trim().isNotEmpty) {
                            _addWebsiteTask(_urlInputController.text);
                          }
                        },
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: _websiteTasks.isEmpty
              ? const Center(child: Text('No website visit jobs found.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _websiteTasks.length,
                  itemBuilder: (context, index) {
                    final task = _websiteTasks[index];
                    final url = task['url'] as String;
                    final isVisible = task['is_visible'] == true;
                    final isDirect = task['is_direct'] == true;
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(
                          url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        subtitle: Text(
                          '${isVisible ? "Visible" : "Hidden"} | Mode: ${isDirect ? "Direct Browser" : "In-App Webview"}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isVisible ? Colors.green : Colors.grey,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                isDirect ? Icons.open_in_new : Icons.tab,
                                color: isDirect ? Colors.purple : Colors.grey,
                              ),
                              tooltip: isDirect ? 'Redirection: Direct Browser' : 'Redirection: WebView',
                              onPressed: () => _toggleWebsiteTaskDirect(url, isDirect),
                            ),
                            IconButton(
                              icon: Icon(
                                isVisible ? Icons.visibility : Icons.visibility_off,
                                color: isVisible ? Colors.blue : Colors.grey,
                              ),
                              onPressed: () => _toggleWebsiteTaskVisibility(url, isVisible),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteWebsiteTask(url),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
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
      length: 4,
      child: Scaffold(
        appBar: widget.showAppBar
            ? AppBar(
                title: const Text('Admin Campaign Panel', style: TextStyle(fontWeight: FontWeight.bold)),
                bottom: const TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Pending'),
                    Tab(text: 'Active / Paused'),
                    Tab(text: 'History'),
                    Tab(text: 'Website Tasks'),
                  ],
                ),
              )
            : AppBar(
                toolbarHeight: 0,
                elevation: 0,
                backgroundColor: Colors.transparent,
                bottom: const TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Pending'),
                    Tab(text: 'Active / Paused'),
                    Tab(text: 'History'),
                    Tab(text: 'Website Tasks'),
                  ],
                ),
              ),
        body: TabBarView(
          children: [
            _buildCampaignList(pending),
            _buildCampaignList(active),
            _buildCampaignList(completed),
            _buildWebsiteTasksPanel(),
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
