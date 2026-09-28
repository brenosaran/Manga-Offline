import 'package:objectbox/objectbox.dart';

@Entity()
class Serie {
  Serie({
    this.id = 0,
    required this.title,
    this.description = '',
    this.category = '',
    this.coverThumbPath,
    this.folderPath = '',
    this.sourceId,
    this.dexId,
    this.sourceUrl,
    this.kind = 'manga',
    this.recommendationsJson = '',
    this.arcsJson = '',
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  @Id()
  int id;

  String title;

  String description;

  String category;

  String? coverThumbPath;

  String folderPath;

  String? sourceId;

  String? dexId;

  String? sourceUrl;

  String kind;

  String recommendationsJson;

  String arcsJson;

  DateTime addedAt;
}
