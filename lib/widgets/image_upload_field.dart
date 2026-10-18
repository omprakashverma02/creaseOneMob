import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme.dart';
import 'common.dart';
import 'logo_cleanup.dart';

/// Tap-to-pick image that uploads to `/api/upload` and reports the stored URL.
class ImageUploadField extends StatefulWidget {
  const ImageUploadField({super.key, required this.label, this.url, required this.onChanged, this.folder = 'misc', this.circle = true, this.size = 88, this.logo = false});
  /// Offer background removal (team / tournament / sponsor logos).
  final bool logo;
  final String label;
  final String? url;
  final ValueChanged<String?> onChanged;
  final String folder;
  final bool circle;
  final double size;
  @override
  State<ImageUploadField> createState() => _ImageUploadFieldState();
}

class _ImageUploadFieldState extends State<ImageUploadField> {
  bool _uploading = false;
  File? _local;

  Future<void> _pick() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(c, ImageSource.gallery)),
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'), onTap: () => Navigator.pop(c, ImageSource.camera)),
          if (widget.url != null)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.live),
              title: const Text('Remove image'),
              onTap: () {
                Navigator.pop(c);
                setState(() => _local = null);
                widget.onChanged(null);
              },
            ),
        ]),
      ),
    );
    if (src == null) return;
    final x = await ImagePicker().pickImage(source: src, maxWidth: 1600, imageQuality: 90);
    if (x == null || !mounted) return;
    // Crop (web ImageCropper) — square for avatars / logos.
    var path = x.path;
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: x.path,
        aspectRatio: widget.circle ? const CropAspectRatio(ratioX: 1, ratioY: 1) : null,
        compressFormat: ImageCompressFormat.png,
        maxWidth: 1024,
        maxHeight: 1024,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop ${widget.label.toLowerCase()}',
            toolbarColor: AppColors.surface,
            toolbarWidgetColor: Colors.white,
            backgroundColor: AppColors.bg,
            activeControlsWidgetColor: AppColors.primary,
            lockAspectRatio: widget.circle,
          ),
          IOSUiSettings(title: 'Crop ${widget.label.toLowerCase()}', aspectRatioLockEnabled: widget.circle),
        ],
      );
      if (cropped == null) return;
      path = cropped.path;
    } catch (_) {
      // Cropper unavailable → upload the original.
    }
    if (!mounted) return;
    var file = File(path);
    if (widget.logo) {
      final clean = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Remove logo background?'),
          content: const Text('Makes a plain white / coloured background transparent so the logo sits cleanly on scorecards.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep as is')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove background')),
          ],
        ),
      );
      if (clean == true) {
        try {
          file = await removeLogoBackground(file);
        } catch (_) {}
      }
    }
    if (!mounted) return;
    setState(() {
      _local = file;
      _uploading = true;
    });
    try {
      final url = await context.api.uploadImage(file, folder: widget.folder);
      widget.onChanged(url);
    } catch (e) {
      if (mounted) context.toast('Upload failed: $e', error: true);
      setState(() => _local = null);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    Widget img;
    if (_local != null) {
      img = Image.file(_local!, width: s, height: s, fit: BoxFit.cover);
    } else if (widget.url != null) {
      img = NetImage(widget.url, size: s, circle: false, fit: BoxFit.cover);
    } else {
      img = Icon(Icons.add_a_photo_outlined, color: AppColors.textMid, size: s * 0.32);
    }
    return Column(children: [
      GestureDetector(
        onTap: _uploading ? null : _pick,
        child: Container(
          width: s,
          height: s,
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.circle ? null : BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.5), width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(child: Center(child: img)),
            if (_uploading) Container(color: Colors.black45, child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      Text(widget.label, style: const TextStyle(fontSize: 12, color: AppColors.textMid, fontWeight: FontWeight.w700)),
    ]);
  }
}
