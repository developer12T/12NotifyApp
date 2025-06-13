import 'package:flutter/material.dart';
import 'dart:convert';
import '../services/notification_service.dart';
import '../services/api_service.dart';
import 'package:http/http.dart' as http;

class TestNotificationPage extends StatefulWidget {
  final ApiService apiService;
  
  const TestNotificationPage({
    super.key,
    required this.apiService,
  });

  @override
  State<TestNotificationPage> createState() => _TestNotificationPageState();
}

class _TestNotificationPageState extends State<TestNotificationPage> {
  final NotificationService _notificationService = NotificationService();
  bool _isInitialized = false;
  String _notificationStatus = 'ยังไม่มีการทดสอบ';
  int _notificationCount = 0;
  String _lastNotificationTime = 'ไม่มี';

  @override
  void initState() {
    super.initState();
    _initializeNotification();
  }

  Future<void> _initializeNotification() async {
    print('TestNotificationPage: Initializing notification...');
    try {
      await _notificationService.init();
      setState(() {
        _isInitialized = true;
      });
      print('TestNotificationPage: Notification initialized successfully');
    } catch (e) {
      print('TestNotificationPage: Error initializing notification: $e');
    }
  }

  Future<void> _testNotification() async {
    print('TestNotificationPage: Testing notification...');
    try {
      await _notificationService.showNotification(
        title: 'ทดสอบการแจ้งเตือน',
        body: 'นี่คือการทดสอบการแจ้งเตือนจากหน้า Test',
        payload: jsonEncode({
          'type': 'test',
          'message': 'Test notification from test page',
        }),
      );
      print('TestNotificationPage: Test notification sent successfully');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('การแจ้งเตือนถูกส่งแล้ว'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('TestNotificationPage: Error sending test notification: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _testRoomNotification() async {
    print('TestNotificationPage: Testing room notification...');
    try {
      await _notificationService.showNotification(
        title: 'ข้อความใหม่ในกลุ่ม',
        body: 'คุณมีข้อความใหม่ในกลุ่ม 3 ข้อความ',
        payload: jsonEncode({
          'type': 'room',
          'unreadCount': 3,
        }),
      );
      print('TestNotificationPage: Room notification sent successfully');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('การแจ้งเตือนห้องถูกส่งแล้ว'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('TestNotificationPage: Error sending room notification: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _testBackendMessage() async {
    print('TestNotificationPage: Testing backend message...');
    try {
      // ส่งข้อความทดสอบไปยัง backend
      final response = await http.post(
        Uri.parse('https://apps.onetwotrading.co.th/12chat/api/messages'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'roomId': '6847ac0514fdb9c943d98a7c', // กลุ่มแจ้งปัญหา
          'message': 'ข้อความทดสอบจาก TestNotificationPage',
          'senderId': '68213', // User ID ของคุณ
        }),
      );
      
      print('TestNotificationPage: Backend response status: ${response.statusCode}');
      print('TestNotificationPage: Backend response body: ${response.body}');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ส่งข้อความทดสอบแล้ว (Status: ${response.statusCode})'),
            backgroundColor: response.statusCode == 200 ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('TestNotificationPage: Error sending backend message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _testBadgeCount() async {
    print('TestNotificationPage: Testing badge count...');
    try {
      // This is just a test - in real scenario this would come from room updates
      print('TestNotificationPage: Badge count test completed');
      
      setState(() {
        _notificationCount++;
        _notificationStatus = 'ทดสอบ Badge Count สำเร็จ';
        _lastNotificationTime = DateTime.now().toString();
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('การทดสอบ Badge Count สำเร็จ'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('TestNotificationPage: Error testing badge count: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _testBadgeCountReset() async {
    print('TestNotificationPage: Resetting badge count...');
    try {
      // This would reset the badge count to 0
      print('TestNotificationPage: Badge count reset test completed');
      
      setState(() {
        _notificationCount = 0;
        _notificationStatus = 'รีเซ็ต Badge Count สำเร็จ';
        _lastNotificationTime = DateTime.now().toString();
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('การรีเซ็ต Badge Count สำเร็จ'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('TestNotificationPage: Error resetting badge count: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _testRealTimeMessage() async {
    print('TestNotificationPage: Testing real-time message...');
    try {
      // This is just a test - in real scenario this would come from room updates
      print('TestNotificationPage: Real-time message test completed');
      
      setState(() {
        _notificationCount++;
        _notificationStatus = 'ทดสอบข้อความเรียลไทม สำเร็จ';
        _lastNotificationTime = DateTime.now().toString();
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('การทดสอบข้อความเรียลไทม สำเร็จ'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('TestNotificationPage: Error testing real-time message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _testCrossRoomMessaging() async {
    print('TestNotificationPage: Testing cross-room messaging...');
    try {
      // Test sending a message to a different room to simulate real-time messaging
      if (widget.apiService.socket?.connected == true) {
        print('TestNotificationPage: Socket is connected, testing cross-room message');
        
        // Simulate a message from another room
        final testMessage = {
          '_id': 'test_${DateTime.now().millisecondsSinceEpoch}',
          'room': 'test_room_id',
          'message': 'ข้อความทดสอบจากห้องอื่น - ${DateTime.now().toString()}',
          'sender': {
            'employeeID': 'test_user',
            'name': 'ผู้ใช้ทดสอบ'
          },
          'timestamp': DateTime.now().toIso8601String(),
          'isRead': false,
          'isImage': false,
        };
        
        print('TestNotificationPage: Emitting test message: $testMessage');
        
        // Emit the test message to simulate real-time messaging
        widget.apiService.socket?.emit('testMessage', testMessage);
        
        setState(() {
          _notificationCount++;
          _notificationStatus = 'ทดสอบข้อความข้ามห้อง สำเร็จ';
          _lastNotificationTime = DateTime.now().toString();
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('การทดสอบข้อความข้ามห้อง สำเร็จ - ตรวจสอบ logs'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        print('TestNotificationPage: Socket is not connected');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Socket ไม่ได้เชื่อมต่อ'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('TestNotificationPage: Error testing cross-room messaging: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ทดสอบการแจ้งเตือน'),
        backgroundColor: const Color(0xFF004B93),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Icon(
                      _isInitialized ? Icons.check_circle : Icons.error,
                      color: _isInitialized ? Colors.green : Colors.red,
                      size: 48,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isInitialized ? 'การแจ้งเตือนพร้อมใช้งาน' : 'การแจ้งเตือนยังไม่พร้อม',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _isInitialized ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isInitialized ? _testNotification : null,
              icon: const Icon(Icons.notifications),
              label: const Text('ทดสอบการแจ้งเตือนพื้นฐาน'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF004B93),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isInitialized ? _testRoomNotification : null,
              icon: const Icon(Icons.group),
              label: const Text('ทดสอบการแจ้งเตือนห้อง'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF004B93),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isInitialized ? _testBackendMessage : null,
              icon: const Icon(Icons.send),
              label: const Text('ทดสอบการส่งข้อความทดสอบจาก backend'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF004B93),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isInitialized ? _testRealTimeMessage : null,
              icon: const Icon(Icons.message),
              label: const Text('ทดสอบข้อความเรียลไทม'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isInitialized ? _testCrossRoomMessaging : null,
              icon: const Icon(Icons.group),
              label: const Text('ทดสอบข้อความข้ามห้อง'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF004B93),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isInitialized ? _testBadgeCount : null,
              icon: const Icon(Icons.badge),
              label: const Text('ทดสอบ Badge Count (เพิ่ม 1)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isInitialized ? _testBadgeCountReset : null,
              icon: const Icon(Icons.refresh),
              label: const Text('รีเซ็ต Badge Count'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ข้อมูลการทดสอบ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('สถานะการแจ้งเตือน: $_notificationStatus'),
                    const SizedBox(height: 8),
                    Text('จำนวนการแจ้งเตือน: $_notificationCount'),
                    const SizedBox(height: 8),
                    Text('เวลาล่าสุด: $_lastNotificationTime'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'คำแนะนำ:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text('1. กดปุ่มทดสอบการแจ้งเตือน'),
                    Text('2. ตรวจสอบว่ามีการแจ้งเตือนปรากฏหรือไม่'),
                    Text('3. หากไม่มีการแจ้งเตือน ให้ตรวจสอบ:'),
                    Text('   - การตั้งค่า notification permissions'),
                    Text('   - การตั้งค่าแอปในอุปกรณ์'),
                    Text('   - Logs ใน console'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 