import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

class TestCasePage extends StatefulWidget {
  final ApiService apiService;
  
  const TestCasePage({
    super.key,
    required this.apiService,
  });

  @override
  State<TestCasePage> createState() => _TestCasePageState();
}

class _TestCasePageState extends State<TestCasePage> {
  final Map<String, bool> _testResults = {};
  final Map<String, String> _testNotes = {};
  String _currentUser = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _initializeTestCases();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    if (userJson != null) {
      final userData = jsonDecode(userJson);
      setState(() {
        _currentUser = userData['fullNameThai'] ?? 'Unknown User';
      });
    }
  }

  void _initializeTestCases() {
    // Authentication & Login
    _testResults['login_success'] = false;
    _testResults['login_failed'] = false;
    _testResults['logout_success'] = false;
    _testResults['session_persistence'] = false;

    // Navigation
    _testResults['navigation_announcements'] = false;
    _testResults['navigation_groups'] = false;
    _testResults['navigation_chat'] = false;
    _testResults['navigation_profile'] = false;
    _testResults['desktop_sidebar'] = false;
    _testResults['mobile_bottom_nav'] = false;

    // Announcements
    _testResults['announcements_load'] = false;
    _testResults['announcements_scroll'] = false;
    _testResults['announcements_refresh'] = false;
    _testResults['announcements_detail'] = false;
    _testResults['announcements_real_time'] = false;
    _testResults['announcements_web_view'] = false;

    // Group Chat
    _testResults['groups_load'] = false;
    _testResults['groups_join'] = false;
    _testResults['groups_send_message'] = false;
    _testResults['groups_send_image'] = false;
    _testResults['groups_send_file'] = false;
    _testResults['groups_reply_message'] = false;
    _testResults['groups_delete_message'] = false;
    _testResults['groups_real_time'] = false;
    _testResults['groups_unread_badge'] = false;
    _testResults['groups_mark_read'] = false;
    _testResults['groups_settings'] = false;
    _testResults['groups_add_members'] = false;
    _testResults['groups_leave_room'] = false;

    // Direct Messages
    _testResults['dm_list_load'] = false;
    _testResults['dm_start_new'] = false;
    _testResults['dm_send_message'] = false;
    _testResults['dm_send_image'] = false;
    _testResults['dm_send_file'] = false;
    _testResults['dm_reply_message'] = false;
    _testResults['dm_delete_message'] = false;
    _testResults['dm_real_time'] = false;
    _testResults['dm_unread_badge'] = false;
    _testResults['dm_mark_read'] = false;

    // Notifications
    _testResults['notifications_permission'] = false;
    _testResults['notifications_basic'] = false;
    _testResults['notifications_group'] = false;
    _testResults['notifications_dm'] = false;
    _testResults['notifications_background'] = false;
    _testResults['notifications_tap'] = false;
    _testResults['notifications_badge'] = false;

    // Socket & Real-time
    _testResults['socket_connection'] = false;
    _testResults['socket_reconnection'] = false;
    _testResults['socket_room_join'] = false;
    _testResults['socket_room_leave'] = false;
    _testResults['socket_cross_room'] = false;
    _testResults['socket_error_handling'] = false;

    // Profile & Settings
    _testResults['profile_load'] = false;
    _testResults['profile_edit'] = false;
    _testResults['profile_logout'] = false;

    // Performance
    _testResults['performance_loading'] = false;
    _testResults['performance_scroll'] = false;
    _testResults['performance_memory'] = false;
    _testResults['performance_network'] = false;

    // Error Handling
    _testResults['error_network'] = false;
    _testResults['error_server'] = false;
    _testResults['error_timeout'] = false;
    _testResults['error_validation'] = false;

    // UI/UX
    _testResults['ui_responsive'] = false;
    _testResults['ui_theme'] = false;
    _testResults['ui_animations'] = false;
    _testResults['ui_accessibility'] = false;
  }

  void _updateTestResult(String testId, bool result, {String? note}) {
    setState(() {
      _testResults[testId] = result;
      if (note != null) {
        _testNotes[testId] = note;
      }
    });
  }

  void _resetAllTests() {
    setState(() {
      _testResults.clear();
      _testNotes.clear();
      _initializeTestCases();
    });
  }

  Future<void> _exportTestResults() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = <String, dynamic>{};
      for (final entry in _testResults.entries) {
        results[entry.key] = {
          'passed': entry.value,
          'note': _testNotes[entry.key] ?? '',
          'timestamp': DateTime.now().toIso8601String(),
        };
      }

      final summary = {
        'user': _currentUser,
        'total_tests': _testResults.length,
        'passed_tests': _testResults.values.where((v) => v).length,
        'failed_tests': _testResults.values.where((v) => !v).length,
        'test_date': DateTime.now().toIso8601String(),
        'results': results,
      };

      // สร้าง JSON string
      final jsonString = jsonEncode(summary);
      
      // แสดง dialog เลือกวิธีการส่งออก
      if (mounted) {
        _showExportDialog(jsonString);
      }

    } catch (e) {
      print('Error exporting test results: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการส่งออก: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showExportDialog(String jsonString) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('ส่งออกผลการทดสอบ'),
          content: const Text('เลือกวิธีการส่งออกผลการทดสอบ:'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _copyToClipboard(jsonString);
              },
              child: const Text('คัดลอก JSON'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _copyToClipboard(_generateReadableReport());
              },
              child: const Text('คัดลอกรายงาน'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showDetailedResults();
              },
              child: const Text('ดูรายละเอียด'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _printToConsole(jsonString);
              },
              child: const Text('ส่งไป Console'),
            ),
          ],
        );
      },
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ผลการทดสอบถูกคัดลอกไปยัง clipboard แล้ว'),
        backgroundColor: Colors.green,
      ),
    );
  }

  String _generateReadableReport() {
    final passedTests = _testResults.entries.where((e) => e.value).length;
    final failedTests = _testResults.entries.where((e) => !e.value).length;
    final totalTests = _testResults.length;
    final passRate = totalTests > 0 ? (passedTests / totalTests * 100).toStringAsFixed(1) : '0';

    final buffer = StringBuffer();
    buffer.writeln('=== ผลการทดสอบ 12NotifyApp ===');
    buffer.writeln('ผู้ทดสอบ: $_currentUser');
    buffer.writeln('วันที่ทดสอบ: ${DateTime.now().toString().substring(0, 19)}');
    buffer.writeln('');
    buffer.writeln('สรุปผล:');
    buffer.writeln('- จำนวนการทดสอบทั้งหมด: $totalTests');
    buffer.writeln('- ผ่าน: $passedTests (${passRate}%)');
    buffer.writeln('- ไม่ผ่าน: $failedTests');
    buffer.writeln('');
    buffer.writeln('รายละเอียด:');
    buffer.writeln('');

    // จัดกลุ่มตามหมวดหมู่
    final categories = {
      '🔐 Authentication & Login': ['login_success', 'login_failed', 'logout_success', 'session_persistence'],
      '🧭 Navigation': ['navigation_announcements', 'navigation_groups', 'navigation_chat', 'navigation_profile', 'desktop_sidebar', 'mobile_bottom_nav'],
      '📢 Announcements': ['announcements_load', 'announcements_scroll', 'announcements_refresh', 'announcements_detail', 'announcements_real_time', 'announcements_web_view'],
      '👥 Group Chat': ['groups_load', 'groups_join', 'groups_send_message', 'groups_send_image', 'groups_send_file', 'groups_reply_message', 'groups_delete_message', 'groups_real_time', 'groups_unread_badge', 'groups_mark_read', 'groups_settings', 'groups_add_members', 'groups_leave_room'],
      '💬 Direct Messages': ['dm_list_load', 'dm_start_new', 'dm_send_message', 'dm_send_image', 'dm_send_file', 'dm_reply_message', 'dm_delete_message', 'dm_real_time', 'dm_unread_badge', 'dm_mark_read'],
      '🔔 Notifications': ['notifications_permission', 'notifications_basic', 'notifications_group', 'notifications_dm', 'notifications_background', 'notifications_tap', 'notifications_badge'],
      '🔌 Socket & Real-time': ['socket_connection', 'socket_reconnection', 'socket_room_join', 'socket_room_leave', 'socket_cross_room', 'socket_error_handling'],
      '👤 Profile & Settings': ['profile_load', 'profile_edit', 'profile_logout'],
      '⚡ Performance': ['performance_loading', 'performance_scroll', 'performance_memory', 'performance_network'],
      '⚠️ Error Handling': ['error_network', 'error_server', 'error_timeout', 'error_validation'],
      '🎨 UI/UX': ['ui_responsive', 'ui_theme', 'ui_animations', 'ui_accessibility'],
    };

    for (final category in categories.entries) {
      buffer.writeln('${category.key}:');
      for (final testId in category.value) {
        final result = _testResults[testId] ?? false;
        final status = result ? '✅ ผ่าน' : '❌ ไม่ผ่าน';
        final title = _getTestTitle(testId);
        final note = _testNotes[testId];
        
        buffer.write('  $status - $title');
        if (note != null && note.isNotEmpty) {
          buffer.write(' (หมายเหตุ: $note)');
        }
        buffer.writeln();
      }
      buffer.writeln('');
    }

    return buffer.toString();
  }

  void _showDetailedResults() {
    final passedTests = _testResults.entries.where((e) => e.value).length;
    final failedTests = _testResults.entries.where((e) => !e.value).length;
    final totalTests = _testResults.length;
    final passRate = totalTests > 0 ? (passedTests / totalTests * 100).toStringAsFixed(1) : '0';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('สรุปผลการทดสอบ'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('ผู้ทดสอบ: $_currentUser'),
                const SizedBox(height: 8),
                Text('วันที่ทดสอบ: ${DateTime.now().toString().substring(0, 19)}'),
                const SizedBox(height: 16),
                Text('จำนวนการทดสอบทั้งหมด: $totalTests'),
                Text('ผ่าน: $passedTests (${passRate}%)'),
                Text('ไม่ผ่าน: $failedTests'),
                const SizedBox(height: 16),
                const Text('รายละเอียด:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._testResults.entries.map((entry) {
                  final status = entry.value ? '✅ ผ่าน' : '❌ ไม่ผ่าน';
                  final note = _testNotes[entry.key];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$status - ${_getTestTitle(entry.key)}'),
                        if (note != null && note.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Text('หมายเหตุ: $note', 
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ปิด'),
            ),
          ],
        );
      },
    );
  }

  void _printToConsole(String jsonString) {
    print('=== TEST RESULTS EXPORT ===');
    print(jsonString);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ผลการทดสอบถูกส่งไปยัง console แล้ว'),
        backgroundColor: Colors.green,
      ),
    );
  }

  String _getTestTitle(String testId) {
    final titles = {
      'login_success': 'เข้าสู่ระบบสำเร็จ',
      'login_failed': 'เข้าสู่ระบบไม่สำเร็จ',
      'logout_success': 'ออกจากระบบสำเร็จ',
      'session_persistence': 'เก็บ session',
      'navigation_announcements': 'หน้าประกาศ',
      'navigation_groups': 'หน้ากลุ่ม',
      'navigation_chat': 'หน้าแชท',
      'navigation_profile': 'หน้าโปรไฟล์',
      'desktop_sidebar': 'Sidebar (Desktop)',
      'mobile_bottom_nav': 'Bottom Nav (Mobile)',
      'announcements_load': 'โหลดประกาศ',
      'announcements_scroll': 'เลื่อนดูประกาศ',
      'announcements_refresh': 'รีเฟรชประกาศ',
      'announcements_detail': 'ดูรายละเอียด',
      'announcements_real_time': 'เรียลไทม์',
      'announcements_web_view': 'Web View',
      'groups_load': 'โหลดกลุ่ม',
      'groups_join': 'เข้ากลุ่ม',
      'groups_send_message': 'ส่งข้อความ',
      'groups_send_image': 'ส่งรูปภาพ',
      'groups_send_file': 'ส่งไฟล์',
      'groups_reply_message': 'ตอบกลับ',
      'groups_delete_message': 'ลบข้อความ',
      'groups_real_time': 'เรียลไทม์',
      'groups_unread_badge': 'Badge อ่านแล้ว',
      'groups_mark_read': 'ทำเครื่องหมายอ่านแล้ว',
      'groups_settings': 'ตั้งค่ากลุ่ม',
      'groups_add_members': 'เพิ่มสมาชิก',
      'groups_leave_room': 'ออกจากกลุ่ม',
      'dm_list_load': 'โหลดรายการแชท',
      'dm_start_new': 'เริ่มแชทใหม่',
      'dm_send_message': 'ส่งข้อความ',
      'dm_send_image': 'ส่งรูปภาพ',
      'dm_send_file': 'ส่งไฟล์',
      'dm_reply_message': 'ตอบกลับ',
      'dm_delete_message': 'ลบข้อความ',
      'dm_real_time': 'เรียลไทม์',
      'dm_unread_badge': 'Badge อ่านแล้ว',
      'dm_mark_read': 'ทำเครื่องหมายอ่านแล้ว',
      'notifications_permission': 'สิทธิ์การแจ้งเตือน',
      'notifications_basic': 'แจ้งเตือนพื้นฐาน',
      'notifications_group': 'แจ้งเตือนกลุ่ม',
      'notifications_dm': 'แจ้งเตือนแชท',
      'notifications_background': 'แจ้งเตือนพื้นหลัง',
      'notifications_tap': 'แตะแจ้งเตือน',
      'notifications_badge': 'Badge แจ้งเตือน',
      'socket_connection': 'เชื่อมต่อ Socket',
      'socket_reconnection': 'เชื่อมต่อใหม่',
      'socket_room_join': 'เข้ากลุ่ม Socket',
      'socket_room_leave': 'ออกจากกลุ่ม Socket',
      'socket_cross_room': 'ข้ามห้อง',
      'socket_error_handling': 'จัดการข้อผิดพลาด',
      'profile_load': 'โหลดโปรไฟล์',
      'profile_edit': 'แก้ไขโปรไฟล์',
      'profile_logout': 'ออกจากระบบ',
      'performance_loading': 'ความเร็วการโหลด',
      'performance_scroll': 'ความลื่นการเลื่อน',
      'performance_memory': 'การใช้หน่วยความจำ',
      'performance_network': 'ประสิทธิภาพเครือข่าย',
      'error_network': 'ข้อผิดพลาดเครือข่าย',
      'error_server': 'ข้อผิดพลาดเซิร์ฟเวอร์',
      'error_timeout': 'ข้อผิดพลาด Timeout',
      'error_validation': 'ข้อผิดพลาดการตรวจสอบ',
      'ui_responsive': 'Responsive Design',
      'ui_theme': 'ธีม',
      'ui_animations': 'แอนิเมชัน',
      'ui_accessibility': 'การเข้าถึง',
    };
    return titles[testId] ?? testId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Cases - 12NotifyApp'),
        backgroundColor: const Color(0xFF004B93),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetAllTests,
            tooltip: 'รีเซ็ตการทดสอบทั้งหมด',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportTestResults,
            tooltip: 'ส่งออกผลการทดสอบ',
          ),
        ],
      ),
      body: Column(
        children: [
          // Summary Card
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'สรุปการทดสอบ',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildSummaryItem('ทั้งหมด', _testResults.length, Colors.blue),
                      _buildSummaryItem('ผ่าน', _testResults.values.where((v) => v).length, Colors.green),
                      _buildSummaryItem('ไม่ผ่าน', _testResults.values.where((v) => !v).length, Colors.red),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ผู้ทดสอบ: $_currentUser',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          
          // Test Cases Table
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _buildTestCategory('🔐 Authentication & Login', [
                      _buildTestRow('login_success', 'เข้าสู่ระบบสำเร็จ', 'ทดสอบการเข้าสู่ระบบด้วยข้อมูลที่ถูกต้อง'),
                      _buildTestRow('login_failed', 'เข้าสู่ระบบไม่สำเร็จ', 'ทดสอบการเข้าสู่ระบบด้วยข้อมูลที่ไม่ถูกต้อง'),
                      _buildTestRow('logout_success', 'ออกจากระบบสำเร็จ', 'ทดสอบการออกจากระบบ'),
                      _buildTestRow('session_persistence', 'เก็บ session', 'ทดสอบการเก็บ session หลังจากปิดแอพ'),
                    ]),
                    
                    _buildTestCategory('🧭 Navigation', [
                      _buildTestRow('navigation_announcements', 'หน้าประกาศ', 'ทดสอบการนำทางไปหน้าประกาศ'),
                      _buildTestRow('navigation_groups', 'หน้ากลุ่ม', 'ทดสอบการนำทางไปหน้ากลุ่ม'),
                      _buildTestRow('navigation_chat', 'หน้าแชท', 'ทดสอบการนำทางไปหน้าแชท'),
                      _buildTestRow('navigation_profile', 'หน้าโปรไฟล์', 'ทดสอบการนำทางไปหน้าโปรไฟล์'),
                      _buildTestRow('desktop_sidebar', 'Sidebar (Desktop)', 'ทดสอบ Sidebar บน Desktop'),
                      _buildTestRow('mobile_bottom_nav', 'Bottom Nav (Mobile)', 'ทดสอบ Bottom Navigation บน Mobile'),
                    ]),
                    
                    _buildTestCategory('📢 Announcements', [
                      _buildTestRow('announcements_load', 'โหลดประกาศ', 'ทดสอบการโหลดรายการประกาศ'),
                      _buildTestRow('announcements_scroll', 'เลื่อนดูประกาศ', 'ทดสอบการเลื่อนดูประกาศ'),
                      _buildTestRow('announcements_refresh', 'รีเฟรชประกาศ', 'ทดสอบการรีเฟรชรายการประกาศ'),
                      _buildTestRow('announcements_detail', 'ดูรายละเอียด', 'ทดสอบการดูรายละเอียดประกาศ'),
                      _buildTestRow('announcements_real_time', 'เรียลไทม์', 'ทดสอบการรับประกาศใหม่แบบเรียลไทม์'),
                      _buildTestRow('announcements_web_view', 'Web View', 'ทดสอบการเปิดลิงก์ใน Web View'),
                    ]),
                    
                    _buildTestCategory('👥 Group Chat', [
                      _buildTestRow('groups_load', 'โหลดกลุ่ม', 'ทดสอบการโหลดรายการกลุ่ม'),
                      _buildTestRow('groups_join', 'เข้ากลุ่ม', 'ทดสอบการเข้ากลุ่มแชท'),
                      _buildTestRow('groups_send_message', 'ส่งข้อความ', 'ทดสอบการส่งข้อความในกลุ่ม'),
                      _buildTestRow('groups_send_image', 'ส่งรูปภาพ', 'ทดสอบการส่งรูปภาพในกลุ่ม'),
                      _buildTestRow('groups_send_file', 'ส่งไฟล์', 'ทดสอบการส่งไฟล์ในกลุ่ม'),
                      _buildTestRow('groups_reply_message', 'ตอบกลับ', 'ทดสอบการตอบกลับข้อความ'),
                      _buildTestRow('groups_delete_message', 'ลบข้อความ', 'ทดสอบการลบข้อความ'),
                      _buildTestRow('groups_real_time', 'เรียลไทม์', 'ทดสอบการรับข้อความใหม่แบบเรียลไทม์'),
                      _buildTestRow('groups_unread_badge', 'Badge อ่านแล้ว', 'ทดสอบการแสดง badge ข้อความที่ยังไม่อ่าน'),
                      _buildTestRow('groups_mark_read', 'ทำเครื่องหมายอ่านแล้ว', 'ทดสอบการทำเครื่องหมายว่าอ่านแล้ว'),
                      _buildTestRow('groups_settings', 'ตั้งค่ากลุ่ม', 'ทดสอบการตั้งค่ากลุ่ม'),
                      _buildTestRow('groups_add_members', 'เพิ่มสมาชิก', 'ทดสอบการเพิ่มสมาชิกในกลุ่ม'),
                      _buildTestRow('groups_leave_room', 'ออกจากกลุ่ม', 'ทดสอบการออกจากกลุ่ม'),
                    ]),
                    
                    _buildTestCategory('💬 Direct Messages', [
                      _buildTestRow('dm_list_load', 'โหลดรายการแชท', 'ทดสอบการโหลดรายการแชทส่วนตัว'),
                      _buildTestRow('dm_start_new', 'เริ่มแชทใหม่', 'ทดสอบการเริ่มแชทใหม่'),
                      _buildTestRow('dm_send_message', 'ส่งข้อความ', 'ทดสอบการส่งข้อความส่วนตัว'),
                      _buildTestRow('dm_send_image', 'ส่งรูปภาพ', 'ทดสอบการส่งรูปภาพส่วนตัว'),
                      _buildTestRow('dm_send_file', 'ส่งไฟล์', 'ทดสอบการส่งไฟล์ส่วนตัว'),
                      _buildTestRow('dm_reply_message', 'ตอบกลับ', 'ทดสอบการตอบกลับข้อความส่วนตัว'),
                      _buildTestRow('dm_delete_message', 'ลบข้อความ', 'ทดสอบการลบข้อความส่วนตัว'),
                      _buildTestRow('dm_real_time', 'เรียลไทม์', 'ทดสอบการรับข้อความใหม่แบบเรียลไทม์'),
                      _buildTestRow('dm_unread_badge', 'Badge อ่านแล้ว', 'ทดสอบการแสดง badge ข้อความที่ยังไม่อ่าน'),
                      _buildTestRow('dm_mark_read', 'ทำเครื่องหมายอ่านแล้ว', 'ทดสอบการทำเครื่องหมายว่าอ่านแล้ว'),
                    ]),
                    
                    _buildTestCategory('🔔 Notifications', [
                      _buildTestRow('notifications_permission', 'สิทธิ์การแจ้งเตือน', 'ทดสอบการขอสิทธิ์การแจ้งเตือน'),
                      _buildTestRow('notifications_basic', 'แจ้งเตือนพื้นฐาน', 'ทดสอบการแจ้งเตือนพื้นฐาน'),
                      _buildTestRow('notifications_group', 'แจ้งเตือนกลุ่ม', 'ทดสอบการแจ้งเตือนข้อความกลุ่ม'),
                      _buildTestRow('notifications_dm', 'แจ้งเตือนแชท', 'ทดสอบการแจ้งเตือนข้อความส่วนตัว'),
                      _buildTestRow('notifications_background', 'แจ้งเตือนพื้นหลัง', 'ทดสอบการแจ้งเตือนเมื่อแอพอยู่พื้นหลัง'),
                      _buildTestRow('notifications_tap', 'แตะแจ้งเตือน', 'ทดสอบการแตะแจ้งเตือนเพื่อเปิดแอพ'),
                      _buildTestRow('notifications_badge', 'Badge แจ้งเตือน', 'ทดสอบการแสดง badge การแจ้งเตือน'),
                    ]),
                    
                    _buildTestCategory('🔌 Socket & Real-time', [
                      _buildTestRow('socket_connection', 'เชื่อมต่อ Socket', 'ทดสอบการเชื่อมต่อ Socket'),
                      _buildTestRow('socket_reconnection', 'เชื่อมต่อใหม่', 'ทดสอบการเชื่อมต่อ Socket ใหม่'),
                      _buildTestRow('socket_room_join', 'เข้ากลุ่ม Socket', 'ทดสอบการเข้ากลุ่มผ่าน Socket'),
                      _buildTestRow('socket_room_leave', 'ออกจากกลุ่ม Socket', 'ทดสอบการออกจากกลุ่มผ่าน Socket'),
                      _buildTestRow('socket_cross_room', 'ข้ามห้อง', 'ทดสอบการรับข้อความข้ามห้อง'),
                      _buildTestRow('socket_error_handling', 'จัดการข้อผิดพลาด', 'ทดสอบการจัดการข้อผิดพลาด Socket'),
                    ]),
                    
                    _buildTestCategory('👤 Profile & Settings', [
                      _buildTestRow('profile_load', 'โหลดโปรไฟล์', 'ทดสอบการโหลดข้อมูลโปรไฟล์'),
                      _buildTestRow('profile_edit', 'แก้ไขโปรไฟล์', 'ทดสอบการแก้ไขข้อมูลโปรไฟล์'),
                      _buildTestRow('profile_logout', 'ออกจากระบบ', 'ทดสอบการออกจากระบบจากหน้าโปรไฟล์'),
                    ]),
                    
                    _buildTestCategory('⚡ Performance', [
                      _buildTestRow('performance_loading', 'ความเร็วการโหลด', 'ทดสอบความเร็วการโหลดหน้า'),
                      _buildTestRow('performance_scroll', 'ความลื่นการเลื่อน', 'ทดสอบความลื่นของการเลื่อน'),
                      _buildTestRow('performance_memory', 'การใช้หน่วยความจำ', 'ทดสอบการใช้หน่วยความจำ'),
                      _buildTestRow('performance_network', 'ประสิทธิภาพเครือข่าย', 'ทดสอบประสิทธิภาพเครือข่าย'),
                    ]),
                    
                    _buildTestCategory('⚠️ Error Handling', [
                      _buildTestRow('error_network', 'ข้อผิดพลาดเครือข่าย', 'ทดสอบการจัดการข้อผิดพลาดเครือข่าย'),
                      _buildTestRow('error_server', 'ข้อผิดพลาดเซิร์ฟเวอร์', 'ทดสอบการจัดการข้อผิดพลาดเซิร์ฟเวอร์'),
                      _buildTestRow('error_timeout', 'ข้อผิดพลาด Timeout', 'ทดสอบการจัดการข้อผิดพลาด Timeout'),
                      _buildTestRow('error_validation', 'ข้อผิดพลาดการตรวจสอบ', 'ทดสอบการจัดการข้อผิดพลาดการตรวจสอบ'),
                    ]),
                    
                    _buildTestCategory('🎨 UI/UX', [
                      _buildTestRow('ui_responsive', 'Responsive Design', 'ทดสอบการแสดงผลบนหน้าจอต่างๆ'),
                      _buildTestRow('ui_theme', 'ธีม', 'ทดสอบการแสดงผลธีม'),
                      _buildTestRow('ui_animations', 'แอนิเมชัน', 'ทดสอบแอนิเมชันต่างๆ'),
                      _buildTestRow('ui_accessibility', 'การเข้าถึง', 'ทดสอบการเข้าถึงสำหรับผู้พิการ'),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildTestCategory(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF004B93).withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF004B93),
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTestRow(String testId, String title, String description) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.grey[200]!,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Checkbox
          Checkbox(
            value: _testResults[testId] ?? false,
            onChanged: (value) {
              _updateTestResult(testId, value ?? false);
            },
            activeColor: const Color(0xFF004B93),
          ),
          
          // Test info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                if (_testNotes[testId] != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'หมายเหตุ: ${_testNotes[testId]}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue[700],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Status indicator
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (_testResults[testId] ?? false) ? Colors.green : Colors.grey[300],
            ),
          ),
        ],
      ),
    );
  }
} 