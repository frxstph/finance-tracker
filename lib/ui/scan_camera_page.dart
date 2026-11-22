import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/money.dart';
import '../domain/receipt_parser.dart';

/// What the scan camera ended with.
sealed class ScanCameraResult {
  const ScanCameraResult();
}

/// A photo was taken: read it and open Check and save.
class ScanPhoto extends ScanCameraResult {
  const ScanPhoto(this.path);
  final String path;
}

/// "Choose photos" from the gallery instead.
class ScanUseGallery extends ScanCameraResult {
  const ScanUseGallery();
}

/// "Type it instead": the normal add screen.
class ScanTypeIt extends ScanCameraResult {
  const ScanTypeIt();
}

/// The in-app camera could not start: use the phone's camera app.
class ScanUseSystemCamera extends ScanCameraResult {
  const ScanUseSystemCamera();
}

/// In-app receipt camera: a dark viewfinder with green corners that reads
/// the live picture a few times a second, outlines the text it sees, and
/// says when it has found the total ("Total found: ₱500.00"). The shutter
/// takes a full photo, which is read again properly for Check and save.
/// Design: "Scan button concept" canvas, screen 3.
class ScanCameraPage extends StatefulWidget {
  const ScanCameraPage({super.key});

  @override
  State<ScanCameraPage> createState() => _ScanCameraPageState();
}

