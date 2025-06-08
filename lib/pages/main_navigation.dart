import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
// import 'package:package_info_plus/package_info_plus.dart';  // Commented out as we use hardcoded version
import 'announcements_page.dart';
import 'room_page.dart';
import 'direct_message_list_page.dart';
import 'profile_page.dart';
import '../services/api_service.dart';
import '../components/side_navigation.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({Key? key}) : super(key: key);

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;
  String _userName = '';
  String _version = 'alpha-test 1.0.0';  // Hardcoded version
  final ApiService _apiService = ApiService();
  // Add keys for each page
  final List<GlobalKey<State<StatefulWidget>>> _pageKeys = [
    GlobalKey<State<StatefulWidget>>(),
    GlobalKey<State<StatefulWidget>>(),
    GlobalKey<State<StatefulWidget>>(),
    GlobalKey<State<StatefulWidget>>(),
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
    // _loadVersion();  // Commented out as we use hardcoded version
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    if (userJson != null) {
      final userData = jsonDecode(userJson);
      setState(() {
        _userName = userData['fullNameThai'] ?? '';
      });
    }
  }

  // Future<void> _loadVersion() async {  // Commented out as we use hardcoded version
  //   final packageInfo = await PackageInfo.fromPlatform();
  //   setState(() {
  //     _version = packageInfo.version;
  //   });
  // }

  String get _title {
    switch (_selectedIndex) {
      case 0:
        return 'ประกาศ';
      case 1:
        return 'กลุ่ม';
      case 2:
        return 'แชท';
      case 3:
        return 'ข้อมูลส่วนตัว';
      default:
        return 'NotiOneTwo';
    }
  }

  void _onItemTapped(int index) {
    if (_selectedIndex != index) {
      setState(() {
        _selectedIndex = index;
      });
      
      // Force rebuild the selected page by recreating its key
      _pageKeys[index] = GlobalKey<State<StatefulWidget>>();
    }
  }

  Future<void> _logout() async {
    final shouldLogout = await showModalBottomSheet<bool>(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.logout, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              const Text(
                'ออกจากระบบ',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'คุณต้องการออกจากระบบใช่หรือไม่?',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('ยืนยัน'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black,
                        side: BorderSide(color: Colors.grey.shade400),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('ยกเลิก'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (shouldLogout == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      await prefs.remove('user');
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  void dispose() {
    _apiService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: AppBar(
            backgroundColor: _selectedIndex == 3 ? const Color(0xFF00569D) : Colors.white,
            elevation: 0,
            title: Row(
              children: [
                // Image.asset('assets/images/logo-xl-login.png', height: 24),
                const SizedBox(width: 12),
                Text(
                  _selectedIndex == 0
                      ? 'ข่าวสาร/ประกาศ'
                       : _selectedIndex == 1
                              ? 'กลุ่มของคุณ'
                      : _selectedIndex == 2
                          ? 'แชทของคุณ'
                          : 'ข้อมูลของคุณ',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: _selectedIndex == 3 ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.logout, color: _selectedIndex == 3 ? Colors.white : Colors.black),
                onPressed: _logout,
              ),
            ],
          ),
        ),
      ),
      body: Row(
        children: [
          if (isDesktop) SideNavigation(
            selectedIndex: _selectedIndex,
            onItemTapped: _onItemTapped,
            userName: _userName,
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                AnnouncementsPage(key: _pageKeys[0]),
                RoomPage(key: _pageKeys[1], apiService: _apiService),
                DirectMessageListPage(
                  key: _pageKeys[2],
                  apiService: _apiService,
                ),
                ProfilePage(key: _pageKeys[3]),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isDesktop ? null : Container(
        decoration: BoxDecoration(
          color: Colors.white,
          // borderRadius: const BorderRadius.only(
          //   topLeft: Radius.circular(24),
          //   topRight: Radius.circular(24),
          // ),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 3,
              offset: Offset(0, -1),
            ),
          ],
        ),
        child: ClipRRect(
          // borderRadius: const BorderRadius.only(
          //   topLeft: Radius.circular(24),
          //   topRight: Radius.circular(24),
          // ),
          child: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            elevation: 0,
            selectedItemColor: const Color(0xFF004B93),
            unselectedItemColor: Colors.black,
            iconSize: 26,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 10),
            showUnselectedLabels: true,
            items: const <BottomNavigationBarItem>[
              BottomNavigationBarItem(
                icon: Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Icon(Icons.notifications_active),
                  // child: Icon(Icons.campaign_rounded),
                ),
                label: 'ประกาศ',
              ),
              BottomNavigationBarItem(
                icon: Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Icon(Icons.people_alt),
                  // child: Icon(Icons.group_rounded),
                ),
                label: 'กลุ่ม',
              ),
               BottomNavigationBarItem(
                icon: Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Icon(Icons.question_answer),
                ),
                label: 'แชท',
              ),
              BottomNavigationBarItem(
                icon: Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Icon(Icons.account_circle_rounded),
                ),
                label: 'ข้อมูลส่วนตัว',
              ),
            ],
            currentIndex: _selectedIndex,
            onTap: _onItemTapped,
          ),
        ),
      ),
    );
  }
} 