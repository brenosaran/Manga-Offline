import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/chapter.dart';
import '../models/serie.dart';
import '../models/volume_index.dart';
import '../objectbox.g.dart';

class DatabaseService {
  DatabaseService._();

  static final DatabaseService instance = DatabaseService._();

  Store? _store;

  Store get store {
    final value = _store;
    if (value == null) {
      throw StateError('DatabaseService.init() ainda não foi chamado.');
    }
    return value;
  }

  Box<Serie> get series => store.box<Serie>();

  Box<Chapter> get chapters => store.box<Chapter>();

  Box<VolumeIndex> get volumeIndexes => store.box<VolumeIndex>();

  Future<void> init() async {
    if (_store != null) return;
    final dir = await getApplicationDocumentsDirectory();
    _store = await openStore(
      directory: p.join(dir.path, 'manga_offline_db'),
    );
  }
}
