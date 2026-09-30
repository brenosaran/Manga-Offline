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

/// Detecção de balões de fala e caixas de narração **offline no dispositivo**
/// usando o modelo YOLO11s (`assets/models/balloon_detector.tflite`) treinado
/// com One Piece (9.915 páginas) para 3 classes.
///
/// O modelo foi exportado pelo Ultralytics com entrada **NCHW `[1,3,S,S]`**
/// float32 normalizada (0–1) e saída **`[1,4+C,A]`** (4 coords + `C` classes),
/// onde `S` = [_inputSize], `A` = [_anchors] e as classes são
/// `0 = balão de fala`, `1 = narração` e `2 = texto`. As coordenadas saem
/// normalizadas em [0,1] (relativas ao quadro de entrada), no formato
/// centro + largura/altura (`cx, cy, w, h`).
///
/// Aqui reproduzimos o mesmo pré-processamento (letterbox cinza 114),
/// aplicamos NMS por grupo e mantemos apenas balões/narrações que **contêm
/// texto** (um balão sem texto detectado não é exibido), devolvendo as caixas
/// mapeadas para os pixels da página e ordenadas no sentido de leitura (RTL).
class BubbleDetectionService {
  BubbleDetectionService._();

  static const String _asset = 'assets/models/balloon_detector.tflite';
  static const int _inputSize = 768;
  static final int _anchors = _anchorsFor(_inputSize);

  /// Classes do modelo: 0 = balão de fala, 1 = narração, 2 = texto.
  static const int _classCount = 3;
  static const int _numChannels = 4 + _classCount;
  static const double _confThreshold = 0.25;

  /// Limiar mais baixo para o texto: ele só serve para confirmar que um balão
  /// tem conteúdo, então preferimos pecar por excesso a descartar balões.
  static const double _textConfThreshold = 0.15;
  static const double _iouThreshold = 0.45;
  static const double _minBoxPx = 8.0;
  static const double _minAreaFraction = 0.001;

  /// Número de âncoras da cabeça do YOLO (P3/P4/P5 = strides 8/16/32).
  static int _anchorsFor(int size) {
    var total = 0;
    for (final stride in const [8, 16, 32]) {
      final k = size ~/ stride;
      total += k * k;
    }
    return total;
  }

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
    debugPrint('[BUBBLE] modelo carregado: ${bytes.length} bytes');
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
      debugPrint('[BUBBLE] iniciando detecção de ${pagePaths.length} páginas');
      final modelBytes = await _loadModel();
      final pages = await Isolate.run(
        () => _detectPages(modelBytes, pagePaths),
      );
      debugPrint('[BUBBLE] detecção concluída: ${pages.length} páginas');
      final root = <String, dynamic>{
        'version': BubbleData.currentVersion,
        'pages': pages,
      };
      await File(p.join(folderPath, 'bubbles.json'))
          .writeAsString(jsonEncode(root));
      return BubbleData.fromJson(root);
    } catch (e, s) {
      debugPrint('[BUBBLE] FALHA na detecção — $e\n$s');
      return null;
    }
  }
}

// --- Funções executadas no isolate (sem dependências de plugins) ---

