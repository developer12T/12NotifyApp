import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:convert';

class DesktopNotificationService {
  static final DesktopNotificationService _instance = DesktopNotificationService._internal();
  factory DesktopNotificationService() => _instance;
  DesktopNotificationService._internal();

  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  // Track recent notifications to prevent duplicates
  final Map<String, DateTime> _recentNotifications = {};
  static const Duration _notificationCooldown = Duration(seconds: 5);

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await _localNotifications.initialize(initializationSettings);

      // Create notification channels for different platforms
      if (Platform.isAndroid) {
        await _createAndroidChannels();
      } else if (Platform.isIOS) {
        // iOS doesn't need channels
      } else {
        // Desktop platforms
        await _createDesktopChannels();
      }

      _isInitialized = true;
      print('DesktopNotificationService: Initialized successfully');
    } catch (e) {
      print('DesktopNotificationService: Error initializing: $e');
    }
  }

  Future<void> _createAndroidChannels() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'desktop_notifications',
      'Desktop Notifications',
      description: 'ช่องทางการแจ้งเตือนสำหรับ Desktop',
      importance: Importance.max,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> _createDesktopChannels() async {
    // For desktop, we'll use a simple channel
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'desktop_notifications',
      'Desktop Notifications',
      description: 'ช่องทางการแจ้งเตือนสำหรับ Desktop',
      importance: Importance.max,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> showNotification({
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Create unique key for this notification
    final notificationKey = '${title}_${body}_${payload.toString()}';
    
    // Check for duplicates
    final now = DateTime.now();
    if (_recentNotifications.containsKey(notificationKey)) {
      final lastShown = _recentNotifications[notificationKey]!;
      if (now.difference(lastShown) < _notificationCooldown) {
        print('DesktopNotificationService: Skipping duplicate notification');
        return;
      }
    }

    try {
      NotificationDetails notificationDetails;
      
      if (Platform.isAndroid) {
        notificationDetails = const NotificationDetails(
          android: AndroidNotificationDetails(
            'desktop_notifications',
            'Desktop Notifications',
            channelDescription: 'ช่องทางการแจ้งเตือนสำหรับ Desktop',
            importance: Importance.max,
            priority: Priority.high,
            showWhen: true,
            enableVibration: true,
            playSound: true,
          ),
        );
      } else if (Platform.isIOS) {
        notificationDetails = const NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        );
      } else {
        // Desktop platforms
        notificationDetails = const NotificationDetails(
          android: AndroidNotificationDetails(
            'desktop_notifications',
            'Desktop Notifications',
            channelDescription: 'ช่องทางการแจ้งเตือนสำหรับ Desktop',
            importance: Importance.max,
            priority: Priority.high,
            showWhen: true,
            enableVibration: false, // No vibration on desktop
            playSound: true,
          ),
        );
      }

      final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      
      await _localNotifications.show(
        id,
        title,
        body,
        notificationDetails,
        payload: payload != null ? json.encode(payload) : null,
      );

      // Track this notification
      _recentNotifications[notificationKey] = now;
      
      // Clean up old entries
      _recentNotifications.removeWhere(
        (key, time) => now.difference(time) > const Duration(minutes: 2),
      );

      print('DesktopNotificationService: Notification shown with ID: $id');
    } catch (e) {
      print('DesktopNotificationService: Error showing notification: $e');
    }
  }

  Future<void> showAnnouncementNotification({
    required String title,
    required String content,
    Map<String, dynamic>? data,
  }) async {
    await showNotification(
      title: 'ประกาศใหม่: $title',
      body: content,
      payload: data,
    );
  }

  Future<void> showMessageNotification({
    required String senderName,
    required String message,
    Map<String, dynamic>? data,
  }) async {
    final shortMessage = message.length > 50 ? '${message.substring(0, 50)}...' : message;
    
    await showNotification(
      title: 'ข้อความใหม่จาก $senderName',
      body: shortMessage,
      payload: data,
    );
  }

  // Test method
  Future<void> testNotification() async {
    await showNotification(
      title: 'ทดสอบการแจ้งเตือน',
      body: 'นี่คือการทดสอบการแจ้งเตือนบน Desktop',
      payload: {'type': 'test', 'timestamp': DateTime.now().toIso8601String()},
    );
  }
} 