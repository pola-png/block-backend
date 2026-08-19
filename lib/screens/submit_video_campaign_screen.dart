import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutterwave_standard/flutterwave.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/backend_service.dart';
import '../services/currency_service.dart';
import 'my_campaigns_screen.dart';
import 'admin_campaign_dashboard_screen.dart';

class SubmitVideoCampaignScreen extends StatefulWidget {
  const SubmitVideoCampaignScreen({super.key});

  @override
  State<SubmitVideoCampaignScreen> createState() => _SubmitVideoCampaignScreenState();
}

class _SubmitVideoCampaignScreenState extends State<SubmitVideoCampaignScreen> {
  final _formKey = GlobalKey<FormState>();
  final _videoUrlController = TextEditingController();
  final _titleController = TextEditingController();
  final _durationController = TextEditingController();
  final _targetReviewsController = TextEditingController();

  String _campaignType = 'Promo';
  int _targetLevel = 2; // Level 2, 3, 4
  double _calculatedCost = 0.0;
  bool _isProcessing = false;
  bool _isAdmin = false;

  final Map<int, double> _levelBasePayout = {
    2: 0.30, // Level 2 max review rate
    3: 0.60, // Level 3 max review rate
    4: 1.00, // Level 4 max review rate
  };

  @override
  void initState() {
    super.initState();
    _durationController.addListener(_calculateTotalCost);
    _targetReviewsController.addListener(_calculateTotalCost);
    BackendService.adminModeOverride.addListener(_checkAdminRole);
    _checkAdminRole();
  }

