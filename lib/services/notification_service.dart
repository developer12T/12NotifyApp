import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
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
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // จัดการเมื่อผู้ใช้แตะที่การแจ้งเตือน
        debugPrint('ผู้ใช้แตะที่การแจ้งเตือน: ${response.payload}');
      },
    );
  }

  // ฟังก์ชันสำหรับแสดงการแจ้งเตือน
  Future<void> showNotification({
    required String title,    // หัวข้อการแจ้งเตือน
    required String body,     // เนื้อหาการแจ้งเตือน
    String? payload,         // ข้อมูลเพิ่มเติม (ถ้ามี)
  }) async {
    // ตั้งค่าการแจ้งเตือนสำหรับ Android
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'default_channel',     // ID ของช่องทางการแจ้งเตือน
      'Default Channel',     // ชื่อช่องทางการแจ้งเตือน
      channelDescription: 'ช่องทางการแจ้งเตือนเริ่มต้น',
      importance: Importance.max,    // ความสำคัญสูงสุด
      priority: Priority.high,       // ความสำคัญสูง
      showWhen: true,               // แสดงเวลาที่ได้รับ
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
    await flutterLocalNotificationsPlugin.show(
      0,              // ID ของการแจ้งเตือน
      title,          // หัวข้อ
      body,           // เนื้อหา
      platformChannelSpecifics,
      payload: payload,
    );
  }
} 