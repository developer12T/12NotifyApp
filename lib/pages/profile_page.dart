import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'login_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    if (userJson != null) {
      try {
        setState(() {
          _userData = jsonDecode(userJson);
        });
      } catch (e) {
        print('Error decoding userJson: $e');
        setState(() {
          _userData = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _userData == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  height: 220,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF00569D),  // สีน้ำเงินหลัก
                        Color(0xFF004A85),  // สีน้ำเงินเข้ม
                        Color(0xFF003D6D),  // สีน้ำเงินเข้มมาก
                      ],
                      stops: [0.0, 0.5, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x40000000),
                        blurRadius: 2,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // เพิ่มเอฟเฟกต์แสงเรืองรอง
                        Positioned(
                          top: -50,
                          right: -50,
                          child: Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  Color(0x40FFFFFF),
                                  Color(0x00FFFFFF),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.5),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(3.0),
                            child: (_userData?['imgUrl'] != null && _userData?['imgUrl'] is String && (_userData?['imgUrl'] as String).isNotEmpty)
                                ? Opacity(
                                    opacity: 1,
                                    child: ClipOval(
                                      child: Image.network(
                                        _userData!['imgUrl'],
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Image.asset(
                                            'assets/images/no-photo-icon-22.png',
                                            width: 100,
                                            height: 100,
                                            fit: BoxFit.cover,
                                          );
                                        },
                                      ),
                                    ),
                                  )
                                : Opacity(
                                    opacity: 1,
                                    child: ClipOval(
                                      child: Image.asset(
                                        'assets/images/no-photo-icon-22.png',
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(12.0),
                    children: [
                      _buildInfoRow(Icons.badge, 'รหัสพนักงาน', _userData!['employeeID'] ?? '-'),
                      _buildInfoRow(Icons.person, 'ชื่อผู้ใช้งาน', _userData!['userName'] ?? '-'),
                      _buildInfoRow(Icons.translate, 'ชื่อ-นามสกุล (อังกฤษ)', _userData!['fullName'] ?? '-'),
                      _buildInfoRow(Icons.language, 'ชื่อ-นามสกุล (ไทย)', _userData!['fullNameThai'] ?? '-'),
                      _buildInfoRow(Icons.email, 'อีเมล', _userData!['mail'] ?? '-'),
                      _buildInfoRow(Icons.work, 'ตำแหน่ง', _userData!['positon'] ?? '-'),
                      _buildInfoRow(Icons.business, 'แผนก', _userData!['department'] ?? '-'),
                      _buildInfoRow(Icons.business_center, 'บริษัท', _userData!['company'] ?? '-'),
                      // const SizedBox(height: 20),
                      _buildLogoutButton(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E6ED)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF00569D)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00569D),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF3A3A3A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      child: InkWell(
        onTap: _showLogoutConfirmation,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE0E6ED)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.logout,
                color: Colors.red[600],
                size: 20,
              ),
              const SizedBox(width: 4),
              Text(
                'ออกจากระบบ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red[600],
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.logout,
                color: Colors.red[600],
                size: 16,
              ),
              const SizedBox(width: 8),
              const Text(
                'ยืนยันการออกจากระบบ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          content: const Text(
            'คุณต้องการออกจากระบบหรือไม่?',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'ยกเลิก',
                style: TextStyle(
                  color: Color(0xFF00569D),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _logout();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'ออกจากระบบ',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _logout() async {
    try {
      // ล้างข้อมูลผู้ใช้จาก SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      
      // นำผู้ใช้กลับไปหน้า login
      if (mounted) {
        Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => LoginPage()),
            );
      }
    } catch (e) {
      print('Error during logout: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('เกิดข้อผิดพลาดในการออกจากระบบ'),
            backgroundColor: Colors.red[600],
          ),
        );
      }
    }
  }
} 