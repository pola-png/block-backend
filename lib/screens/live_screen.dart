import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class LiveScreen extends StatefulWidget {
  final bool isGuest;

  const LiveScreen({super.key, this.isGuest = false});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  final TextEditingController _titleController = TextEditingController();
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const <CameraDescription>[];
  bool _isInitializingCamera = true;
  bool _isShowingComingSoon = false;
  String? _cameraError;
  int _activeCameraIndex = 0;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _isInitializingCamera = true;
      _cameraError = null;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera found on this device.');
      }
      _cameras = cameras;
      final preferredIndex = cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      _activeCameraIndex = preferredIndex >= 0 ? preferredIndex : 0;
      await _attachCamera(_cameras[_activeCameraIndex]);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraError = 'Unable to open camera.';
        _isInitializingCamera = false;
      });
    }
  }

  Future<void> _attachCamera(CameraDescription description) async {
    final previous = _cameraController;
    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: true,
    );
    _cameraController = controller;
    if (previous != null) {
      await previous.dispose();
    }
    try {
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);
      if (!mounted) return;
      setState(() {
        _isInitializingCamera = false;
        _cameraError = null;
      });
    } catch (_) {
      await controller.dispose();
      if (_cameraController == controller) {
        _cameraController = null;
      }
      if (!mounted) return;
      setState(() {
        _cameraError = 'Unable to open camera.';
        _isInitializingCamera = false;
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isInitializingCamera) return;
    final nextIndex = (_activeCameraIndex + 1) % _cameras.length;
    setState(() => _isInitializingCamera = true);
    _activeCameraIndex = nextIndex;
    await _attachCamera(_cameras[nextIndex]);
  }

  Future<void> _goLive() async {
    if (_isShowingComingSoon) return;
    FocusScope.of(context).unfocus();
    if (widget.isGuest) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to start a live stream.')),
      );
      return;
    }
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a live title first.')),
      );
      return;
    }
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _cameraError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera is not ready yet.')),
      );
      return;
    }

    setState(() => _isShowingComingSoon = true);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() => _isShowingComingSoon = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Coming soon. Live streaming will be connected later.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildCameraSurface(theme)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopBar(context),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomSheet(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraSurface(ThemeData theme) {
    if (_isInitializingCamera) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: CircularProgressIndicator(
          color: theme.colorScheme.primary,
        ),
      );
    }

    if (_cameraError != null ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return Container(
        color: const Color(0xFF050816),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.videocam_off,
                color: Colors.white70,
                size: 54,
              ),
              const SizedBox(height: 16),
              const Text(
                'Camera unavailable',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _cameraError ?? 'Unable to open camera preview.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              OutlinedButton(
                onPressed: _initializeCamera,
                child: const Text('Retry camera'),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: _cameraController!.value.previewSize!.height,
          height: _cameraController!.value.previewSize!.width,
          child: CameraPreview(_cameraController!),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            const Spacer(),
            if (_cameras.length > 1)
              _buildCircleButton(
                icon: Icons.cameraswitch,
                onTap: _switchCamera,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildBottomSheet(ThemeData theme) {
    final canGoLive =
        _titleController.text.trim().isNotEmpty && !_isInitializingCamera;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
        decoration: BoxDecoration(
          color: const Color(0xCC090B12),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const Text(
              'Start Live',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add a title, check your camera, then go live.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Live title',
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 54,
                child: ElevatedButton(
                onPressed: canGoLive && !_isShowingComingSoon ? _goLive : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF3B30),
                  disabledBackgroundColor: Colors.white24,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Text(
                  _isShowingComingSoon ? 'Coming Soon' : 'Go Live',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }
}