  Future<void> _checkAdminRole() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final profileRes = await Supabase.instance.client
            .from('profiles')
            .select('is_admin')
            .eq('id', user.id)
            .maybeSingle();
        if (profileRes != null) {
          final isAdm = profileRes['is_admin'] == true && BackendService.adminModeOverride.value;
          setState(() {
            _isAdmin = isAdm;
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking admin role: $e');
    }
  }

  void _calculateTotalCost() {
    final reviews = int.tryParse(_targetReviewsController.text.trim()) ?? 0;
    final userPayout = _levelBasePayout[_targetLevel] ?? 0.30;
    
    // Total cost includes 60% markup (Total = Payout * 1.60)
    final double perReviewAdvertiserRate = userPayout * 1.60;
    final total = reviews * perReviewAdvertiserRate;

    setState(() {
      _calculatedCost = total;
    });
  }

  Future<void> _submitCampaign() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final user = await BackendService.getCurrentUser();
      if (user == null) throw StateError('You must be logged in to submit a campaign.');

      if (!_isAdmin) {
        final publicKey = dotenv.env['FLW_PUBLIC_KEY'] ?? '';
        final redirectUrl = dotenv.env['FLW_REDIRECT_URL'] ?? 'https://example.com';
        final isTestMode = (dotenv.env['FLW_TEST_MODE'] ?? 'true') == 'true';

        if (publicKey.isEmpty) {
          throw StateError('Flutterwave public key is missing in .env');
        }

        final customer = Customer(
          name: user.name.trim().isNotEmpty ? user.name : 'XapZap User',
          phoneNumber: '08000000000',
          email: user.email.trim().isNotEmpty ? user.email : 'user@xapzap.com',
        );

        final txRef = 'xapzap_campaign_${user.$id}_${DateTime.now().millisecondsSinceEpoch}';

        // Fetch network-detected local currency and exchange rates dynamically
        final localCurrencyInfo = await CurrencyService.getLocalCurrencyInfo(_calculatedCost);
        final finalCurrency = localCurrencyInfo.currencyCode;
        final finalAmount = localCurrencyInfo.convertedAmount;

        final flutterwave = Flutterwave(
          publicKey: publicKey,
          currency: finalCurrency,
          amount: finalAmount.toStringAsFixed(2),
          customer: customer,
          txRef: txRef,
          redirectUrl: redirectUrl,
          paymentOptions: "card,account,ussd,barter",
          customization: Customization(
            title: "XapZap Campaign: ${_titleController.text.trim()}",
            description: "Submit video for ${finalAmount.toStringAsFixed(2)} $finalCurrency",
          ),
          isTestMode: isTestMode,
        );

        if (!mounted) return;
        final ChargeResponse response = await flutterwave.charge(context);

        debugPrint('Flutterwave Campaign ChargeResponse: status=${response.status}, txRef=${response.txRef}');

        final String status = (response.status ?? '').toLowerCase();
        if (status != 'success' && status != 'successful') {
          throw StateError('Payment failed. Status: "${response.status}", TxRef: "${response.txRef}", TransID: "${response.transactionId}"');
        }
      }

      // Save campaign details to Supabase database
      final supabaseUser = Supabase.instance.client.auth.currentUser;
      if (supabaseUser == null) throw StateError('User session expired');

      await Supabase.instance.client.from('video_campaigns').insert({
        'advertiser_id': supabaseUser.id,
        'video_url': _videoUrlController.text.trim(),
        'campaign_type': _campaignType,
        'duration_minutes': int.parse(_durationController.text.trim()),
        'target_reviews': int.parse(_targetReviewsController.text.trim()),
        'reviews_completed': 0,
        'total_paid': _calculatedCost,
        'status': 'pending',
      });

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Campaign Submitted'),
              ],
            ),
            content: const Text(
              'Your video campaign was successfully funded and submitted! Our administrators will review the content and activate it shortly.',
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Close submit screen
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Submission failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _durationController.removeListener(_calculateTotalCost);
    _targetReviewsController.removeListener(_calculateTotalCost);
    BackendService.adminModeOverride.removeListener(_checkAdminRole);
    _videoUrlController.dispose();
    _titleController.dispose();
    _durationController.dispose();
    _targetReviewsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final int tabCount = _isAdmin ? 3 : 2;

    return DefaultTabController(
      length: tabCount,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Promote Video / Ad Review', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: TabBar(
            isScrollable: false,
            indicatorColor: Colors.pinkAccent,
            labelColor: Colors.pinkAccent,
            unselectedLabelColor: isDark ? Colors.white70 : Colors.black87,
            tabs: [
              const Tab(text: 'Submit Ad'),
              const Tab(text: 'My Campaigns'),
              if (_isAdmin) const Tab(text: 'Admin Control'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildSubmitForm(context, theme),
            const MyCampaignsScreen(showAppBar: false),
            if (_isAdmin) const AdminCampaignDashboardScreen(showAppBar: false),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitForm(BuildContext context, ThemeData theme) {
    return Stack(
      children: [
        Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // Youtube Guidelines drop section card
              Card(
                color: Colors.deepPurple.shade900.withOpacity(0.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.deepPurple.shade700, width: 1.5),
                ),
                child: ExpansionTile(
                  leading: const Icon(Icons.video_library, color: Colors.pinkAccent),
                  title: const Text(
                    'YouTube Ad Review Guide 🎬',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.pinkAccent),
                  ),
                  childrenPadding: const EdgeInsets.all(16.0),
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Before submitting your ad for rating reviews, please upload it to YouTube to make sure it plays cleanly:',
                          style: TextStyle(fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 8),
                        _buildStepItem('1. Upload the video to your YouTube account.'),
                        _buildStepItem('2. Set the privacy state to "Unlisted" so it remains hidden from your public channel but accessible to our reviewers.'),
                        _buildStepItem('3. Copy the video link and paste it into the URL field below.'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Text(
                'Campaign Details',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Campaign Title',
                  prefixIcon: const Icon(Icons.title),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (val) => val == null || val.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _videoUrlController,
                decoration: InputDecoration(
                  labelText: 'YouTube / Facebook Video URL',
                  prefixIcon: const Icon(Icons.link),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Required';
                  if (!val.startsWith('http')) return 'Enter a valid URL';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: _campaignType,
                decoration: InputDecoration(
                  labelText: 'Video Type / Category',
                  prefixIcon: const Icon(Icons.category),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: const [
                  DropdownMenuItem(value: 'Promo', child: Text('Promo Video / Ad Campaign')),
                  DropdownMenuItem(value: 'Short Film', child: Text('Short Film / Creative Content')),
                  DropdownMenuItem(value: 'Product Review', child: Text('Product Feature Review')),
                  DropdownMenuItem(value: 'Vlog / Hook', child: Text('Vlog / Hook Testing')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _campaignType = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _durationController,
                      decoration: InputDecoration(
                        labelText: 'Duration (Minutes)',
                        prefixIcon: const Icon(Icons.timer),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (val) {
                        if (val == null || val.isEmpty) return 'Required';
                        final numVal = int.tryParse(val);
                        if (numVal == null || numVal <= 0) return 'Must be > 0';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _targetLevel,
                      decoration: InputDecoration(
                        labelText: 'Target Level',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 2, child: Text('Bronze (Lvl 2)')),
                        DropdownMenuItem(value: 3, child: Text('Silver (Lvl 3)')),
                        DropdownMenuItem(value: 4, child: Text('Gold (Lvl 4)')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _targetLevel = val;
                            _calculateTotalCost();
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _targetReviewsController,
                decoration: InputDecoration(
                  labelText: 'Target Number of Reviews',
                  prefixIcon: const Icon(Icons.people_outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                keyboardType: TextInputType.number,
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Required';
                  final numVal = int.tryParse(val);
                  if (numVal == null || numVal <= 0) return 'Must be > 0';
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Pricing Summary Card
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Cost Per Review (with commission):', style: TextStyle(color: Colors.grey)),
                          Text(
                            '\$${((_levelBasePayout[_targetLevel] ?? 0.30) * 1.60).toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Budget Required:',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '\$${_calculatedCost.toStringAsFixed(2)} USD',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isProcessing ? null : _submitCampaign,
                child: const Text('Fund & Launch Campaign', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          ),
        ),
        if (_isProcessing)
          Container(
            color: Colors.black54,
            child: const Center(
              child: CircularProgressIndicator(color: Colors.pinkAccent),
            ),
          ),
      ],
    );
  }

  Widget _buildStepItem(String step) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        step,
        style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.3),
      ),
    );
  }
}
