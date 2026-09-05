import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../../core/constants/app_routes.dart';

class UploadMediaScreen extends StatefulWidget {
  const UploadMediaScreen({super.key});

  @override
  State<UploadMediaScreen> createState() => _UploadMediaScreenState();
}

class _UploadMediaScreenState extends State<UploadMediaScreen> {
  // ── Theme colours ──────────────────────────────────────────────────────────
  static const Color _bg       = Color(0xFF0A1628);
  static const Color _card     = Color(0xFF111F3A);
  static const Color _yellow   = Color(0xFFFFD700);
  static const Color _inputFill= Color(0xFF0D1E35);
  static const Color _border   = Color(0xFF1E3A5F);
  static const Color _textPri  = Colors.white;
  static const Color _textSec  = Color(0xFF8899BB);

  // ── Size limits ────────────────────────────────────────────────────────────
  static const int _maxPhotos        = 5;
  static const int _minPhotos        = 2;
  static const int _maxPhotoMB       = 8;   // 8 MB per photo
  static const int _maxVideoMB       = 50;  // 50 MB for video

  final ImagePicker _picker = ImagePicker();
  final List<File> _photos  = [];
  File? _video;

  // ──────────────────────────────────────────────────────────────────────────
  //  Pickers
  // ──────────────────────────────────────────────────────────────────────────

