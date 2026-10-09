import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../auslan_scripts/auslan_predict.dart';

class _ServerPrediction {
  const _ServerPrediction({
    required this.label,
    required this.confidence,
    this.hasHand = true,
  });

  final String label;
  final double confidence;
  final bool hasHand;
}

class SignLanguageCameraCard extends StatefulWidget {
  const SignLanguageCameraCard({
    super.key,
    required this.label,
    required this.accent,
    this.onPrediction,
    this.onFinalized,
  });

  final String label;
  final Color accent;
  final Function(String rawLabel, double confidence, String allLetters)?
  onPrediction;
  final Function(String capturedLetters, String? guessedText, String trigger)?
  onFinalized;

  @override
  State<SignLanguageCameraCard> createState() => _SignLanguageCameraCardState();
}

class _SignLanguageCameraCardState extends State<SignLanguageCameraCard> {
  CameraController? _controller;
  bool _isDisposed = false;
  bool _isInitialized = false;
  bool _isPredicting = false;
  String _prediction = '';
  String _statusMessage = 'Connecting to recognition server...';
  double _confidence = 0;
  Timer? _timer;
  CameraImage? _latestFrame;
  String _allLetters = '';
  bool _hasLoggedServerConfigWarning = false;
  bool _hasLoggedConnectionWarning = false;
  bool _hasLoggedFrameFormatWarning = false;
  DateTime? _lastHandDetectedAt;
  bool _isFinalizing = false;

  AuslanPredictor? _predictor;

  @override
  @override
  void initState() {
    super.initState();
    _initCamera();
    unawaited(_initPredictor());
  }

  Future<void> _initPredictor() async {
    _predictor = AuslanPredictor();
    try {
      // The app was creating an AustlanPredictor instance but never actually
      // loading the shipped TensorFlow Lite model. This meant the sign pipeline
      // had no ready inference backend at runtime.
      await _predictor!.loadModel();
      if (mounted) {
        _showStatus('Model ready. Showing hand signs to the camera...');
      }
    } catch (error) {
      debugPrint('Predictor bootstrap failed: $error');
      if (mounted) {
        _showStatus('Model boot failed. Remote server detection will be used if available.');
      }
    }
  }

  void _showStatus(String message) {
    if (!mounted || _statusMessage == message) return;
    setState(() => _statusMessage = message);
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      front,
      ResolutionPreset.medium,
      imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );
    try {
      await controller.initialize();
      if (!mounted || _isDisposed) {
        await controller.dispose();
        return;
      }

      await controller.startImageStream((frame) {
        if (!mounted || _isDisposed) {
          return;
        }
        _latestFrame = frame;
      });

      if (!mounted || _isDisposed) {
        await controller.dispose();
        return;
      }

      _controller = controller;
      setState(() => _isInitialized = true);
      _timer = Timer.periodic(
        const Duration(milliseconds: 350),
        (_) => _sendFrame(),
      );
    } catch (e) {
      debugPrint('Camera Init Error: $e');
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }

  Future<void> _sendFrame() async {
    final controller = _controller;
    if (_isDisposed ||
        _isPredicting ||
        controller == null ||
        !controller.value.isInitialized ||
        _predictor == null ||
        _latestFrame == null) {
      return;
    }
    _isPredicting = true;

    try {
      final serverUrl = dotenv.env['AUSLAN_SERVER_URL']?.trim() ?? '';
      if (serverUrl.isEmpty) {
        _showStatus('Set AUSLAN_SERVER_URL in .env');
        if (!_hasLoggedServerConfigWarning) {
          debugPrint(
            'Set AUSLAN_SERVER_URL in .env (example: http://127.0.0.1:8000/predict_auslan)',
          );
          _hasLoggedServerConfigWarning = true;
        }
        return;
      }
      final candidateUris = _buildCandidateUris(serverUrl);
      if (candidateUris.isEmpty) {
        _showStatus('Invalid recognition server URL');
        debugPrint('Invalid AUSLAN_SERVER_URL: $serverUrl');
        return;
      }

      final frameBytes = await _encodeFrameToPng(_latestFrame!);
      if (frameBytes == null) {
        _showStatus('Camera frame format is not supported');
        if (!_hasLoggedFrameFormatWarning) {
          debugPrint('Unsupported frame format for silent capture.');
          _hasLoggedFrameFormatWarning = true;
        }
        return;
      }
      final serverPrediction = await _predictFromServer(
        candidateUris: candidateUris,
        imageBytes: frameBytes,
      );
      if (serverPrediction == null) {
        _showStatus('Recognition server unavailable. Check Wi-Fi and server.');
        return;
      }

      final now = DateTime.now();
      if (!serverPrediction.hasHand) {
        _showStatus('Show one hand clearly to the camera');
        if (_lastHandDetectedAt != null &&
            now.difference(_lastHandDetectedAt!) >=
                const Duration(seconds: 5)) {
          await _finalizeCapture(trigger: 'no-hand-5s');
          _lastHandDetectedAt = null;
        }
        return;
      }

      _lastHandDetectedAt = now;

      final predictor = _predictor!;
      final prediction = predictor.processRawPrediction(
        rawLabel: serverPrediction.label,
        confidencePercent: serverPrediction.confidence,
      );

      if (!mounted) return;
      setState(() {
        _statusMessage = '';
        _prediction = prediction.rawLabel;
        _confidence = prediction.confidence;
        _allLetters = prediction.allLetters;
      });

      if (prediction.acceptedLetter.isNotEmpty) {
        widget.onPrediction?.call(
          prediction.rawLabel,
          prediction.confidence,
          prediction.allLetters,
        );
      }
    } catch (e) {
      debugPrint('Prediction Error: $e');
    } finally {
      _isPredicting = false;
    }
  }

