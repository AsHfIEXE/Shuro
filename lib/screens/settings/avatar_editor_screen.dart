import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// Profile photo editor: pick from the device, then pan/zoom (pinch, via
/// InteractiveViewer) and rotate it within a circular crop guide before
/// saving. The saved image is exactly what's visible inside the circle,
/// captured with RepaintBoundary — no cropping library needed, just
/// Flutter's own widgets.
class AvatarEditorScreen extends StatefulWidget {
  const AvatarEditorScreen({super.key});

  @override
  State<AvatarEditorScreen> createState() => _AvatarEditorScreenState();
}

class _AvatarEditorScreenState extends State<AvatarEditorScreen> {
  static const double _previewSize = 280;

  Uint8List? _imageBytes;
  double _rotationDegrees = 0;
  bool _saving = false;
  final TransformationController _transformationController = TransformationController();
  final GlobalKey _repaintKey = GlobalKey();

  Future<void> _pickImage() async {
    final bytes = await context.read<AppState>().pickImageBytes();
    if (bytes == null || !mounted) return;
    setState(() {
      _imageBytes = bytes;
      _rotationDegrees = 0;
      _transformationController.value = Matrix4.identity();
    });
  }

  void _rotateBy(double degrees) {
    setState(() => _rotationDegrees = (_rotationDegrees + degrees) % 360);
  }

  Future<void> _save() async {
    final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    setState(() => _saving = true);
    try {
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null || !mounted) return;
      context.read<AppState>().updateUserAvatar(byteData.buffer.asUint8List());
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final hasImage = _imageBytes != null;

    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(
        backgroundColor: kSurfaceColor,
        elevation: 0,
        title: Text('Profile photo', style: headingFont(color: kTextColor, fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          if (hasImage)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('Save', style: GoogleFonts.getFont(currentFontFamily, color: kBrandColor, fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          if (appState.userAvatarBytes != null)
            TextButton(
              onPressed: () {
                context.read<AppState>().updateUserAvatar(null);
                Navigator.of(context).pop();
              },
              child: Text('Remove', style: GoogleFonts.getFont(currentFontFamily, color: Colors.redAccent, fontSize: 14)),
            ),
        ],
      ),
      body: Center(
        child: hasImage ? _buildEditor() : _buildEmptyState(appState),
      ),
    );
  }

  Widget _buildEmptyState(AppState appState) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _previewSize,
          height: _previewSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kCardColor,
            image: appState.userAvatarBytes != null ? DecorationImage(image: MemoryImage(appState.userAvatarBytes!), fit: BoxFit.cover) : null,
          ),
          child: appState.userAvatarBytes == null ? const Icon(Icons.person_rounded, color: Colors.white24, size: 96) : null,
        ),
        const SizedBox(height: 28),
        ElevatedButton.icon(
          onPressed: _pickImage,
          style: ElevatedButton.styleFrom(backgroundColor: kBrandColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
          icon: const Icon(Icons.photo_library_rounded, size: 18),
          label: Text('Choose photo', style: GoogleFonts.getFont(currentFontFamily, fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _buildEditor() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _previewSize,
          height: _previewSize,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kBrandColor, width: 2)),
          child: RepaintBoundary(
            key: _repaintKey,
            child: ClipOval(
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.5,
                maxScale: 4,
                child: Transform.rotate(
                  angle: _rotationDegrees * math.pi / 180,
                  child: Image.memory(_imageBytes!, width: _previewSize, height: _previewSize, fit: BoxFit.cover),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('Pinch to zoom · drag to reposition', style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 12)),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(onPressed: () => _rotateBy(-90), icon: const Icon(Icons.rotate_left_rounded, color: Colors.white70)),
            SizedBox(
              width: 180,
              child: Slider(
                value: _rotationDegrees,
                min: 0,
                max: 360,
                activeColor: kBrandColor,
                inactiveColor: kDividerColor,
                onChanged: (v) => setState(() => _rotationDegrees = v),
              ),
            ),
            IconButton(onPressed: () => _rotateBy(90), icon: const Icon(Icons.rotate_right_rounded, color: Colors.white70)),
          ],
        ),
        TextButton(
          onPressed: _pickImage,
          child: Text('Choose a different photo', style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13)),
        ),
      ],
    );
  }
}
