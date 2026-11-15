import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Shows the current receipt photo (if any) with buttons to add or remove.
class PhotoSection extends StatelessWidget {
  const PhotoSection({
    super.key,
    required this.file,
    required this.onPicked,
    required this.onRemove,
  });

  /// The photo to preview, or null when there is none.
  final File? file;

  /// Called with the temporary path of a newly picked image.
  final ValueChanged<String> onPicked;
  final VoidCallback onRemove;

  Future<void> _pick(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final XFile? picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1600,
    );
    if (picked == null) return;
    onPicked(picked.path);
  }

  @override
  Widget build(BuildContext context) {
    final f = file;
    if (f == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => _pick(context),
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('Add photo'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            f,
            height: 160,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const SizedBox(
              height: 80,
              child: Center(child: Text('Photo not found')),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            TextButton.icon(
              onPressed: () => _pick(context),
              icon: const Icon(Icons.refresh),
              label: const Text('Replace'),
            ),
            TextButton.icon(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove'),
            ),
          ],
        ),
      ],
    );
  }
}