  Future<void> _finalizeCapture({required String trigger}) async {
    if (_isFinalizing || _predictor == null) {
      return;
    }

    final predictor = _predictor!;
    if (!predictor.hasCapturedLetters) {
      return;
    }

    _isFinalizing = true;
    final capturedLetters = predictor.allLetters;
    String? guessedText;
    try {
      guessedText = await predictor.guessWordPhrase();
      widget.onFinalized?.call(capturedLetters, guessedText, trigger);
    } catch (e) {
      debugPrint('Finalize Error: $e');
      widget.onFinalized?.call(capturedLetters, null, trigger);
    } finally {
      predictor.resetCaptureState();
      if (mounted) {
        setState(() {
          _allLetters = '';
        });
      }
      _isFinalizing = false;
    }
  }

  Future<_ServerPrediction?> _predictFromServer({
    required List<Uri> candidateUris,
    required Uint8List imageBytes,
  }) async {
    for (final uri in candidateUris) {
      try {
        final request = http.MultipartRequest('POST', uri);
        request.files.add(
          http.MultipartFile.fromBytes(
            'image',
            imageBytes,
            filename: 'frame.png',
          ),
        );

        final response = await request.send().timeout(
          const Duration(seconds: 20),
        );
        final body = await response.stream.bytesToString();
        if (response.statusCode != 200) {
          debugPrint(
            'Auslan server failed: status=${response.statusCode}, url=$uri, body=$body',
          );
          continue;
        }

        final decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }

        final label = (decoded['label'] ?? '').toString().trim();
        final confidenceRaw = decoded['confidence'];
        final confidence = switch (confidenceRaw) {
          num() => confidenceRaw.toDouble(),
          String() => double.tryParse(confidenceRaw) ?? 0.0,
          _ => 0.0,
        };

        if (label.isEmpty || label == 'null') {
          return const _ServerPrediction(
            label: '',
            confidence: 0,
            hasHand: false,
          );
        }

        return _ServerPrediction(label: label, confidence: confidence);
      } on TimeoutException catch (e) {
        if (!_hasLoggedConnectionWarning) {
          debugPrint('Auslan server timeout: $e');
          debugPrint('Tried: ${candidateUris.join(', ')}');
          _hasLoggedConnectionWarning = true;
        }
        continue;
      } catch (e) {
        if (!_hasLoggedConnectionWarning) {
          debugPrint('Auslan server request error: $e');
          debugPrint('Tried: ${candidateUris.join(', ')}');
          _hasLoggedConnectionWarning = true;
        }
        continue;
      }
    }

