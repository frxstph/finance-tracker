import 'dart:io';

import 'package:flutter/material.dart';

/// Opens [file] full screen with pinch to zoom.
Future<void> showPhotoViewer(BuildContext context, File file, String title) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(title),
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Image.file(
              file,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Text(
                'Photo not found',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
