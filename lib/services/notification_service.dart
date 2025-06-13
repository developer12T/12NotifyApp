import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'dart:convert';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  Future<void> init({Function(Map<String, dynamic>)? onNotificationTap}) async {
    print('NotificationService: Initializing...');
    
    try {
      // ตั้งค่าการแจ้งเตือนสำหรับ Android
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // ตั้งค่าการแจ้งเตือนสำหรับ iOS
      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
        requestAlertPermission: true,  // ขออนุญาตแสดงการแจ้งเตือน
        requestBadgePermission: true,  // ขออนุญาตแสดง badge
        requestSoundPermission: true,  // ขออนุญาตเล่นเสียง
      );

      // รวมการตั้งค่าสำหรับทั้ง Android และ iOS
      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      // เริ่มต้นการแจ้งเตือน
      final bool? result = await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // จัดการเมื่อผู้ใช้แตะที่การแจ้งเตือน
          print('NotificationService: User tapped notification: ${response.payload}');
          debugPrint('ผู้ใช้แตะที่การแจ้งเตือน: ${response.payload}');
          
          if (response.payload != null && onNotificationTap != null) {
            try {
              final payload = jsonDecode(response.payload!);
              onNotificationTap(payload);
            } catch (e) {
              print('NotificationService: Error parsing notification payload: $e');
              debugPrint('Error parsing notification payload: $e');
            }
          }
        },
      );
      
      _isInitialized = result ?? false;
      print('NotificationService: Initialization result: $_isInitialized');
      
      // Create notification channel for Android
      await _createNotificationChannel();
      
    } catch (e) {
      print('NotificationService: Error during initialization: $e');
      _isInitialized = false;
    }
  }

  Future<void> _createNotificationChannel() async {
    try {
      final androidPlugin = flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'default_channel',
            '12Chat Notify',
            description: 'ช่องทางการแจ้งเตือน 12Chat',
            importance: Importance.max,
            enableVibration: true,
            playSound: true,
          ),
        );
        print('NotificationService: Android notification channel created');
      }
    } catch (e) {
      print('NotificationService: Error creating notification channel: $e');
    }
  }

  // ฟังก์ชันสำหรับแสดงการแจ้งเตือน
  Future<void> showNotification({
    required String title,    // หัวข้อการแจ้งเตือน
    required String body,     // เนื้อหาการแจ้งเตือน
    String? payload,         // ข้อมูลเพิ่มเติม (ถ้ามี)
  }) async {
    print('NotificationService: Attempting to show notification');
    print('NotificationService: Title: $title');
    print('NotificationService: Body: $body');
    print('NotificationService: Payload: $payload');
    print('NotificationService: Is initialized: $_isInitialized');
    
    try {
      if (!_isInitialized) {
        print('NotificationService: Not initialized, initializing now...');
        await init();
      }

      // ตั้งค่าการแจ้งเตือนสำหรับ Android
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'default_channel',     // ID ของช่องทางการแจ้งเตือน
        '12Chat Notify',       // ชื่อช่องทางการแจ้งเตือน (จะแสดงเป็นหัวข้อ popup)
        channelDescription: 'ช่องทางการแจ้งเตือน 12Chat',
        importance: Importance.max,    // ความสำคัญสูงสุด
        priority: Priority.high,       // ความสำคัญสูง
        showWhen: true,               // แสดงเวลาที่ได้รับ
        enableVibration: true,        // เปิดการสั่น
        playSound: true,              // เล่นเสียง
      );

      // ตั้งค่าการแจ้งเตือนสำหรับ iOS
      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
          DarwinNotificationDetails(
        presentAlert: true,    // แสดงการแจ้งเตือน
        presentBadge: true,    // แสดง badge
        presentSound: true,    // เล่นเสียง
      );

      // รวมการตั้งค่าสำหรับทั้ง Android และ iOS
      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      // แสดงการแจ้งเตือน
      final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      print('NotificationService: Showing notification with ID: $id');
      
      await flutterLocalNotificationsPlugin.show(
        id,              // ID ของการแจ้งเตือน
        title,          // หัวข้อ
        body,           // เนื้อหา
        platformChannelSpecifics,
        payload: payload,
      );
      
      print('NotificationService: Notification shown successfully with ID: $id');
    } catch (e) {
      print('NotificationService: Error showing notification: $e');
      print('NotificationService: Stack trace: ${StackTrace.current}');
    }
  }
} 