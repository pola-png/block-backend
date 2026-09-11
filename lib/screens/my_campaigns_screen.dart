import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MyCampaignsScreen extends StatefulWidget {
  final bool showAppBar;
  const MyCampaignsScreen({super.key, this.showAppBar = true});

  @override
  State<MyCampaignsScreen> createState() => _MyCampaignsScreenState();
}

class _MyCampaignsScreenState extends State<MyCampaignsScreen> {
  List<Map<String, dynamic>> _campaigns = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserCampaigns();
  }

  Future<void> _loadUserCampaigns() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final res = await Supabase.instance.client
          .from('video_campaigns')
          .select()
          .eq('advertiser_id', user.id)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _campaigns = List<Map<String, dynamic>>.from(res);
        });
      }
    } catch (e) {
      debugPrint('Error loading user campaigns: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.blue;
      case 'approved':
      case 'active':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'pending':
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF121212) : const Color(0xFFF9FAFC);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('My Campaigns', style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: backgroundColor,
              elevation: 0,
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.pinkAccent))
          : _campaigns.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.campaign_outlined, size: 64, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5)),
                      const SizedBox(height: 16),
                      Text(
                        'No campaigns submitted yet.',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadUserCampaigns,
                  color: Colors.pinkAccent,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _campaigns.length,
                    itemBuilder: (context, index) {
                      final campaign = _campaigns[index];
                      final status = (campaign['status'] as String? ?? 'pending').toUpperCase();
                      final totalPaid = (campaign['total_paid'] as num? ?? 0).toDouble();
                      final targetReviews = campaign['target_reviews'] as int? ?? 0;
                      final reviewsCompleted = campaign['reviews_completed'] as int? ?? 0;
                      final duration = campaign['duration_minutes'] as int? ?? 0;
                      final type = campaign['campaign_type'] as String? ?? 'Short video';
                      final dateStr = campaign['created_at'] as String?;
                      final date = dateStr != null ? DateTime.parse(dateStr) : DateTime.now();

                      final statusColor = _getStatusColor(status);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        color: isDark ? theme.cardColor : Colors.white,
                        elevation: isDark ? 2 : 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? theme.colorScheme.primaryContainer.withOpacity(0.2)
                                          : theme.colorScheme.primaryContainer.withOpacity(0.6),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      type.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? theme.colorScheme.primary : theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      status,
                                      style: TextStyle(
                                        color: statusColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                campaign['video_url'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const Divider(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildStatColumn('Duration', '$duration mins', theme),
                                  _buildStatColumn('Reviews Done', '$reviewsCompleted/$targetReviews', theme),
                                  _buildStatColumn('Total Paid', '\$${totalPaid.toStringAsFixed(2)}', theme),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Submitted: ${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildStatColumn(String label, String value, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
