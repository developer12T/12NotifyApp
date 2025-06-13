import 'package:flutter/material.dart';
import '../services/background_service_test.dart';

class BackgroundServiceTestPage extends StatefulWidget {
  const BackgroundServiceTestPage({super.key});

  @override
  State<BackgroundServiceTestPage> createState() => _BackgroundServiceTestPageState();
}

class _BackgroundServiceTestPageState extends State<BackgroundServiceTestPage> {
  final BackgroundServiceTest _testService = BackgroundServiceTest();
  String _status = 'ไม่ทราบสถานะ';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _testService.checkBackgroundServiceStatus();
      setState(() {
        _status = 'ตรวจสอบสถานะแล้ว (ดู log)';
      });
    } catch (e) {
      setState(() {
        _status = 'เกิดข้อผิดพลาด: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _startService() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _testService.testStartBackgroundService();
      setState(() {
        _status = 'เริ่มต้น background service แล้ว';
      });
    } catch (e) {
      setState(() {
        _status = 'เกิดข้อผิดพลาด: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testNotification() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _testService.testBackgroundNotification();
      setState(() {
        _status = 'ส่งคำสั่งแสดง notification แล้ว';
      });
    } catch (e) {
      setState(() {
        _status = 'เกิดข้อผิดพลาด: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testSocket() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _testService.testBackgroundSocket();
      setState(() {
        _status = 'ทดสอบ socket แล้ว';
      });
    } catch (e) {
      setState(() {
        _status = 'เกิดข้อผิดพลาด: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _stopService() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _testService.stopBackgroundService();
      setState(() {
        _status = 'หยุด background service แล้ว';
      });
    } catch (e) {
      setState(() {
        _status = 'เกิดข้อผิดพลาด: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ทดสอบ Background Service'),
        backgroundColor: Theme.of(context).colorScheme.primary,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'สถานะ Background Service',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_status),
                    const SizedBox(height: 8),
                    if (_isLoading)
                      const LinearProgressIndicator(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _checkStatus,
              icon: const Icon(Icons.refresh),
              label: const Text('ตรวจสอบสถานะ'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _startService,
              icon: const Icon(Icons.play_arrow),
              label: const Text('เริ่มต้น Background Service'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _testNotification,
              icon: const Icon(Icons.notifications),
              label: const Text('ทดสอบ Notification'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _testSocket,
              icon: const Icon(Icons.wifi),
              label: const Text('ทดสอบ Socket'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _stopService,
              icon: const Icon(Icons.stop),
              label: const Text('หยุด Background Service'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 24),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'คำแนะนำการทดสอบ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '1. กดปุ่ม "เริ่มต้น Background Service" เพื่อเริ่มต้น service\n'
                      '2. กดปุ่ม "ทดสอบ Notification" เพื่อทดสอบการแจ้งเตือน\n'
                      '3. กดปุ่ม "ทดสอบ Socket" เพื่อตรวจสอบการเชื่อมต่อ socket\n'
                      '4. ตรวจสอบ log ใน console เพื่อดูผลลัพธ์\n'
                      '5. ลองปิดแอปและดูว่า notification ยังทำงานหรือไม่',
                    ),
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