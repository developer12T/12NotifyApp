import 'package:flutter_background_service/flutter_background_service.dart';
import 'dart:convert';

class BackgroundNotificationService {
  static final BackgroundNotificationService _instance = BackgroundNotificationService._internal();
  factory BackgroundNotificationService() => _instance;
  BackgroundNotificationService._internal();

  // แสดง notification ผ่าน background service
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      print('=== BackgroundNotificationService: Showing notification ===');
      print('Title: $title');
      print('Body: $body');
      print('Payload: $payload');
      
      final service = FlutterBackgroundService();
      
      // ส่งข้อมูลไปยังแอปหลักเพื่อแสดง notification
      service.invoke('showNotificationFromService', {
        'title': title,
        'body': body,
        'payload': payload,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      print('=== BackgroundNotificationService: Notification request sent ===');
      
    } catch (e) {
      print('=== BackgroundNotificationService: Error showing notification ===');
      print('Error: $e');
      rethrow;
    }
  }

  // แสดง notification แบบ simple (สำหรับ background service)
  Future<void> showSimpleNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      print('=== BackgroundNotificationService: Showing simple notification ===');
      
      // ใช้ background service notification แบบ simple
      final service = FlutterBackgroundService();
      
      // ส่งข้อมูลแบบ simple
      service.invoke('simpleNotification', {
        'title': title,
        'body': body,
        'payload': payload,
      });
      
      print('=== BackgroundNotificationService: Simple notification sent ===');
      
    } catch (e) {
      print('=== BackgroundNotificationService: Error showing simple notification ===');
      print('Error: $e');
    }
  }

  // แสดง notification แบบ emergency (สำหรับกรณีที่แอปปิด)
  Future<void> showEmergencyNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      print('=== BackgroundNotificationService: Showing emergency notification ===');
      
      // ใช้ background service notification แบบ emergency
      final service = FlutterBackgroundService();
      
      service.invoke('emergencyNotification', {
        'title': title,
        'body': body,
        'payload': payload,
        'priority': 'high',
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      print('=== BackgroundNotificationService: Emergency notification sent ===');
      
    } catch (e) {
      print('=== BackgroundNotificationService: Error showing emergency notification ===');
      print('Error: $e');
    }
  }
} 