Map<String, dynamic> _detectPages(Uint8List modelBytes, List<String> pagePaths) {
  final interpreter = Interpreter.fromBuffer(modelBytes);
  debugPrint('[BUBBLE] interpretador OK: in=${interpreter.getInputTensor(0).shape} '
      'out=${interpreter.getOutputTensor(0).shape}');
  try {
    // Buffers reutilizados entre páginas: `run()` copia os bytes para o tensor
    // de entrada e o resultado para o buffer de saída.
    final inputBytes = Uint8List(
        3 * BubbleDetectionService._inputSize * BubbleDetectionService._inputSize * 4);
    final outputBytes = Uint8List(
        BubbleDetectionService._numChannels * BubbleDetectionService._anchors * 4);
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
  var decoded = img.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) return null;
  // O pacote `image` 4.10.1 decodifica PNG em tons de cinza com os canais
  // verde/azul zerados (`setRgb(cinza, 0, 0)`), o que faz o modelo receber uma
  // imagem "vermelha" e detectar **zero** balões. Normalizamos para 3 canais
  // (R=G=B=cinza) antes do letterbox. Ver image/lib/src/formats/png_decoder.dart.
  if (decoded.numChannels != 3) {
    decoded = decoded.convert(numChannels: 3);
  }
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

  // Saída [1,4+C,A] (C = 3 classes, A = _anchors = 12096 no input 768):
  // índice = atributo * A + âncora. As 4 primeiras linhas são as coordenadas
  // (cx, cy, w, h) normalizadas em [0,1] (relativas ao quadro de entrada) e as
  // seguintes são as pontuações das classes (balão, narração, texto).
  final anchors = BubbleDetectionService._anchors;
  final inputSizeD = BubbleDetectionService._inputSize.toDouble();
  final boxes = <List<double>>[];
  final scores = <double>[];
  final texts = <List<double>>[];
  final textScores = <double>[];
  for (var a = 0; a < anchors; a++) {
    final cx = outputFloats[a] * inputSizeD;
    final cy = outputFloats[anchors + a] * inputSizeD;
    final bw = outputFloats[2 * anchors + a] * inputSizeD;
    final bh = outputFloats[3 * anchors + a] * inputSizeD;
    final balloon = outputFloats[4 * anchors + a];
    final narration = outputFloats[5 * anchors + a];
    final text = outputFloats[6 * anchors + a];
    // Balão e narração são mutuamente exclusivos: fica a maior pontuação.
    final bubbleConf = balloon > narration ? balloon : narration;
    if (bubbleConf >= BubbleDetectionService._confThreshold) {
      boxes.add([cx, cy, bw, bh]);
      scores.add(bubbleConf);
    }
    if (text >= BubbleDetectionService._textConfThreshold) {
      texts.add([cx, cy, bw, bh]);
      textScores.add(text);
    }
  }

  final kept = nms(boxes, scores, BubbleDetectionService._iouThreshold);
  final keptTexts = nms(texts, textScores, BubbleDetectionService._iouThreshold);

  final pageArea = (w * h).toDouble();
  List<List<double>> buildMapped({required bool requireText}) {
    final out = <List<double>>[];
    for (final b in kept) {
      // "Sem texto, não é balão": descarta caixas sem nenhum texto dentro.
      if (requireText && !_containsText(b, keptTexts)) continue;
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
      out.add([cx1, cy1, bw, bh]);
    }
    return out;
  }

  var mapped = buildMapped(requireText: true);
  // Rede de segurança: se o filtro derrubou TODAS as caixas (ex.: nenhum texto
  // reconhecido nesta página), mantém as caixas brutas em vez de devolver a
  // página sem balões nenhum.
  if (mapped.isEmpty && kept.isNotEmpty) {
    mapped = buildMapped(requireText: false);
  }

  debugPrint('[BUBBLE] $path cand=${boxes.length} texto=${texts.length} '
      'nms=${kept.length} nmsTexto=${keptTexts.length} mapped=${mapped.length}');
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

/// `true` se o centro de algum texto em [texts] cair dentro da caixa [box].
/// Caixas no formato `[cx, cy, w, h]` (centro + tamanho).
bool _containsText(List<double> box, List<List<double>> texts) {
  final x1 = box[0] - box[2] / 2, y1 = box[1] - box[3] / 2;
  final x2 = box[0] + box[2] / 2, y2 = box[1] + box[3] / 2;
  for (final t in texts) {
    if (t[0] >= x1 && t[0] <= x2 && t[1] >= y1 && t[1] <= y2) return true;
  }
  return false;
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

/// Ordem de leitura de mangá (RTL) por **corte XY recursivo** (recursive XY-cut),
/// o método usado por Kovanen & Aizawa ([panel-order-estimator], Manga109) e
/// pelo panelforge. É mais robusto que agrupar por "faixas" porque:
/// 1. corta a página primeiro em **linhas** (maior lacuna horizontal) e depois em
///    **colunas** (lacuna vertical), recursivamente;
/// 2. dentro de uma faixa, as colunas são visitadas da **direita para a
///    esquerda**;
/// 3. sem lacuna limpa, tolera sobreposições crescentes e, no limite, ordena
///    pelo centro (de cima para baixo e da direita para a esquerda).
///
/// Caixas no formato `[x, y, w, h]`.
List<List<double>> orderRtl(List<List<double>> boxes) {
  if (boxes.isEmpty) return boxes;
  final order = _xyCut(boxes, List<int>.generate(boxes.length, (i) => i));
  return [for (final i in order) boxes[i]];
}

List<int> _xyCut(List<List<double>> boxes, List<int> idx) {
  if (idx.length <= 1) return List<int>.of(idx);

  final spanH = _maxOf(idx, (i) => boxes[i][1] + boxes[i][3]) -
      _minOf(idx, (i) => boxes[i][1]);
  final spanV = _maxOf(idx, (i) => boxes[i][0] + boxes[i][2]) -
      _minOf(idx, (i) => boxes[i][0]);

  var cuts = const <double>[];
  var axis = 'h';
  // Tolerâncias crescentes para sobreposições (balões/quadros encostados).
  outer:
  for (final tolFrac in const [0.0, 0.02, 0.05, 0.1]) {
    for (final ax in const ['h', 'v']) {
      final span = ax == 'h' ? spanH : spanV;
      final intervals = <List<double>>[
        for (final i in idx)
          ax == 'h'
              ? [boxes[i][1], boxes[i][1] + boxes[i][3]]
              : [boxes[i][0], boxes[i][0] + boxes[i][2]],
      ];
      final g = _gaps(intervals, tolFrac * span);
      if (g.isNotEmpty) {
        cuts = g;
        axis = ax;
        break outer;
      }
    }
  }

  if (cuts.isNotEmpty) {
    final groups = List<List<int>>.generate(cuts.length + 1, (_) => <int>[]);
    for (final i in idx) {
      final center = axis == 'h'
          ? boxes[i][1] + boxes[i][3] / 2
          : boxes[i][0] + boxes[i][2] / 2;
      groups[_searchSorted(cuts, center)].add(i);
    }
    var nonEmpty = [for (final g in groups) if (g.isNotEmpty) g];
    // Um corte que não separou nada recursaria para sempre: ignora.
    if (nonEmpty.length > 1) {
      // Colunas (corte vertical) em RTL: a da direita primeiro.
      if (axis == 'v') nonEmpty = nonEmpty.reversed.toList();
      final out = <int>[];
      for (final g in nonEmpty) {
        out.addAll(_xyCut(boxes, g));
      }
      return out;
    }
  }

  // Sem corte limpo: ordena pelo centro (topo→base; direita→esquerda).
  return List<int>.of(idx)
    ..sort((a, b) {
      final cy = (boxes[a][1] + boxes[a][3] / 2)
          .compareTo(boxes[b][1] + boxes[b][3] / 2);
      if (cy != 0) return cy;
      return (boxes[b][0] + boxes[b][2] / 2)
          .compareTo(boxes[a][0] + boxes[a][2] / 2);
    });
}

/// Posições de corte no meio das lacunas entre intervalos mesclados.
/// Intervalos que se sobrepõem por mais de [tol] são mesclados.
List<double> _gaps(List<List<double>> intervals, double tol) {
  if (intervals.isEmpty) return const [];
  final sorted = List<List<double>>.of(intervals)
    ..sort((a, b) => a[0].compareTo(b[0]));
  final merged = <List<double>>[
    [sorted[0][0], sorted[0][1]],
  ];
  for (var k = 1; k < sorted.length; k++) {
    final a = sorted[k][0];
    final b = sorted[k][1];
    if (a <= merged.last[1] - tol) {
      if (b > merged.last[1]) merged.last[1] = b;
    } else {
      merged.add([a, b > merged.last[1] ? b : merged.last[1]]);
    }
  }
  return [
    for (var i = 0; i < merged.length - 1; i++)
      (merged[i][1] + merged[i + 1][0]) / 2,
  ];
}

/// Índice de inserção de [value] em [cuts] (mantém a ordem; `searchsorted`).
int _searchSorted(List<double> cuts, double value) {
  var lo = 0, hi = cuts.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (cuts[mid] < value) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

double _minOf(List<int> idx, double Function(int) f) {
  var m = f(idx.first);
  for (final i in idx) {
    final v = f(i);
    if (v < m) m = v;
  }
  return m;
}

double _maxOf(List<int> idx, double Function(int) f) {
  var m = f(idx.first);
  for (final i in idx) {
    final v = f(i);
    if (v > m) m = v;
  }
  return m;
}

