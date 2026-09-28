import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class VolumeButtonService {
  static const MethodChannel _channel =
      MethodChannel('manga_offline/volume');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> enable({
    required VoidCallback onNext,
    required VoidCallback onPrevious,
  }) async {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'volumeDown':
          onNext();
          break;
        case 'volumeUp':
          onPrevious();
          break;
      }
      return null;
    });

    if (isSupported) {
      try {
        await _channel.invokeMethod<bool>('enable');
      } on PlatformException {
        // Ignora: segue com a navegação por toque/teclado.
      } on MissingPluginException {
        // Plataforma sem implementação nativa.
      }
    }
  }

  Future<void> disable() async {
    _channel.setMethodCallHandler(null);
    if (isSupported) {
      try {
        await _channel.invokeMethod<bool>('disable');
      } on PlatformException {
        // Ignora.
      } on MissingPluginException {
        // Ignora.
      }
    }
  }
}
