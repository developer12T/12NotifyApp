import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

// Top-level function for background notification handling
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  print('onDidReceiveBackgroundNotificationResponse: ${response.payload}');
}

class NotiService {
  static final NotiService _instance = NotiService._internal();
  factory NotiService() => _instance;
  NotiService._internal();

  final notificationsPlugin = FlutterLocalNotificationsPlugin();
  
  bool _isInitialized = false;
  
  bool get isInitialized => _isInitialized;

  static const androidChannelId = 'announcements_channel_id';
  static const androidChannelName = 'Announcements';
  static const androidChannelDescription = 'Announcements Channel';
  
  // INITIALIZE
  Future<void> initNotification() async {
    print('NotiService: Initializing notifications...');
    if (_isInitialized) {
      print('NotiService: Already initialized');
      return;
    }
    
    try {
      // Request permissions for Android 13 and above
      final androidPlugin = notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final granted = await androidPlugin.requestNotificationsPermission();
        print('NotiService: Android notification permission granted: $granted');
      }

      // Request permissions for iOS
      final iOSPlugin = notificationsPlugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (iOSPlugin != null) {
        final granted = await iOSPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        print('NotiService: iOS notification permission granted: $granted');
      }
      
      // prepare android init settings
      const initSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      
      // prepare ios init settings
      const initSettingsIOS = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      // prepare windows init settings
      const initSettingsWindows = WindowsInitializationSettings(
        appName: '12Chat',
        appUserModelId: 'com.onetwotrading.onetwochat.flutterNotify',
        guid: '12345678-1234-1234-1234-123456789012',
      );
      
      const initSetting = InitializationSettings(
        android: initSettingsAndroid,
        iOS: initSettingsIOS,
        windows: initSettingsWindows,
      );
    
      // Create notification channel for Android
      await notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              androidChannelId,
              androidChannelName,
              description: androidChannelDescription,
              importance: Importance.high,
              enableVibration: true,
              playSound: true,
            ),
          );
    
      await notificationsPlugin.initialize(
        initSetting,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          print('NotiService: Notification tapped: ${response.payload}');
          // Handle notification tap - you can add navigation logic here
        },
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );

      _isInitialized = true;
      print('NotiService: Initialization completed successfully');
    } catch (e) {
      print('NotiService: Error initializing notifications: $e');
      rethrow;
    }
  }

  // SHOW NOTIFICATION
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    print('=== NotiService: Attempting to show notification ===');
    print('NotiService: Title: $title');
    print('NotiService: Body: $body');
    print('NotiService: Payload: $payload');
    print('NotiService: Is initialized: $_isInitialized');
    print('NotiService: Plugin instance: ${notificationsPlugin != null ? 'OK' : 'NULL'}');
    
    try {
      if (!_isInitialized) {
        print('NotiService: Not initialized, initializing now...');
        await initNotification();
      }

      const notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          androidChannelId,
          androidChannelName,
          channelDescription: androidChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          enableVibration: true,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      print('NotiService: Showing notification with ID: $id');
      print('NotiService: Notification details: $notificationDetails');
      
      await notificationsPlugin.show(
        id,
        title,
        body,
        notificationDetails,
        payload: payload,
      );
      print('NotiService: Notification shown successfully with ID: $id');
    } catch (e) {
      print('=== NotiService: Error showing notification ===');
      print('NotiService: Error: $e');
      print('NotiService: Error type: ${e.runtimeType}');
      print('NotiService: Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  // SHOW NOTIFICATION WITHOUT RE-INITIALIZATION (สำหรับ background service)
  Future<void> showNotificationWithoutInit({
    required String title,
    required String body,
    String? payload,
  }) async {
    print('=== NotiService: Attempting to show notification without init ===');
    print('NotiService: Title: $title');
    print('NotiService: Body: $body');
    print('NotiService: Payload: $payload');
    print('NotiService: Is initialized: $_isInitialized');
    
    try {
      // ใช้ notification details แบบ simple โดยไม่ต้อง initialize ใหม่
      const notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'socket_service_channel',  // ใช้ channel เดียวกับ background service
          '12Chat Background Service',
          channelDescription: 'ช่องทางการแจ้งเตือนสำหรับ Background Service',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          enableVibration: true,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      print('NotiService: Showing notification without init with ID: $id');
      
      // ลองแสดง notification โดยไม่ต้อง initialize ใหม่
      await notificationsPlugin.show(
        id,
        title,
        body,
        notificationDetails,
        payload: payload,
      );
      print('NotiService: Notification without init shown successfully with ID: $id');
    } catch (e) {
      print('=== NotiService: Error showing notification without init ===');
      print('NotiService: Error: $e');
      print('NotiService: Error type: ${e.runtimeType}');
      print('NotiService: Stack trace: ${StackTrace.current}');
      
      // ถ้าไม่สำเร็จ ให้ throw error เพื่อให้ caller จัดการต่อ
      rethrow;
    }
  }
} 