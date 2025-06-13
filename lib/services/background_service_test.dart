import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:convert';

class BackgroundServiceTest {
  static final BackgroundServiceTest _instance = BackgroundServiceTest._internal();
  factory BackgroundServiceTest() => _instance;
  BackgroundServiceTest._internal();

  /// ทดสอบการเริ่มต้น background service
  Future<void> testStartBackgroundService() async {
    print('=== Testing Background Service Start ===');
    
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      
      print('Background service is running: $isRunning');
      
      if (!isRunning) {
        print('Starting background service...');
        await service.startService();
        
        // รอให้ service เริ่มต้น
        await Future.delayed(const Duration(seconds: 3));
        
        final isRunningAfter = await service.isRunning();
        print('Background service is running after start: $isRunningAfter');
      }
      
      // ทดสอบส่งข้อมูลไปยัง service
      service.invoke('test', {
        'message': 'Test message from main app',
        'timestamp': DateTime.now().toIso8601String(),
      });
      
    } catch (e) {
      print('Error testing background service: $e');
      print('Stack trace: ${StackTrace.current}');
    }
  }

  /// ทดสอบการส่ง notification จาก background service
  Future<void> testBackgroundNotification() async {
    print('=== Testing Background Notification ===');
    
    try {
      final service = FlutterBackgroundService();
      
      // ส่งคำสั่งให้ background service แสดง notification
      service.invoke('showNotification', {
        'title': 'ทดสอบจากแอปหลัก',
        'body': 'นี่คือการทดสอบการแจ้งเตือนจาก background service',
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      print('Notification test command sent to background service');
      
    } catch (e) {
      print('Error testing background notification: $e');
    }
  }

  /// ทดสอบการเชื่อมต่อ socket ใน background
  Future<void> testBackgroundSocket() async {
    print('=== Testing Background Socket ===');
    
    try {
      final service = FlutterBackgroundService();
      
      // ส่งคำสั่งให้ background service ทดสอบ socket
      service.invoke('testSocket', {
        'action': 'connect',
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      print('Socket test command sent to background service');
      
    } catch (e) {
      print('Error testing background socket: $e');
    }
  }

  /// ตรวจสอบสถานะของ background service
  Future<void> checkBackgroundServiceStatus() async {
    print('=== Checking Background Service Status ===');
    
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      
      print('Background service status:');
      print('- Is running: $isRunning');
      
      if (isRunning) {
        // รับข้อมูลจาก service
        service.invoke('getStatus', {});
        
        // รับข้อมูลจาก service
        service.on('status').listen((event) {
          print('Service status received: $event');
        });
      }
      
    } catch (e) {
      print('Error checking background service status: $e');
    }
  }

  /// หยุด background service
  Future<void> stopBackgroundService() async {
    print('=== Stopping Background Service ===');
    
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      
      if (isRunning) {
        service.invoke('stopService');
        print('Stop command sent to background service');
        
        // รอให้ service หยุด
        await Future.delayed(const Duration(seconds: 2));
        
        final isRunningAfter = await service.isRunning();
        print('Background service is running after stop: $isRunningAfter');
      } else {
        print('Background service is not running');
      }
      
    } catch (e) {
      print('Error stopping background service: $e');
    }
  }
} 