class _ScanCameraPageState extends State<ScanCameraPage>
    with WidgetsBindingObserver {
  static const Duration _every = Duration(milliseconds: 450);
  static const Color _mint = Color(0xFF5FD39A);

  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  CameraController? _controller;
  CameraDescription? _camera;
  String? _error;
  bool _torch = false;
  bool _busy = false;
  bool _taking = false;
  bool _starting = false;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  // What the live picture shows right now.
  List<_SeenLine> _lines = const <_SeenLine>[];
  Size? _imageSize;
  InputImageRotation _rotation = InputImageRotation.rotation90deg;
  int? _total;
  DateTime? _date;
  final List<int?> _recentTotals = <int?>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCamera();
    _recognizer.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The camera has to be let go when the app leaves the screen.
    if (state == AppLifecycleState.paused) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _start();
    }
  }

  Future<void> _start() async {
    // The permission prompt pauses the app and resumes it; don't start a
    // second camera while the first is still opening.
    if (_starting) return;
    _starting = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found on this phone.');
        return;
      }
      _camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        _camera!,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      setState(() {
        _controller = controller;
        _error = null;
        _torch = false;
      });
      await controller.startImageStream(_onFrame);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.code == 'CameraAccessDenied' ||
              e.code == 'CameraAccessDeniedWithoutPrompt'
          ? 'The app isn’t allowed to use the camera. Allow it in your '
              'phone’s settings, or use the phone’s camera app.'
          : 'The camera couldn’t start (${e.description ?? e.code}).');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'The camera couldn’t start ($e).');
    } finally {
      _starting = false;
    }
  }

  Future<void> _stopCamera() async {
    final c = _controller;
    _controller = null;
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    await c.dispose();
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || _taking) return;
    final now = DateTime.now();
    if (now.difference(_last) < _every) return;
    _busy = true;
    _last = now;
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      final result = await _recognizer.processImage(input);
      if (!mounted) return;
      _show(result, Size(image.width.toDouble(), image.height.toDouble()),
          input.metadata!.rotation);
    } catch (_) {
      // A frame that can't be read is simply skipped.
    } finally {
      _busy = false;
    }
  }

  /// Reads the live frame into lines and rows, guesses the total and date,
  /// and marks the lines that hold them.
  void _show(RecognizedText result, Size imageSize, InputImageRotation rot) {
    final lines = <TextLine>[
      for (final b in result.blocks) ...b.lines,
    ]..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    final rows = <List<TextLine>>[];
    for (final line in lines) {
      final row = rows.isEmpty ? null : rows.last;
      if (row != null &&
          (line.boundingBox.center.dy - row.first.boundingBox.center.dy)
                  .abs() <
              row.first.boundingBox.height * 0.6) {
        row.add(line);
      } else {
        rows.add(<TextLine>[line]);
      }
    }
    final text = <String>[
      for (final row in rows)
        (row..sort((a, b) =>
                a.boundingBox.left.compareTo(b.boundingBox.left)))
            .map((l) => l.text)
            .join('  '),
    ];
    final guess = parseReceipt(text);
    final total = labelledTotal(text) ?? guess.amount;
    final date = guess.date;

    _recentTotals.add(total);
    if (_recentTotals.length > 3) _recentTotals.removeAt(0);

    final seen = <_SeenLine>[
      for (final l in lines)
        _SeenLine(
          l.boundingBox,
          total != null && amountsIn(l.text).contains(total)
              ? _Mark.total
              : date != null && findDate(<String>[l.text], DateTime.now()) == date
                  ? _Mark.date
                  : _Mark.none,
        ),
    ];
    setState(() {
      _lines = seen;
      _imageSize = imageSize;
      _rotation = rot;
      _total = total;
      _date = date;
    });
  }

  /// The same total on the last few frames: the picture is steady.
  bool get _steady =>
      _total != null &&
      _recentTotals.length >= 2 &&
      _recentTotals.every((t) => t == _total);

  InputImage? _toInputImage(CameraImage image) {
    final camera = _camera;
    final controller = _controller;
    if (camera == null || controller == null) return null;
    final rotation = InputImageRotationValue.fromRawValue(
        (camera.sensorOrientation + 360) % 360);
    if (rotation == null) return null;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
    final Uint8List bytes;
    var resolved = format;
    if (image.planes.length == 1) {
      bytes = image.planes.first.bytes;
    } else if (image.planes.length == 3 &&
        (format == InputImageFormat.yuv_420_888 ||
            format == InputImageFormat.yv12)) {
      bytes = _toNv21(image);
      resolved = InputImageFormat.nv21;
    } else {
      final all = WriteBuffer();
      for (final p in image.planes) {
        all.putUint8List(p.bytes);
      }
      bytes = all.done().buffer.asUint8List();
    }
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: resolved,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  Uint8List _toNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final ySize = width * height;
    final out = Uint8List(ySize + ySize ~/ 2);
    final y = image.planes[0];
    var dest = 0;
    for (var row = 0; row < height; row++) {
      out.setRange(dest, dest + width, y.bytes, row * y.bytesPerRow);
      dest += width;
    }
    final u = image.planes[1];
    final v = image.planes[2];
    final uStride = u.bytesPerPixel ?? 1;
    final vStride = v.bytesPerPixel ?? 1;
    var i = ySize;
    for (var row = 0; row < height ~/ 2; row++) {
      for (var col = 0; col < width ~/ 2; col++) {
        out[i++] = v.bytes[row * v.bytesPerRow + col * vStride];
        out[i++] = u.bytes[row * u.bytesPerRow + col * uStride];
      }
    }
    return out;
  }

  Future<void> _toggleTorch() async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      setState(() => _torch = !_torch);
    } catch (_) {}
  }

  Future<void> _shoot() async {
    final c = _controller;
    if (c == null || _taking) return;
    setState(() => _taking = true);
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
      final file = await c.takePicture();
      if (_torch) await c.setFlashMode(FlashMode.off);
      if (!mounted) return;
      Navigator.of(context).pop(ScanPhoto(file.path));
    } catch (e) {
      if (!mounted) return;
      setState(() => _taking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn’t take the photo: $e')),
      );
      try {
        await c.startImageStream(_onFrame);
      } catch (_) {}
    }
  }

  String get _status {
    final t = _total;
    if (t == null) {
      return _lines.isEmpty ? 'Looking for a receipt…' : 'Looking for the total…';
    }
    final amount = formatPeso(t);
    return _steady
        ? 'Total found: $amount · hold still'
        : 'Total found: $amount';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF101512),
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (controller != null && controller.value.isInitialized)
              _Preview(
                controller: controller,
                lines: _lines,
                imageSize: _imageSize,
                rotation: _rotation,
              ),
            if (_error != null) _ErrorView(message: _error!),
            const IgnorePointer(child: CustomPaint(painter: _CornersPainter())),
            SafeArea(
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: <Widget>[
                        IconButton(
                          tooltip: 'Close',
                          color: Colors.white,
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const Expanded(
                          child: Text(
                            'Scan a receipt',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: _torch ? 'Turn off the light' : 'Turn on the light',
                          color: Colors.white,
                          icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
                          onPressed: controller == null ? null : _toggleTorch,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (_error == null) ...<Widget>[
                    Semantics(
                      liveRegion: true,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _total != null
                              ? _mint.withAlpha(56)
                              : Colors.black.withAlpha(110),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _status,
                          style: TextStyle(
                            color: _total != null
                                ? const Color(0xFFA9F0CB)
                                : Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _date != null
                          ? 'Date found too. Tap the button to scan.'
                          : 'Fit the whole receipt inside the corners.',
                      style: const TextStyle(
                          color: Color(0xFFC7CFCA), fontSize: 14),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        _SideButton(
                          icon: Icons.photo_library_outlined,
                          label: 'Choose photos instead',
                          onTap: () => Navigator.of(context)
                              .pop(const ScanUseGallery()),
                        ),
                        if (_error == null)
                          _Shutter(
                            ready: _steady,
                            busy: _taking,
                            onTap: controller == null ? null : _shoot,
                          )
                        else
                          FilledButton(
                            onPressed: () => Navigator.of(context)
                                .pop(const ScanUseSystemCamera()),
                            child: const Text('Use the phone’s camera'),
                          ),
                        _SideButton(
                          icon: Icons.edit_outlined,
                          label: 'Type it instead',
                          onTap: () =>
                              Navigator.of(context).pop(const ScanTypeIt()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Mark { none, total, date }

class _SeenLine {
  const _SeenLine(this.box, this.mark);
  final Rect box;
  final _Mark mark;
}

/// The camera picture filling the screen, with the text outlines drawn in
/// the same space so they sit on the words.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.controller,
    required this.lines,
    required this.imageSize,
    required this.rotation,
  });

  final CameraController controller;
  final List<_SeenLine> lines;
  final Size? imageSize;
  final InputImageRotation rotation;

  @override
  Widget build(BuildContext context) {
    final preview = controller.value.previewSize;
    if (preview == null) return CameraPreview(controller);
    // previewSize is landscape; on a portrait screen it's turned.
    final portrait = Size(preview.height, preview.width);
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: portrait.width,
          height: portrait.height,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              CameraPreview(controller),
              if (imageSize != null)
                CustomPaint(
                  painter: _TextBoxesPainter(
                    lines: lines,
                    imageSize: imageSize!,
                    rotation: rotation,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Faint boxes round the text it sees; the total in green, the date in
/// light green.
class _TextBoxesPainter extends CustomPainter {
  _TextBoxesPainter({
    required this.lines,
    required this.imageSize,
    required this.rotation,
  });

  final List<_SeenLine> lines;
  final Size imageSize;
  final InputImageRotation rotation;

  double _x(double x, Size canvas) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        return x * canvas.width / imageSize.height;
      case InputImageRotation.rotation270deg:
        return canvas.width - x * canvas.width / imageSize.height;
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        return x * canvas.width / imageSize.width;
    }
  }

  double _y(double y, Size canvas) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        return y * canvas.height / imageSize.width;
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        return y * canvas.height / imageSize.height;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withAlpha(90);
    final total = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFF5FD39A);
    final totalFill = Paint()..color = const Color(0xFF5FD39A).withAlpha(40);
    final date = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFA9F0CB);
    for (final l in lines) {
      final a = _x(l.box.left, size);
      final b = _x(l.box.right, size);
      final rect = Rect.fromLTRB(
        a < b ? a : b,
        _y(l.box.top, size),
        a < b ? b : a,
        _y(l.box.bottom, size),
      ).inflate(4);
      final r = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      switch (l.mark) {
        case _Mark.total:
          canvas.drawRRect(r, totalFill);
          canvas.drawRRect(r, total);
        case _Mark.date:
          canvas.drawRRect(r, date);
        case _Mark.none:
          canvas.drawRRect(r, faint);
      }
    }
  }

  @override
  bool shouldRepaint(_TextBoxesPainter old) =>
      old.lines != lines || old.imageSize != imageSize;
}

/// Green corners marking where the receipt should go.
class _CornersPainter extends CustomPainter {
  const _CornersPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.78;
    final h = size.height * 0.56;
    final left = (size.width - w) / 2;
    final top = size.height * 0.14;
    final rect = Rect.fromLTWH(left, top, w, h);
    const len = 36.0;
    final p = Paint()
      ..color = const Color(0xFF5FD39A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(rect.left, rect.top + len)
      ..lineTo(rect.left, rect.top)
      ..lineTo(rect.left + len, rect.top)
      ..moveTo(rect.right - len, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right, rect.top + len)
      ..moveTo(rect.right, rect.bottom - len)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.right - len, rect.bottom)
      ..moveTo(rect.left + len, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left, rect.bottom - len);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_CornersPainter oldDelegate) => false;
}

class _Shutter extends StatelessWidget {
  const _Shutter({required this.ready, required this.busy, this.onTap});

  final bool ready;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Take the photo',
      child: GestureDetector(
        onTap: busy ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 5),
            color: ready ? const Color(0xFF5FD39A) : const Color(0xFF2E8B5E),
            boxShadow: ready
                ? const <BoxShadow>[
                    BoxShadow(color: Color(0x885FD39A), blurRadius: 18),
                  ]
                : const <BoxShadow>[],
          ),
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(22),
                  child: CircularProgressIndicator(
                      strokeWidth: 3, color: Colors.white),
                )
              : null,
        ),
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: const Color(0xFF1E2722),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF4B5A51)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(icon, color: Colors.white, semanticLabel: label),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.no_photography_outlined,
                color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
