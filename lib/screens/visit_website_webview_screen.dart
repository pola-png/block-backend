import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/ad_helper.dart';
import '../services/micro_job_service.dart';

class VisitWebsiteWebviewScreen extends StatefulWidget {
  final String url;
  final double rewardAmount;
  const VisitWebsiteWebviewScreen({super.key, required this.url, this.rewardAmount = 0.20});

  @override
  State<VisitWebsiteWebviewScreen> createState() => _VisitWebsiteWebviewScreenState();
}

class _VisitWebsiteWebviewScreenState extends State<VisitWebsiteWebviewScreen> {
  late final WebViewController _webViewController;
  int _secondsRemaining = 20;
  Timer? _timer;
  bool _completed = false;
  bool _isLoading = true;

  // Banner Ad
  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _loadBannerAd();
    _startTimer();
  }

  void _openInExternalBrowser() async {
    final cleanUrl = widget.url.startsWith('http') ? widget.url : 'https://${widget.url}';
    final uri = Uri.parse(cleanUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not launch external application: $e');
      try {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (e2) {
        debugPrint('Fallback launch error: $e2');
      }
    }
  }

  void _initWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent("Mozilla/5.0 (Linux; Android 13; SM-S901B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Mobile Safari/537.36")
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (url) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (error) {
            debugPrint('WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: AdHelper.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBannerLoaded = true),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('WebView screen banner failed to load: $error');
        },
      ),
    )..load();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        _timer?.cancel();
        _claimReward();
      }
    });
  }

  Future<void> _claimReward() async {
    if (_completed) return;
    setState(() {
      _completed = true;
    });

    final taskId = 'visit_website_${widget.url.hashCode}';
    final mod = widget.url.hashCode.abs() % 10;
    final calcVal = double.parse((0.20 + (mod * 0.033)).clamp(0.20, 0.50).toStringAsFixed(2));
    final reward = widget.rewardAmount > 0.20 ? widget.rewardAmount : calcVal;

    final success = await MicroJobService.rewardUser(taskId, reward);

    if (!mounted) return;
    if (success) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Task Completed!'),
            ],
          ),
          content: Text('You have successfully completed this website visit. A reward of \$${reward.toStringAsFixed(2)} has been added to your balance.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Go back to MicroJobsView
              },
              child: const Text('Great!'),
            ),
          ],
        ),
      );
    } else {
      // In case they already got rewarded, just alert and exit
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reward already claimed or system error. Returning to tasks.'),
          backgroundColor: Colors.orange,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_completed ? 'Completed!' : 'Wait $_secondsRemaining seconds...'),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Open in Chrome/Browser',
            onPressed: _openInExternalBrowser,
          ),
          if (!_completed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    value: (20 - _secondsRemaining) / 20,
                    strokeWidth: 3,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.pinkAccent),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top indicator bar
            Container(
              color: Colors.pinkAccent.withOpacity(0.1),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              alignment: Alignment.center,
              child: Text(
                _completed
                    ? '🎉 Reward earned! You can now go back.'
                    : '⏳ Keep browsing for $_secondsRemaining seconds to earn \$${(widget.rewardAmount > 0.20 ? widget.rewardAmount : double.parse((0.20 + ((widget.url.hashCode.abs() % 10) * 0.033)).clamp(0.20, 0.50).toStringAsFixed(2))).toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            
            // WebView container
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _webViewController),
                  if (_isLoading)
                    const Center(
                      child: CircularProgressIndicator(color: Colors.pinkAccent),
                    ),
                ],
              ),
            ),

            // Bottom Banner Ad
            if (_isBannerLoaded && _bannerAd != null)
              Container(
                alignment: Alignment.center,
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                color: Theme.of(context).scaffoldBackgroundColor,
                child: AdWidget(ad: _bannerAd!),
              ),
          ],
        ),
      ),
    );
  }
}
