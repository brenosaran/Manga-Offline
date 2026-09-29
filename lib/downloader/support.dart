import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'naming.dart';

/// Executa [worker] [count] vezes com no máximo [concurrency] em paralelo.
Future<void> runPool({
  required int count,
  required int concurrency,
  required Future<void> Function() worker,
}) async {
  final workers = List.generate(
    math.max(1, math.min(concurrency, count)),
    (_) => worker(),
  );
  await Future.wait(workers);
}

/// Repete [action] até [retries] vezes extras, com espera crescente.
Future<T> retryOperation<T>(
  Future<T> Function() action, {
  required int retries,
}) async {
  var attempt = 0;
  while (true) {
    attempt++;
    try {
      return await action();
    } catch (e) {
      if (attempt > retries) rethrow;
      await Future.delayed(Duration(milliseconds: 500 * attempt));
    }
  }
}

/// Grava o `.cbz` de forma atômica (temporário + rename).
Future<void> writeCbz(
  File file,
  List<Uint8List> images,
  List<String> originalNames,
) async {
  final bytes = buildCbz(images, originalNames);
  final tmp = File('${file.path}.part');
  await tmp.writeAsBytes(bytes, flush: true);
  if (file.existsSync()) await file.delete();
  await tmp.rename(file.path);
}
