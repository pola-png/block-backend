import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/ad_helper.dart';
import '../services/micro_job_service.dart';
import 'visit_website_webview_screen.dart';

class VisitWebsiteGatewayScreen extends StatefulWidget {
  final String url;
  final bool isDirect;
  const VisitWebsiteGatewayScreen({super.key, required this.url, this.isDirect = false});

  @override
  State<VisitWebsiteGatewayScreen> createState() => _VisitWebsiteGatewayScreenState();
}

class _VisitWebsiteGatewayScreenState extends State<VisitWebsiteGatewayScreen> {
  int _secondsRemaining = 20;
  Timer? _timer;
  bool _canProceed = false;

  // Multiple banner ads for high density
  BannerAd? _bannerAd1;
  BannerAd? _bannerAd2;
  BannerAd? _bannerAd3;
  bool _isBanner1Loaded = false;
  bool _isBanner2Loaded = false;
  bool _isBanner3Loaded = false;

  // Interstitial Ad
  InterstitialAd? _interstitialAd;
  bool _isInterstitialLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAds();
    _startCountdown();
  }

  void _loadAds() {
    // Load Banner Ad 1 (Top)
    _bannerAd1 = BannerAd(
      adUnitId: AdHelper.banner,
      size: AdSize.mediumRectangle, // medium rectangle to make it massive
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBanner1Loaded = true),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('Gateway Banner 1 failed to load: $error');
        },
      ),
    )..load();

    // Load Banner Ad 2 (Middle)
    _bannerAd2 = BannerAd(
      adUnitId: AdHelper.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBanner2Loaded = true),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('Gateway Banner 2 failed to load: $error');
        },
      ),
    )..load();

    // Load Banner Ad 3 (Bottom)
    _bannerAd3 = BannerAd(
      adUnitId: AdHelper.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBanner3Loaded = true),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('Gateway Banner 3 failed to load: $error');
        },
      ),
    )..load();

    // Load Interstitial Ad
    InterstitialAd.load(
      adUnitId: AdHelper.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialLoaded = true;
          debugPrint('Gateway Interstitial loaded successfully.');
          // Auto play interstitial as soon as it's ready to maximize ad exposure
          _showInterstitialAd();
        },
        onAdFailedToLoad: (error) {
          debugPrint('Gateway Interstitial failed to load: $error');
        },
      ),
    );
  }

  void _showInterstitialAd() {
    if (_isInterstitialLoaded && _interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _interstitialAd = null;
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          _interstitialAd = null;
        },
      );
      _interstitialAd!.show();
    }
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        setState(() {
          _canProceed = true;
        });
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bannerAd1?.dispose();
    _bannerAd2?.dispose();
    _bannerAd3?.dispose();
    _interstitialAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Website Task Gateway'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Container(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Banner 2 (Top Banner)
              if (_isBanner2Loaded && _bannerAd2 != null)
                Container(
                  alignment: Alignment.center,
                  width: _bannerAd2!.size.width.toDouble(),
                  height: _bannerAd2!.size.height.toDouble(),
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: AdWidget(ad: _bannerAd2!),
                ),

              const SizedBox(height: 16),

              // Countdown / Progress Section
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        _canProceed ? 'Ready to Proceed!' : 'Please wait on this page...',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _canProceed ? Colors.green : theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 100,
                            height: 100,
                            child: CircularProgressIndicator(
                              value: (20 - _secondsRemaining) / 20,
                              strokeWidth: 8,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _canProceed ? Colors.green : Colors.pinkAccent,
                              ),
                              backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                            ),
                          ),
                          Text(
                            '$_secondsRemaining',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _canProceed ? Colors.green : Colors.grey,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _canProceed
                            ? () async {
                                if (widget.isDirect) {
                                  // Open URL directly in external browser and pop this screen
                                  try {
                                    final uri = Uri.parse(widget.url);
                                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                                    // Credit reward
                                    await MicroJobService.rewardUser('visit_website_${widget.url.hashCode}', 0.03);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('🎉 \$0.03 reward credited!'), backgroundColor: Colors.green),
                                      );
                                      Navigator.pop(context);
                                    }
                                  } catch (e) {
                                    debugPrint('Could not launch URL directly: $e');
                                    // Fallback to embedded WebView if launch fails
                                    if (mounted) {
                                      Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => VisitWebsiteWebviewScreen(url: widget.url),
                                        ),
                                      );
                                    }
                                  }
                                } else {
                                  // Navigate to WebView and pop this gateway screen
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => VisitWebsiteWebviewScreen(url: widget.url),
                                    ),
                                  );
                                }
                              }
                            : null,
                        child: const Text(
                          'Continue to Website',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Banner 1 (Massive MREC Ad)
              if (_isBanner1Loaded && _bannerAd1 != null)
                Container(
                  alignment: Alignment.center,
                  width: _bannerAd1!.size.width.toDouble(),
                  height: _bannerAd1!.size.height.toDouble(),
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: AdWidget(ad: _bannerAd1!),
                )
              else
                Container(
                  width: 300,
                  height: 250,
                  alignment: Alignment.center,
                  color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: const Text('Advertisement Loading...'),
                ),

              const SizedBox(height: 16),

              // Banner 3 (Bottom Banner)
              if (_isBanner3Loaded && _bannerAd3 != null)
                Container(
                  alignment: Alignment.center,
                  width: _bannerAd3!.size.width.toDouble(),
                  height: _bannerAd3!.size.height.toDouble(),
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: AdWidget(ad: _bannerAd3!),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  }
}
