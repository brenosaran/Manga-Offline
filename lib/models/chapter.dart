import 'package:objectbox/objectbox.dart';

@Entity()
class Chapter {
  Chapter({
    this.id = 0,
    required this.serieId,
    required this.title,
    required this.number,
    this.volume = 0,
    this.pagePaths = const [],
    this.folderPath = '',
    this.cbzPath,
    this.lastPageIndex = 0,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  @Id()
  int id;

  int serieId;

  String title;

  double number;

  int volume;

  List<String> pagePaths;

  String folderPath;

  String? cbzPath;

  int lastPageIndex;

  DateTime addedAt;

  int get pageCount => pagePaths.length;

  String? get coverPath => pagePaths.isEmpty ? null : pagePaths.first;

  double get progress =>
      pageCount == 0 ? 0 : (lastPageIndex + 1) / pageCount;
}
