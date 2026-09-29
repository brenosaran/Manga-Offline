import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/bubble_data.dart';

/// Detecção de balões/caixas de texto **offline no dispositivo** usando o
/// modelo YOLOv8n (`assets/models/text_detector.tflite`) treinado na Fase 5.
///
/// O modelo foi exportado pelo Ultralytics com entrada **NCHW `[1,3,640,640]`**
/// float32 normalizada (0–1) e saída **`[1,5,8400]`** (4 coords + 1 classe),
/// coordenadas no espaço letterbox 640×640. Aqui reproduzimos o mesmo
/// pré-processamento (letterbox cinza 114) e mapeamos de volta para os pixels
/// da página, aplicando NMS e a ordenação de leitura (RTL).
class BubbleDetectionService {
  BubbleDetectionService._();

  static const String _asset = 'assets/models/text_detector.tflite';
  static const int _inputSize = 640;
  static const int _anchors = 8400;
  static const double _confThreshold = 0.25;
  static const double _iouThreshold = 0.45;
  static const double _minBoxPx = 8.0;
  static const double _minAreaFraction = 0.001;

  static Uint8List? _modelBytes;

  /// `tflite_flutter` só traz as bibliotecas nativas para Android/iOS; no
  /// desktop é preciso adicionar o `.dll`/`.so` manualmente, então tratamos
  /// Android/iOS como suportados e os demais como indisponíveis (fallback).
  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<Uint8List> _loadModel() async {
    final cached = _modelBytes;
    if (cached != null) return cached;
    final data = await rootBundle.load(_asset);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    _modelBytes = bytes;
    return bytes;
  }

  /// Detecta os balões de todas as páginas de um capítulo e grava `bubbles.json`
  /// no diretório do capítulo (cache para as próximas leituras).
  ///
  /// Retorna `null` se o dispositivo não suportar o detector ou se algo falhar.
  static Future<BubbleData?> detectAndCache({
    required String folderPath,
    required List<String> pagePaths,
  }) async {
    if (!isSupported || pagePaths.isEmpty) return null;
    try {
      final modelBytes = await _loadModel();
      final pages = await Isolate.run(
        () => _detectPages(modelBytes, pagePaths),
      );
      final root = <String, dynamic>{'version': 1, 'pages': pages};
      await File(p.join(folderPath, 'bubbles.json'))
          .writeAsString(jsonEncode(root));
      return BubbleData.fromJson(root);
    } catch (e) {
      debugPrint('BubbleDetectionService: falha na detecção — $e');
      return null;
    }
  }
}

// --- Funções executadas no isolate (sem dependências de plugins) ---

Map<String, dynamic> _detectPages(Uint8List modelBytes, List<String> pagePaths) {
  final interpreter = Interpreter.fromBuffer(modelBytes);
  try {
    // Buffers reutilizados entre páginas: `run()` copia os bytes para o tensor
    // de entrada e o resultado para o buffer de saída.
    final inputBytes = Uint8List(3 * 640 * 640 * 4);
    final outputBytes = Uint8List(5 * 8400 * 4);
    final inputFloats = inputBytes.buffer.asFloat32List();
    final outputFloats = outputBytes.buffer.asFloat32List();

    final pages = <String, dynamic>{};
    for (final path in pagePaths) {
      final page = _detectOne(
        interpreter,
        inputBytes,
        inputFloats,
        outputBytes,
        outputFloats,
        path,
      );
      if (page != null) pages[p.basename(path)] = page;
    }
    return pages;
  } finally {
    interpreter.close();
  }
}

