import 'package:firebase_core/firebase_core.dart';

class FirebaseTest {
  static Future<bool> testFirebaseInitialization() async {
    try {
      print('FirebaseTest: Attempting to initialize Firebase...');
      await Firebase.initializeApp();
      print('FirebaseTest: Firebase initialized successfully');
      return true;
    } catch (e) {
      print('FirebaseTest: Error initializing Firebase: $e');
      return false;
    }
  }
} 