import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/native_ad_preload_service.dart';

class HomeInlineNativeAdTile extends StatefulWidget {
  final int slotIndex;
  final bool reserveSpaceWhenLoading;
  final bool sharedPool;

  const HomeInlineNativeAdTile({
    super.key,
    required this.slotIndex,
    required this.reserveSpaceWhenLoading,
    required this.sharedPool,
  });

  @override
  State<HomeInlineNativeAdTile> createState() => _HomeInlineNativeAdTileState();
}

class _HomeInlineNativeAdTileState extends State<HomeInlineNativeAdTile>
    with AutomaticKeepAliveClientMixin {
  NativeAd? _ad;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    NativeAdPreloadService.changes.addListener(_claimAd);
    _claimAd();
  }

  @override
  void didUpdateWidget(covariant HomeInlineNativeAdTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slotIndex != widget.slotIndex) {
      _ad?.dispose();
      _ad = null;
      _claimAd();
    }
  }

  @override
  void dispose() {
    NativeAdPreloadService.changes.removeListener(_claimAd);
    _ad?.dispose();
    super.dispose();
  }

  void _claimAd() {
    if (_ad != null ||
        NativeAdPreloadService.isFailed(widget.slotIndex) ||
        NativeAdPreloadService.isShown(widget.slotIndex)) {
      return;
    }
    final ad = widget.sharedPool
        ? NativeAdPreloadService.takeAnyLoadedAd()
        : NativeAdPreloadService.takeForSlot(widget.slotIndex);
    if (ad != null) {
      if (!mounted) return;
      setState(() => _ad = ad);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_ad == null) {
      if (!widget.reserveSpaceWhenLoading) {
        return const SizedBox.shrink();
      }
      return HomeNativeAdLoadingShell(slotIndex: widget.slotIndex);
    }
    return HomeNativeAdPostCard(slotIndex: widget.slotIndex, ad: _ad!);
  }
}

class HomeNativeAdPostCard extends StatelessWidget {
  final int slotIndex;
  final NativeAd ad;

  const HomeNativeAdPostCard({
    super.key,
    required this.slotIndex,
    required this.ad,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final gapColor = isDark ? Colors.black : Colors.black.withOpacity(0.03);

    final card = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width =
                  constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
              final adHeight =
                  width > 0 ? (width * 0.9).clamp(260.0, 460.0) : 300.0;
              return SizedBox(
                width: double.infinity,
                height: adHeight,
                child: AdWidget(
                  key: ValueKey<int>(slotIndex),
                  ad: ad,
                ),
              );
            },
          ),
          const HomeNativeAdFooter(),
        ],
      ),
    );

    return Container(
      color: gapColor,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: card,
    );
  }
}

class HomeNativeAdHeader extends StatelessWidget {
  final int slotIndex;

  const HomeNativeAdHeader({super.key, required this.slotIndex});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor:
                theme.colorScheme.surfaceContainerHighest.withOpacity(0.8),
            child: Icon(
              Icons.campaign_outlined,
              size: 20,
              color: labelColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Sponsored',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: theme.brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withOpacity(0.6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Ad',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: labelColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
          Icon(Icons.more_vert, color: theme.iconTheme.color),
        ],
      ),
    );
  }
}

class HomeNativeAdFooter extends StatelessWidget {
  const HomeNativeAdFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Text(
        'Sponsored content',
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class HomeNativeAdLoadingShell extends StatelessWidget {
  final int slotIndex;

  const HomeNativeAdLoadingShell({super.key, required this.slotIndex});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final gapColor = isDark ? Colors.black : Colors.black.withOpacity(0.03);

    return Container(
      color: gapColor,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width =
              constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
          final adHeight = width > 0 ? (width * 0.9).clamp(260.0, 460.0) : 300.0;
          final card = Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border:
                  Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
            ),
            child: HomeNativeAdShimmer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: adHeight,
                    width: double.infinity,
                    color: theme.colorScheme.surface,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHigh
                              .withOpacity(0.7),
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Container(
                      height: 12,
                      width: 120,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withOpacity(0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
          return card;
        },
      ),
    );
  }
}

class HomeNativeAdShimmer extends StatefulWidget {
  final Widget child;

  const HomeNativeAdShimmer({super.key, required this.child});

  @override
  State<HomeNativeAdShimmer> createState() => _HomeNativeAdShimmerState();
}

class _HomeNativeAdShimmerState extends State<HomeNativeAdShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerHighest.withOpacity(0.55);
    final highlight = theme.colorScheme.surfaceContainerHigh.withOpacity(0.9);
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final slide = _controller.value * 2 - 1;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1.2 + slide, -0.1),
              end: Alignment(1.2 + slide, 0.1),
              colors: <Color>[base, highlight, base],
              stops: const <double>[0.2, 0.5, 0.8],
            ).createShader(bounds);
          },
          child: RepaintBoundary(child: child!),
        );
      },
    );
  }
}

class HomeTvFocusableTile extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;

  const HomeTvFocusableTile({
    super.key,
    required this.child,
    this.onPressed,
  });

  @override
  State<HomeTvFocusableTile> createState() => _HomeTvFocusableTileState();
}

class _HomeTvFocusableTileState extends State<HomeTvFocusableTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: FocusableActionDetector(
        autofocus: false,
        onShowFocusHighlight: (value) {
          if (_focused == value) return;
          setState(() => _focused = value);
        },
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _focused ? theme.colorScheme.primary : Colors.transparent,
              width: 3,
            ),
            boxShadow: _focused
                ? <BoxShadow>[
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.25),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class HomeTvSponsoredCard extends StatelessWidget {
  final int slotIndex;

  const HomeTvSponsoredCard({super.key, required this.slotIndex});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messages = <Map<String, String>>[
      <String, String>{
        'eyebrow': 'Sponsored',
        'title': 'Watch on the big screen',
        'body':
            'Enjoy videos, news, and creator content in a TV-friendly layout.',
      },
      <String, String>{
        'eyebrow': 'Featured',
        'title': 'Support creators on XapZap',
        'body': 'More watch time and more reach help creators grow faster.',
      },
      <String, String>{
        'eyebrow': 'Spotlight',
        'title': 'Explore trending videos',
        'body': 'Keep browsing to discover fresh videos, reels, and stories.',
      },
    ];
    final message = messages[slotIndex % messages.length];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withOpacity(0.18),
            theme.colorScheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message['eyebrow']!,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message['title']!,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message['body']!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