Map<String, dynamic>? _detectOne(
  Interpreter interpreter,
  Uint8List inputBytes,
  Float32List inputFloats,
  Uint8List outputBytes,
  Float32List outputFloats,
  String path,
) {
  final decoded = img.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) return null;
  final w = decoded.width;
  final h = decoded.height;
  if (w <= 0 || h <= 0) return null;

  // Letterbox (mantém proporção, cinza 114, sem "scale up").
  final ratio = math.min(
    BubbleDetectionService._inputSize / w,
    BubbleDetectionService._inputSize / h,
  );
  final effectiveRatio = ratio > 1.0 ? 1.0 : ratio;
  final nw = (w * effectiveRatio).round().clamp(1, BubbleDetectionService._inputSize);
  final nh = (h * effectiveRatio).round().clamp(1, BubbleDetectionService._inputSize);
  final padX = (BubbleDetectionService._inputSize - nw) ~/ 2;
  final padY = (BubbleDetectionService._inputSize - nh) ~/ 2;

  final resized = img.copyResize(decoded, width: nw, height: nh);
  final canvas = img.Image(
    width: BubbleDetectionService._inputSize,
    height: BubbleDetectionService._inputSize,
    numChannels: 3,
  );
  img.fill(canvas, color: img.ColorRgb8(114, 114, 114));
  img.compositeImage(canvas, resized, dstX: padX, dstY: padY);

  final rgb = canvas.getBytes(order: img.ChannelOrder.rgb); // HWC
  const size = BubbleDetectionService._inputSize;
  const plane = size * size;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final i = (y * size + x) * 3;
      final o = y * size + x;
      inputFloats[o] = rgb[i] / 255.0;
      inputFloats[plane + o] = rgb[i + 1] / 255.0;
      inputFloats[2 * plane + o] = rgb[i + 2] / 255.0;
    }
  }

  interpreter.run(inputBytes, outputBytes);

  // Saída [1,5,8400]: índice = atributo * 8400 + âncora. As coordenadas do
  // modelo saem normalizadas em [0,1] (relativas ao 640×640 de entrada), então
  // voltamos para pixels antes de desfazer o letterbox.
  final boxes = <List<double>>[];
  final scores = <double>[];
  final inputSizeD = BubbleDetectionService._inputSize.toDouble();
  for (var a = 0; a < BubbleDetectionService._anchors; a++) {
    final conf = outputFloats[4 * BubbleDetectionService._anchors + a];
    if (conf < BubbleDetectionService._confThreshold) continue;
    boxes.add([
      outputFloats[a] * inputSizeD,
      outputFloats[BubbleDetectionService._anchors + a] * inputSizeD,
      outputFloats[2 * BubbleDetectionService._anchors + a] * inputSizeD,
      outputFloats[3 * BubbleDetectionService._anchors + a] * inputSizeD,
    ]);
    scores.add(conf);
  }

  final kept = nms(boxes, scores, BubbleDetectionService._iouThreshold);

  final pageArea = (w * h).toDouble();
  final mapped = <List<double>>[];
  for (final b in kept) {
    final x1 = (b[0] - b[2] / 2 - padX) / effectiveRatio;
    final y1 = (b[1] - b[3] / 2 - padY) / effectiveRatio;
    final x2 = (b[0] + b[2] / 2 - padX) / effectiveRatio;
    final y2 = (b[1] + b[3] / 2 - padY) / effectiveRatio;
    final cx1 = x1.clamp(0.0, w.toDouble());
    final cy1 = y1.clamp(0.0, h.toDouble());
    final cx2 = x2.clamp(0.0, w.toDouble());
    final cy2 = y2.clamp(0.0, h.toDouble());
    final bw = cx2 - cx1;
    final bh = cy2 - cy1;
    if (bw < BubbleDetectionService._minBoxPx ||
        bh < BubbleDetectionService._minBoxPx) {
      continue;
    }
    if ((bw * bh) / pageArea < BubbleDetectionService._minAreaFraction) {
      continue;
    }
    mapped.add([cx1, cy1, bw, bh]);
  }

  final ordered = orderRtl(mapped);
  return {
    'w': w,
    'h': h,
    'bubbles': [
      for (final b in ordered)
        {'x': b[0], 'y': b[1], 'w': b[2], 'h': b[3]},
    ],
  };
}

/// Non-Maximum Suppression sobre caixas `[cx, cy, w, h]`.
List<List<double>> nms(
  List<List<double>> boxes,
  List<double> scores,
  double iouThreshold,
) {
  final order = List<int>.generate(boxes.length, (i) => i)
    ..sort((a, b) => scores[b].compareTo(scores[a]));
  final removed = List<bool>.filled(boxes.length, false);
  final keep = <List<double>>[];
  for (final i in order) {
    if (removed[i]) continue;
    keep.add(boxes[i]);
    for (final j in order) {
      if (j == i || removed[j]) continue;
      if (_iou(boxes[i], boxes[j]) > iouThreshold) removed[j] = true;
    }
  }
  return keep;
}

double _iou(List<double> a, List<double> b) {
  final ax1 = a[0] - a[2] / 2, ay1 = a[1] - a[3] / 2;
  final ax2 = a[0] + a[2] / 2, ay2 = a[1] + a[3] / 2;
  final bx1 = b[0] - b[2] / 2, by1 = b[1] - b[3] / 2;
  final bx2 = b[0] + b[2] / 2, by2 = b[1] + b[3] / 2;
  final ix1 = math.max(ax1, bx1), iy1 = math.max(ay1, by1);
  final ix2 = math.min(ax2, bx2), iy2 = math.min(ay2, by2);
  final iw = (ix2 - ix1).clamp(0.0, double.infinity);
  final ih = (iy2 - iy1).clamp(0.0, double.infinity);
  final inter = iw * ih;
  if (inter <= 0) return 0;
  final union = a[2] * a[3] + b[2] * b[3] - inter;
  return union <= 0 ? 0 : inter / union;
}

/// Ordena de cima para baixo e, dentro de cada "linha", da direita para a
/// esquerda (sentido de leitura de mangá). Caixas no formato `[x, y, w, h]`.
List<List<double>> orderRtl(List<List<double>> boxes) {
  if (boxes.isEmpty) return boxes;
  final items = [...boxes]
    ..sort((a, b) {
      if (a[1] != b[1]) return a[1].compareTo(b[1]);
      return b[0].compareTo(a[0]);
    });
  final rows = <List<List<double>>>[];
  for (final b in items) {
    var placed = false;
    for (final row in rows) {
      var rowTop = double.infinity, rowBot = -double.infinity;
      for (final r in row) {
        rowTop = math.min(rowTop, r[1]);
        rowBot = math.max(rowBot, r[1] + r[3]);
      }
      final center = b[1] + b[3] / 2;
      final height = rowBot - rowTop == 0 ? 1.0 : rowBot - rowTop;
      if ((rowTop <= center && center <= rowBot) ||
          (b[1] - rowBot) < 0.4 * height) {
        row.add(b);
        placed = true;
        break;
      }
    }
    if (!placed) rows.add([b]);
  }
  final result = <List<double>>[];
  for (final row in rows) {
    row.sort((a, b) => b[0].compareTo(a[0])); // mais à direita primeiro
    result.addAll(row);
  }
  return result;
}
