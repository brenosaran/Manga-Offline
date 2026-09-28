import 'package:objectbox/objectbox.dart';

@Entity()
class VolumeIndex {
  VolumeIndex({
    this.id = 0,
    required this.dexId,
    this.data = '{}',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  @Id()
  int id;

  String dexId;

  String data;

  DateTime updatedAt;
}