  void _showPhotoSource() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // handle
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: _border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: _yellow),
                title: const Text('Choose from Gallery',
                    style: TextStyle(color: _textPri)),
                onTap: () {
                  Navigator.pop(context);
                  _pickFromGallery();
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: _yellow),
                title: const Text('Take Photo',
                    style: TextStyle(color: _textPri)),
                onTap: () {
                  Navigator.pop(context);
                  _pickFromCamera();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFromGallery() async {
    final remaining = _maxPhotos - _photos.length;
    if (remaining <= 0) return;

    final picked = await _picker.pickMultiImage(
      imageQuality: 85,
    );
    if (picked.isEmpty) return;

    final List<File> valid = [];
    for (final xf in picked.take(remaining)) {
      final file = File(xf.path);
      final sizeBytes = await file.length();
      if (sizeBytes > _maxPhotoMB * 1024 * 1024) {
        _showSnack('Photo too large. Max ${_maxPhotoMB}MB per photo.');
        continue;
      }
      valid.add(file);
    }

    setState(() => _photos.addAll(valid));
  }

  Future<void> _pickFromCamera() async {
    if (_photos.length >= _maxPhotos) return;

    final xf = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (xf == null) return;

    final file = File(xf.path);
    final sizeBytes = await file.length();
    if (sizeBytes > _maxPhotoMB * 1024 * 1024) {
      _showSnack('Photo too large. Max ${_maxPhotoMB}MB per photo.');
      return;
    }
    setState(() => _photos.add(file));
  }

  Future<void> _pickVideo() async {
    final xf = await _picker.pickVideo(source: ImageSource.gallery);
    if (xf == null) return;

    final file = File(xf.path);
    final sizeBytes = await file.length();
    if (sizeBytes > _maxVideoMB * 1024 * 1024) {
      _showSnack('Video too large. Max ${_maxVideoMB}MB.');
      return;
    }
    setState(() => _video = file);
  }

  void _removePhoto(int index) => setState(() => _photos.removeAt(index));
  void _removeVideo()          => setState(() => _video = null);

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: _card,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Full-screen preview
  // ──────────────────────────────────────────────────────────────────────────

  void _openPhotoPreview(File file) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _FullScreenPhoto(file: file),
    ));
  }

  void _openVideoPreview(File file) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _FullScreenVideo(file: file),
    ));
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Continue
  // ──────────────────────────────────────────────────────────────────────────

  void _onContinue() {
    if (_photos.length < _minPhotos) {
      _showSnack('Please upload at least $_minPhotos photos.');
      return;
    }

    // Retrieve args passed from CreateRequestScreen
    final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>? ?? {};

    Navigator.pushNamed(
      context,
      AppRoutes.requestSummary,
      arguments: {
        ...args,
        'photos': _photos,
        'video': _video,
      },
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Build
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _textPri),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Upload Media',
          style: TextStyle(
            color: _textPri,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Step indicator ────────────────────────────────────
                    _StepIndicator(currentStep: 2),
                    const SizedBox(height: 24),

                    // ── Photos section ────────────────────────────────────
                    Row(
                      children: [
                        const Text(
                          'Upload Photos',
                          style: TextStyle(
                            color: _textPri,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _yellow.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Min 2 • Max 5',
                            style: TextStyle(
                              color: _yellow,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Upload clear photos of the signage issue (max ${_maxPhotoMB}MB each)',
                      style: const TextStyle(color: _textSec, fontSize: 12),
                    ),
                    const SizedBox(height: 16),

                    // ── Photo grid ────────────────────────────────────────
                    _photos.isEmpty
                        ? _EmptyPhotoSlot(onTap: _showPhotoSource)
                        : _buildPhotoGrid(),

                    const SizedBox(height: 28),

                    // ── Video section ─────────────────────────────────────
                    Row(
                      children: [
                        const Text(
                          'Add Video',
                          style: TextStyle(
                            color: _textPri,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _border,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Optional',
                            style: TextStyle(
                              color: _textSec,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Upload a short video for better understanding (max ${_maxVideoMB}MB)',
                      style: const TextStyle(color: _textSec, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    _video == null
                        ? _VideoPickerSlot(onTap: _pickVideo)
                        : _VideoThumbnail(
                            file: _video!,
                            onTap: () => _openVideoPreview(_video!),
                            onRemove: _removeVideo,
                          ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // ── Bottom CTA ────────────────────────────────────────────────
            _BottomBar(
              photoCount: _photos.length,
              minPhotos: _minPhotos,
              onContinue: _onContinue,
            ),
          ],
        ),
      ),
    );
  }

  // ── Photo grid builder ───────────────────────────────────────────────────

  Widget _buildPhotoGrid() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        ..._photos.asMap().entries.map((e) => _PhotoTile(
          file: e.value,
          onTap: () => _openPhotoPreview(e.value),
          onRemove: () => _removePhoto(e.key),
        )),
        if (_photos.length < _maxPhotos)
          _AddMoreTile(onTap: _showPhotoSource),
      ],
    );
  }
}

// ============================================================================
//  SUPPORTING WIDGETS
// ============================================================================

// ── Step indicator (reused from CreateRequestScreen style) ──────────────────

class _StepIndicator extends StatelessWidget {
  final int currentStep; // 1-based
  const _StepIndicator({required this.currentStep});

  static const Color _yellow = Color(0xFFFFD700);
  static const Color _done   = Color(0xFF1E3A5F);
  static const Color _active = _yellow;
  static const Color _textPri= Colors.white;
  static const Color _textSec= Color(0xFF8899BB);

  @override
  Widget build(BuildContext context) {
    const steps = ['Details', 'Media', 'Location'];
    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          // connector
          final filled = (i ~/ 2) < currentStep - 1;
          return Expanded(
            child: Container(
              height: 2,
              color: filled ? _yellow : _done,
            ),
          );
        }
        final idx = i ~/ 2 + 1;
        final isActive   = idx == currentStep;
        final isComplete = idx < currentStep;
        return Column(
          children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isComplete ? _yellow
                     : isActive   ? _yellow
                     : _done,
                border: isActive
                    ? Border.all(color: _yellow, width: 2)
                    : null,
              ),
              child: Center(
                child: isComplete
                    ? const Icon(Icons.check, color: Colors.black, size: 16)
                    : Text(
                        '$idx',
                        style: TextStyle(
                          color: isActive ? Colors.black : _textSec,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              steps[idx - 1],
              style: TextStyle(
                fontSize: 10,
                color: isActive || isComplete ? _textPri : _textSec,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        );
      }),
    );
  }
}

// ── Empty state for no photos yet ───────────────────────────────────────────

class _EmptyPhotoSlot extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyPhotoSlot({required this.onTap});

  static const Color _yellow = Color(0xFFFFD700);
  static const Color _card   = Color(0xFF111F3A);
  static const Color _border = Color(0xFF1E3A5F);
  static const Color _textSec= Color(0xFF8899BB);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 140,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border, style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: _yellow.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_photo_alternate_rounded,
                  color: _yellow, size: 26),
            ),
            const SizedBox(height: 10),
            const Text('Tap to add photos',
                style: TextStyle(color: Colors.white, fontSize: 14,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text('Camera or Gallery',
                style: TextStyle(color: _textSec, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ── Single photo tile in grid ────────────────────────────────────────────────

class _PhotoTile extends StatelessWidget {
  final File file;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  const _PhotoTile({required this.file, required this.onTap, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final size = (MediaQuery.of(context).size.width - 40 - 24) / 3;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              file,
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 4, right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 22, height: 22,
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── "Add More" tile ──────────────────────────────────────────────────────────

class _AddMoreTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddMoreTile({required this.onTap});

  static const Color _yellow = Color(0xFFFFD700);
  static const Color _card   = Color(0xFF111F3A);
  static const Color _border = Color(0xFF1E3A5F);
  static const Color _textSec= Color(0xFF8899BB);

  @override
  Widget build(BuildContext context) {
    final size = (MediaQuery.of(context).size.width - 40 - 24) / 3;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: _yellow, size: 26),
            const SizedBox(height: 4),
            const Text('Add More',
                style: TextStyle(color: _textSec, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ── Video picker slot (empty) ────────────────────────────────────────────────

class _VideoPickerSlot extends StatelessWidget {
  final VoidCallback onTap;
  const _VideoPickerSlot({required this.onTap});

  static const Color _yellow = Color(0xFFFFD700);
  static const Color _card   = Color(0xFF111F3A);
  static const Color _border = Color(0xFF1E3A5F);
  static const Color _textSec= Color(0xFF8899BB);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 68,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: _yellow.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.videocam_rounded, color: _yellow, size: 22),
            ),
            const SizedBox(width: 14),
            const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Select Video',
                    style: TextStyle(color: Colors.white, fontSize: 14,
                        fontWeight: FontWeight.w500)),
                SizedBox(height: 2),
                Text('Optional · Max 50MB',
                    style: TextStyle(color: _textSec, fontSize: 11)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: _textSec, size: 14),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

// ── Video thumbnail (when picked) ────────────────────────────────────────────

class _VideoThumbnail extends StatelessWidget {
  final File file;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  const _VideoThumbnail({
    required this.file, required this.onTap, required this.onRemove});

  static const Color _yellow = Color(0xFFFFD700);
  static const Color _card   = Color(0xFF111F3A);
  static const Color _border = Color(0xFF1E3A5F);
  static const Color _textSec= Color(0xFF8899BB);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 68,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _yellow.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: _yellow.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.play_circle_fill_rounded,
                  color: _yellow, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.path.split('/').last,
                    style: const TextStyle(color: Colors.white, fontSize: 13,
                        fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  const Text('Tap to preview',
                      style: TextStyle(color: _textSec, fontSize: 11)),
                ],
              ),
            ),
            GestureDetector(
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Icon(Icons.delete_outline_rounded,
                    color: Colors.redAccent, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bottom bar with photo counter + continue ─────────────────────────────────

class _BottomBar extends StatelessWidget {
  final int photoCount;
  final int minPhotos;
  final VoidCallback onContinue;
  const _BottomBar({
    required this.photoCount,
    required this.minPhotos,
    required this.onContinue,
  });

  static const Color _yellow = Color(0xFFFFD700);
  static const Color _card   = Color(0xFF111F3A);
  static const Color _textSec= Color(0xFF8899BB);

  @override
  Widget build(BuildContext context) {
    final ready = photoCount >= minPhotos;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      decoration: BoxDecoration(
        color: _card,
        border: const Border(
          top: BorderSide(color: Color(0xFF1E3A5F)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // photo counter chips
          Row(
            children: [
              _Chip(
                label: '$photoCount photo${photoCount == 1 ? '' : 's'} added',
                icon: Icons.photo_rounded,
                ok: ready,
              ),
              const SizedBox(width: 8),
              _Chip(
                label: 'Min $minPhotos required',
                icon: Icons.info_outline_rounded,
                ok: ready,
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: ready ? onContinue : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _yellow,
                disabledBackgroundColor: _yellow.withOpacity(0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: Text(
                'Continue',
                style: TextStyle(
                  color: ready ? Colors.black : Colors.black45,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool ok;
  const _Chip({required this.label, required this.icon, required this.ok});

  @override
  Widget build(BuildContext context) {
    final color = ok ? const Color(0xFF00C853) : const Color(0xFF8899BB);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }
}

// ============================================================================
//  FULL-SCREEN PHOTO PREVIEW
// ============================================================================

class _FullScreenPhoto extends StatelessWidget {
  final File file;
  const _FullScreenPhoto({required this.file});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.file(file, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

// ============================================================================
//  FULL-SCREEN VIDEO PREVIEW
// ============================================================================

class _FullScreenVideo extends StatefulWidget {
  final File file;
  const _FullScreenVideo({required this.file});

  @override
  State<_FullScreenVideo> createState() => _FullScreenVideoState();
}

class _FullScreenVideoState extends State<_FullScreenVideo> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        setState(() => _initialized = true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _controller.value.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _controller.value.isPlaying
                    ? _controller.pause()
                    : _controller.play();
              });
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: _initialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : const CircularProgressIndicator(color: Color(0xFFFFD700)),
      ),
    );
  }
}