    return null;
  }

  Future<Uint8List?> _encodeFrameToPng(CameraImage frame) async {
    if (frame.planes.isEmpty) {
      return null;
    }

    if (frame.format.group == ImageFormatGroup.jpeg) {
      return frame.planes.first.bytes;
    }

    final Uint8List rgbaBytes;
    if (frame.format.group == ImageFormatGroup.bgra8888) {
      final source = frame.planes.first.bytes;
      rgbaBytes = Uint8List(source.length);
      for (var i = 0; i + 3 < source.length; i += 4) {
        rgbaBytes[i] = source[i + 2];
        rgbaBytes[i + 1] = source[i + 1];
        rgbaBytes[i + 2] = source[i];
        rgbaBytes[i + 3] = source[i + 3];
      }
    } else if (frame.format.group == ImageFormatGroup.yuv420 &&
        frame.planes.length >= 3) {
      rgbaBytes = _yuv420ToRgba(frame);
    } else {
      return null;
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgbaBytes,
      frame.width,
      frame.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return byteData?.buffer.asUint8List();
  }

  Uint8List _yuv420ToRgba(CameraImage frame) {
    final width = frame.width;
    final height = frame.height;
    final yPlane = frame.planes[0];
    final uPlane = frame.planes[1];
    final vPlane = frame.planes[2];
    final rgba = Uint8List(width * height * 4);

    for (var y = 0; y < height; y++) {
      final yRow = y * yPlane.bytesPerRow;
      final uvRow = (y ~/ 2) * uPlane.bytesPerRow;
      for (var x = 0; x < width; x++) {
        final yValue = yPlane.bytes[yRow + x];
        final uvColumn = (x ~/ 2) * uPlane.bytesPerPixel!;
        final uValue = uPlane.bytes[uvRow + uvColumn];
        final vValue = vPlane.bytes[(y ~/ 2) * vPlane.bytesPerRow +
            (x ~/ 2) * vPlane.bytesPerPixel!];

        final yAdjusted = yValue - 16;
        final uAdjusted = uValue - 128;
        final vAdjusted = vValue - 128;
        final red = (1.164 * yAdjusted + 1.596 * vAdjusted)
            .round()
            .clamp(0, 255);
        final green = (1.164 * yAdjusted -
                0.392 * uAdjusted -
                0.813 * vAdjusted)
            .round()
            .clamp(0, 255);
        final blue = (1.164 * yAdjusted + 2.017 * uAdjusted)
            .round()
            .clamp(0, 255);
        final offset = (y * width + x) * 4;

        rgba[offset] = red;
        rgba[offset + 1] = green;
        rgba[offset + 2] = blue;
        rgba[offset + 3] = 255;
      }
    }

    return rgba;
  }

  List<Uri> _buildCandidateUris(String rawServerUrl) {
    final normalized =
        rawServerUrl.startsWith('http://') ||
            rawServerUrl.startsWith('https://')
        ? rawServerUrl
        : 'http://$rawServerUrl';

    Uri? primary;
    try {
      primary = Uri.parse(normalized);
    } catch (_) {
      return const [];
    }

    final uris = <Uri>[primary];
    final host = primary.host;
    final isLoopback = host == '127.0.0.1' || host == 'localhost';

    // Android emulator cannot reach host machine via 127.0.0.1.
    if (isLoopback && defaultTargetPlatform == TargetPlatform.android) {
      uris.add(primary.replace(host: '10.0.2.2'));
    }

    final unique = <String>{};
    final deduped = <Uri>[];
    for (final uri in uris) {
      final key = uri.toString();
      if (unique.add(key)) {
        deduped.add(uri);
      }
    }
    return deduped;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    final controller = _controller;
    _controller = null;
    if (controller?.value.isStreamingImages ?? false) {
      unawaited(controller!.stopImageStream().catchError((_) {}));
    }
    if (controller != null) {
      unawaited(controller.dispose().catchError((_) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: () => _finalizeCapture(trigger: 'double-tap'),
      child: Container(
        color: const Color(0xFF111827),
        child: Stack(
          children: [
            if (_isInitialized && _controller != null)
              Positioned.fill(child: CameraPreview(_controller!))
            else
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF1F2937).withValues(alpha: 0.8),
                        const Color(0xFF111827).withValues(alpha: 0.8),
                        const Color(0xFF000000).withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                ),
              ),

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(height: 2, color: widget.accent),
            ),

            if (!_isInitialized)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.videocam_outlined,
                      size: 68,
                      color: Color(0xFF6B7280),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

            if (_prediction.isNotEmpty)
              Positioned(
                top: 16,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$_prediction ${_confidence.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: _confidence >= 80
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

            if (_statusMessage.isNotEmpty && _isInitialized)
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _statusMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ),

            if (_allLetters.isNotEmpty)
              Positioned(
                bottom: 16,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _allLetters,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
            if (_allLetters.isNotEmpty)
              Positioned(
                bottom: 16,
                right: 16,
                child: ElevatedButton.icon(
                  onPressed: _isFinalizing ? null : () => _finalizeCapture(trigger: 'button'),
                  icon: const Icon(Icons.translate, size: 20),
                  label: const Text('Translate'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
