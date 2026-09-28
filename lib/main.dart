import 'package:flutter/material.dart';

import 'app.dart';
import 'core/settings_controller.dart';
import 'services/database_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsController.instance.load();
  await DatabaseService.instance.init();
  runApp(const MangaOfflineApp());
}
