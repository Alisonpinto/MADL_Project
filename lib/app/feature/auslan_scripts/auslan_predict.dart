import 'dart:typed_data';
import 'dart:math' as math;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class AuslanPrediction {
  const AuslanPrediction({
    required this.rawLabel,
    required this.confidence,
    required this.acceptedLetter,
    required this.allLetters,
  });

  final String rawLabel;
  final double confidence;
  final String acceptedLetter;
  final String allLetters;
}

class AuslanPredictor {
  late Interpreter _interpreter;
  late int _inputLength;
  late int _outputLength;
  bool _modelLoaded = false;

  final List<String> labels = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
  ];

  final Duration cooldown = const Duration(seconds: 3);
  final Set<String> lowThresholdLetters = const {
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'V',
  };

  DateTime? _lastAcceptedAt;
  String allLetters = '';

  AuslanPredictor();

  int get inputLength => _inputLength;
  bool get isModelLoaded => _modelLoaded;
  bool get hasCapturedLetters => allLetters.isNotEmpty;

  double thresholdForLabel(String label) {
    return lowThresholdLetters.contains(label) ? 75.0 : 80.0;
  }

  void resetCaptureState() {
    _lastAcceptedAt = null;
    allLetters = '';
  }

  String _readOpenAiKey() {
    try {
      return dotenv.env['OPENAI_API_KEY'] ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> loadModel() async {
    if (_modelLoaded) {
      return;
    }

    // The runtime was creating the predictor but never actually loading the
    // embedded TensorFlow Lite model, so the detector never had a working
    // inference backend until a remote server happened to be available.
    _interpreter = await Interpreter.fromAsset(
      'assets/auslan_detection/model/auslan.tflite',
    );
    _inputLength = _tensorFeatureLength(_interpreter.getInputTensor(0));
    _outputLength = _tensorFeatureLength(_interpreter.getOutputTensor(0));
    _modelLoaded = true;
  }

  int _tensorFeatureLength(Tensor tensor) {
    final shape = tensor.shape;
    if (shape.isEmpty) return 0;
    if (shape.length == 1) return shape.first;

    final safeShape = shape.map((dim) => dim <= 0 ? 1 : dim).toList();
    final total = safeShape.fold<int>(1, (product, dim) => product * dim);
    final batch = safeShape.first;
    return total ~/ batch;
  }

  List<double> _asProbabilities(List<double> values) {
    if (values.isEmpty) return values;
    final inRange = values.every((value) => value >= 0.0 && value <= 1.0);
    final sum = values.fold<double>(0.0, (total, value) => total + value);
    if (inRange && (sum - 1.0).abs() < 0.05) {
      return values;
    }

    final maxValue = values.reduce(math.max);
    final expValues = values
        .map((value) => math.exp(value - maxValue))
        .toList();
    final expSum = expValues.fold<double>(0.0, (total, value) => total + value);
    if (expSum == 0) {
      return List<double>.filled(values.length, 0.0);
    }
    return expValues.map((value) => value / expSum).toList();
  }

  AuslanPrediction predictAuslan(List<double> features) {
    if (!_modelLoaded || _inputLength <= 0 || _outputLength <= 0) {
      return AuslanPrediction(
        rawLabel: '',
        confidence: 0,
        acceptedLetter: '',
        allLetters: allLetters,
      );
    }

    final inputList = Float32List(_inputLength);
    for (var i = 0; i < _inputLength; i++) {
      inputList[i] = i < features.length ? features[i] : 0.0;
    }

    final outputList = Float32List(_outputLength);
    _interpreter.run(inputList.buffer, outputList.buffer);

    final classCount = math.min(labels.length, outputList.length);
    if (classCount == 0) {
      return AuslanPrediction(
        rawLabel: '',
        confidence: 0,
        acceptedLetter: '',
        allLetters: allLetters,
      );
    }

    final rawValues = outputList
        .take(classCount)
        .map((value) => value.toDouble())
        .toList();
    final probs = _asProbabilities(rawValues);

    var maxIndex = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[maxIndex]) {
        maxIndex = i;
      }
    }
    final confidence = probs[maxIndex];

    final rawLabel = labels[maxIndex];
    final confidencePercent = (confidence * 100).clamp(0.0, 100.0);
    return processRawPrediction(
      rawLabel: rawLabel,
      confidencePercent: confidencePercent,
    );
  }

  AuslanPrediction processRawPrediction({
    required String rawLabel,
    required double confidencePercent,
  }) {
    if (rawLabel.isEmpty) {
      return AuslanPrediction(
        rawLabel: '',
        confidence: confidencePercent,
        acceptedLetter: '',
        allLetters: allLetters,
      );
    }

    var acceptedLetter = '';
    final now = DateTime.now();
    final confidenceThresholdPercent = thresholdForLabel(rawLabel);
    if (confidencePercent >= confidenceThresholdPercent) {
      final cooldownElapsed =
          _lastAcceptedAt == null || now.difference(_lastAcceptedAt!) >= cooldown;
      if (cooldownElapsed) {
        acceptedLetter = rawLabel;
        _lastAcceptedAt = now;
        allLetters += acceptedLetter;
      }
    }

    return AuslanPrediction(
      rawLabel: rawLabel,
      confidence: confidencePercent,
      acceptedLetter: acceptedLetter,
      allLetters: allLetters,
    );
  }

  Future<String?> guessWordPhrase() async {
    if (allLetters.isEmpty) return null;
    final openAiKey = _readOpenAiKey();
    if (openAiKey.isEmpty) {
      debugPrint('OPENAI_API_KEY is not configured.');
      return null;
    }

    final prompt =
        """
    You normalize OCR text.
    Rules:
      1. Split merged English words.
      2. Fix simple OCR mistakes.
      3. Return uppercase words only.
      4. Do not add explanations.
      5. Interpret noisy or merged OCR text.
      6. if it's a sentence, try to make it make sense as much as possible
      7. check the sentence before giving the answer to see if it makes sense
      if it doesnt, make it make sense with the given letters
      8. also include slang stuff too
      9. humor would be nice too lol without icon
      
    Text: '$allLetters'
    """;

    final url = Uri.parse("https://api.openai.com/v1/chat/completions");

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $openAiKey',
      },
      body: jsonEncode({
        "model": "gpt-4o-mini",
        "messages": [
          {"role": "user", "content": prompt},
        ],
        "temperature": 0.7,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      String guess = data['choices'][0]['message']['content'].trim();
      return guess;
    } else {
      debugPrint('OpenAI request failed: ${response.statusCode}');
      return null;
    }
  }
}
