import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'package:marquee/marquee.dart';
import 'loading_page.dart';
import 'main_navigation.dart';
import '../services/fcm_service.dart';
import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String _errorMessage = '';
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      // Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      
      // Try to get version from API
      final versionInfo = await ApiService.fetchAppVersionInfo();
      if (versionInfo != null && versionInfo['latest_version'] != null) {
        setState(() {
          _version = 'v${versionInfo['latest_version']}';
        });
      } else {
        // Fallback to current app version
        setState(() {
          _version = 'v$currentVersion';
        });
      }
    } catch (e) {
      print('Error loading version: $e');
      // Fallback to a default version
      setState(() {
        _version = 'v1.0.0';
      });
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': _usernameController.text,
          'password': _passwordController.text,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        // เก็บข้อมูลผู้ใช้ทั้งหมด (data['data'] เป็น object ไม่ใช่ list)
        final userData = {
          'employeeID': data['data']['employeeID'],
          'userName': data['data']['userName'],
          'firstName': data['data']['firstName'],
          'lastName': data['data']['lastName'],
          'fullName': data['data']['fullName'],
          'fullNameThai': data['data']['fullNameThai'],
          'mail': data['data']['mail'],
          'imgUrl': data['data']['imgUrl'],
          'positon': data['data']['positon'],
          'department': data['data']['department'],
          'company': data['data']['company'],
          'status': data['data']['status']
        };
        
        await prefs.setString('user', jsonEncode(userData));

      if(Platform.isAndroid){
        // Register FCM token after login
        await FCMService.registerFCMToken();
        FCMService.listenFCMTokenRefresh();

      }
        if (mounted) {
          Navigator.pushReplacement(
    context,
    MaterialPageRoute(builder: (context) => MainNavigation()),
          );
        }
      } else {
        final error = jsonDecode(response.body);
        String errorMessage = 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง';
        
        // Check if there's a specific error message from the server
        if (error['message'] != null) {
          errorMessage = error['message'];
        }
        
        setState(() {
          _errorMessage = errorMessage;
        });
        
        // Show SnackBar for better visibility
        if (mounted) {
          // ScaffoldMessenger.of(context).showSnackBar(
          //   SnackBar(
          //     content: Text(errorMessage),
          //     backgroundColor: Colors.red,
          //     behavior: SnackBarBehavior.floating,
          //     shape: RoundedRectangleBorder(
          //       borderRadius: BorderRadius.circular(8),
          //     ),
          //     duration: Duration(seconds: 3),
          //   ),
          // );
        }
      }
    } catch (e) {
      setState(() {
        String errorMsg = 'เกิดข้อผิดพลาดในการเชื่อมต่อ';
        
        if (e.toString().contains('SocketException')) {
          errorMsg = 'ไม่สามารถเชื่อมต่อกับเซิร์ฟเวอร์ได้ กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ต';
        } else if (e.toString().contains('TimeoutException')) {
          errorMsg = 'การเชื่อมต่อใช้เวลานานเกินไป กรุณาลองใหม่อีกครั้ง';
        } else if (e.toString().contains('HandshakeException')) {
          errorMsg = 'เกิดข้อผิดพลาดในการเชื่อมต่อที่ปลอดภัย กรุณาตรวจสอบการตั้งค่าเครือข่าย';
        } else {
          errorMsg = 'เกิดข้อผิดพลาดในการเชื่อมต่อ: ${e.toString()}';
        }
        
        _errorMessage = errorMsg;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      resizeToAvoidBottomInset: true,
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/logo-onetwo.png',
                  height: 140,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 24),
                const Text(
                  '12Chat',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF004B93),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 16,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _usernameController,
                          onChanged: (value) {
                            // Clear error message when user starts typing
                            if (_errorMessage.isNotEmpty) {
                              setState(() {
                                _errorMessage = '';
                              });
                            }
                          },
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.person),
                            labelText: 'ชื่อผู้ใช้งาน',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(12)),
                            ),
                            filled: true,
                            fillColor: Color(0xFFF6F8FB),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'กรุณากรอกชื่อผู้ใช้งาน';
                            }
                            return null;
                          },
                        ), 
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          onChanged: (value) {
                            // Clear error message when user starts typing
                            if (_errorMessage.isNotEmpty) {
                              setState(() {
                                _errorMessage = '';
                              });
                            }
                          },
                          decoration: InputDecoration(
                            prefixIcon: Icon(Icons.lock),
                            labelText: 'รหัสผ่าน',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(12)),
                            ),
                            filled: true,
                            fillColor: Color(0xFFF6F8FB),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'กรุณากรอกรหัสผ่าน';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        if (_errorMessage.isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              border: Border.all(color: Colors.red.shade200),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: Colors.red.shade600,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage,
                                    style: TextStyle(
                                      color: Colors.red.shade700,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF004B93),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 4,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Text(
                                    'เข้าสู่ระบบ',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              'assets/images/logo-fplus.png',
                              height: 16,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Copyright One Two Trading Co., Ltd. All rights reserved. $_version',   
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
