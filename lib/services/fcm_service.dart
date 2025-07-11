import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'api_service.dart';

// Background message handler (ต้องอยู่นอก class)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Background message received: ${message.notification?.title}');
  
  // Show local notification for background messages
  await _showBackgroundNotification(message);
}

// Helper function to show notification in background
@pragma('vm:entry-point')
Future<void> _showBackgroundNotification(RemoteMessage message) async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'fcm_background_channel',
    'FCM Background Notifications',
    channelDescription: 'ช่องทางการแจ้งเตือน FCM สำหรับ Background',
    importance: Importance.max,
    priority: Priority.high,
    showWhen: true,
    enableVibration: true,
    playSound: true,
  );

  const DarwinNotificationDetails iOSPlatformChannelSpecifics =
      DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );

  const NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
    iOS: iOSPlatformChannelSpecifics,
  );

  final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  
  await flutterLocalNotificationsPlugin.show(
    id,
    message.notification?.title ?? 'New Message',
    message.notification?.body ?? '',
    platformChannelSpecifics,
    payload: json.encode(message.data),
  );
}

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = 
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  static Future<void> initialize() async {
    print('FCMService: Initializing FCM...');
    
    try {
      // Check if Firebase is initialized
      try {
        await Firebase.initializeApp();
      } catch (e) {
        print('FCMService: Firebase already initialized or error: $e');
      }
      
      // Request permission
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      print('FCMService: Authorization status: ${settings.authorizationStatus}');
      
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('FCMService: User granted permission');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        print('FCMService: User granted provisional permission');
      } else {
        print('FCMService: User denied permission');
      }

      // Get FCM token
      String? token = await _firebaseMessaging.getToken();
      print('FCMService: FCM Token: $token');
      
      // บันทึก token ไปยัง server/database
      if (token != null) {
        await _saveTokenToDatabase(token);
      }

      // Setup background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Setup local notifications
      await _setupLocalNotifications();

      // Handle notification tap when app is terminated
      RemoteMessage? initialMessage = await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        print('FCMService: App opened from terminated state');
        _handleNotificationTap(initialMessage);
      }

      // Handle notification tap when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('FCMService: App opened from background');
        _handleNotificationTap(message);
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('FCMService: Foreground message received');
        _handleForegroundMessage(message);
      });

      // Token refresh
      _firebaseMessaging.onTokenRefresh.listen((String token) {
        print('FCMService: Token refreshed: $token');
        _saveTokenToDatabase(token);
      });

      print('FCMService: Initialization completed successfully');
    } catch (e) {
      print('FCMService: Error during initialization: $e');
      rethrow;
    }
  }

  static Future<void> _setupLocalNotifications() async {
    try {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
        requestAlertPermission: false, // Already requested above
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await _localNotifications.initialize(initializationSettings);

      // Create notification channel for Android
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'fcm_foreground_channel',
        'FCM Foreground Notifications',
        description: 'ช่องทางการแจ้งเตือน FCM สำหรับ Foreground',
        importance: Importance.max,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
          
      print('FCMService: Local notifications setup completed');
    } catch (e) {
      print('FCMService: Error setting up local notifications: $e');
    }
  }

  static Future<void> _saveTokenToDatabase(String token) async {
    // บันทึก token ไปยัง server หรือ database
    print('FCMService: Saving token to database: $token');
    
    try {
      // Get user ID from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('user');
      String? userId;
      
      if (userJson != null) {
        final userData = jsonDecode(userJson);
        userId = userData['employeeID']?.toString();
      }
      
      if (userId == null) {
        print('FCMService: User ID not found, skipping token save');
        return;
      }
      
      // Save token to your server
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${prefs.getString('token')}',
        },
        body: json.encode({
          'user_id': userId,
          'fcm_token': token,
          'platform': Platform.isAndroid ? 'android' : 'ios',
          'app_version': '1.0.0',
        }),
      );
      
      if (response.statusCode == 200) {
        print('FCMService: Token saved successfully to server');
      } else {
        print('FCMService: Failed to save token: ${response.statusCode}');
        print('FCMService: Response: ${response.body}');
      }
    } catch (e) {
      print('FCMService: Error saving token: $e');
      // Don't throw error, just log it
    }
  }

  static void _handleNotificationTap(RemoteMessage message) {
    // จัดการเมื่อผู้ใช้แตะ notification
    print('FCMService: Notification tapped: ${message.data}');
    
    // Navigate to specific screen based on notification data
    if (message.data.containsKey('chat_id')) {
      // Navigate to chat screen
      // Get.to(() => ChatScreen(chatId: message.data['chat_id']));
      print('FCMService: Should navigate to chat: ${message.data['chat_id']}');
    } else if (message.data.containsKey('announcement_id')) {
      // Navigate to announcement screen
      // Get.to(() => AnnouncementDetailScreen(announcementId: message.data['announcement_id']));
      print('FCMService: Should navigate to announcement: ${message.data['announcement_id']}');
    }
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    print('FCMService: Handling foreground message: ${message.notification?.title}');
    
    // Show local notification for foreground messages
    _showForegroundNotification(message);
  }

  static Future<void> _showForegroundNotification(RemoteMessage message) async {
    try {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'fcm_foreground_channel',
        'FCM Foreground Notifications',
        channelDescription: 'ช่องทางการแจ้งเตือน FCM สำหรับ Foreground',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
      );

      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      
      await _localNotifications.show(
        id,
        message.notification?.title ?? 'New Message',
        message.notification?.body ?? '',
        platformChannelSpecifics,
        payload: json.encode(message.data),
      );
      
      print('FCMService: Foreground notification shown with ID: $id');
    } catch (e) {
      print('FCMService: Error showing foreground notification: $e');
    }
  }

  /// เรียกหลัง login หรือ token refresh
  static Future<void> registerFCMToken() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    if (userJson == null) {
      print('FCMService: userJson is null, skip sending token');
      return;
    }
    dynamic userData;
    try {
      userData = jsonDecode(userJson);
    } catch (e) {
      print('FCMService: userJson decode error: $e');
      return;
    }
    final employeeID = userData?['employeeID']?.toString();
    if (employeeID == null) {
      print('FCMService: employeeID not found, skip sending token');
      return;
    }
    String? token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await sendTokenToServer(token, employeeID);
    }
  }

  /// ส่ง token ไป backend
  static Future<void> sendTokenToServer(String token, String employeeID) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/users/update-fcm-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'employeeID': employeeID,
          'fcmToken': token,
          'deviceInfo': {
            'platform': Platform.isAndroid ? 'android' : 'ios',
            'appVersion': '1.0.0',
          }
        }),
      );
      if (response.statusCode == 200) {
        print('FCMService: Token saved successfully');
      } else {
        print('FCMService: Failed to save token: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('FCMService: Error saving token: $e');
    }
  }

  /// Listen for token refresh (ควรเรียกหลัง login)
  static void listenFCMTokenRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    if (userJson == null) {
      print('FCMService: userJson is null, skip token refresh listener');
      return;
    }
    dynamic userData;
    try {
      userData = jsonDecode(userJson);
    } catch (e) {
      print('FCMService: userJson decode error: $e');
      return;
    }
    final employeeID = userData?['employeeID']?.toString();
    if (employeeID == null) {
      print('FCMService: employeeID not found, skip token refresh listener');
      return;
    }
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      sendTokenToServer(token, employeeID);
    });
  }

  // Get current FCM token
  static Future<String?> getToken() async {
    return await _firebaseMessaging.getToken();
  }

  // Subscribe to topic
  static Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      print('FCMService: Subscribed to topic: $topic');
    } catch (e) {
      print('FCMService: Error subscribing to topic: $e');
    }
  }

  // Unsubscribe from topic
  static Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      print('FCMService: Unsubscribed from topic: $topic');
    } catch (e) {
      print('FCMService: Error unsubscribing from topic: $e');
    }
  }

  // Delete token (for logout)
  static Future<void> deleteToken() async {
    try {
      await _firebaseMessaging.deleteToken();
      print('FCMService: FCM token deleted');
    } catch (e) {
      print('FCMService: Error deleting FCM token: $e');
    }
  }

  // Test method to verify FCM setup
  static Future<void> testFCMSetup() async {
    try {
      String? token = await getToken();
      print('FCMService: Test - Current token: $token');
      
      if (token != null) {
        print('FCMService: Test - FCM setup is working correctly');
        return;
      } else {
        print('FCMService: Test - FCM token is null');
      }
    } catch (e) {
      print('FCMService: Test - Error: $e');
    }
  }
} 