import 'package:firebase_core/firebase_core.dart';
import 'dart:io' show Platform;

class FirebaseTest {
  static Future<bool> testFirebaseInitialization() async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        print('FirebaseTest: Attempting to initialize Firebase...');
        await Firebase.initializeApp();
        print('FirebaseTest: Firebase initialized successfully');
        return true;
      } catch (e) {
        print('FirebaseTest: Error initializing Firebase: $e');
        return false;
      }
    } else {
      print('FirebaseTest: Skipping Firebase initialization on desktop');
      return false;
    }
  }
} 