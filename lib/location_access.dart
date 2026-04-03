import 'dart:async';

import 'package:geolocator/geolocator.dart';

class LocationAccessException implements Exception {
  LocationAccessException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LocationAccess {
  static Future<void> requestInitialPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
    } catch (_) {
      // Keep the splash flow moving even if the device can't answer yet.
    }
  }

  static Future<Position> currentPunchPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw LocationAccessException(
        'Turn on location services to capture attendance.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw LocationAccessException(
        'Location permission is required to capture attendance.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw LocationAccessException(
        'Location permission is permanently denied. Enable it in app settings.',
      );
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );
    } on TimeoutException {
      throw LocationAccessException(
        'Unable to get your location. Please try again in an open area.',
      );
    } catch (_) {
      throw LocationAccessException(
        'Unable to get your location. Please try again.',
      );
    }
  }
}
