import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/noti_service.dart';
import 'announcement_detail_page.dart';

class AnnouncementsPage extends StatefulWidget {
  final Function(bool)? onPageVisibilityChanged;
  final bool Function()? isInAnnouncementsPage;
  final bool Function()? isAppInForeground;

  const AnnouncementsPage({
    Key? key,
    this.onPageVisibilityChanged,
    this.isInAnnouncementsPage,
    this.isAppInForeground,
  }) : super(key: key);

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  List<dynamic> announcements = [];
  bool isLoading = true;
  String? errorMessage;
  int currentPage = 1;
  int totalPages = 1;
  final ScrollController _scrollController = ScrollController();
  final SocketService _socketService = SocketService();
  final NotiService _notiService = NotiService();
  bool _isPageVisible = false; // Track page visibility

  @override
  void initState() {
    super.initState();
    print('AnnouncementsPage: initState called');
    _isPageVisible = true; // Set page as visible
    _initializeServices();
    fetchAnnouncements();
    _setupScrollListener();
    
    // Notify that announcements page is visible
    widget.onPageVisibilityChanged?.call(true);
  }

  Future<void> _initializeServices() async {
    print('AnnouncementsPage: _initializeServices started');
    try {
      await _notiService.initNotification();
      print('AnnouncementsPage: NotiService initialized');
      
      // Check if socket is already connected
      if (!_socketService.socket.connected) {
        await _socketService.connect();
        print('AnnouncementsPage: SocketService connected');
      } else {
        print('AnnouncementsPage: SocketService already connected');
      }
      
      _setupSocketConnection();
      print('AnnouncementsPage: Socket connection setup completed');
    } catch (e) {
      print('AnnouncementsPage: Error in _initializeServices: $e');
      print('AnnouncementsPage: Stack trace: ${StackTrace.current}');
    }
  }

  void _setupSocketConnection() {
    print('AnnouncementsPage: Setting up socket connection');
    print('AnnouncementsPage: Socket connected: ${_socketService.socket.connected}');
    print('AnnouncementsPage: Socket ID: ${_socketService.socket.id}');
    
    // Test the subscription
    // _socketService.testAnnouncementsSubscription();
    
    // Test notification service
    // _socketService.testNotificationService();
    
    // Test background notification
    // _socketService.testBackgroundNotification();
    
    _socketService.onNewAnnouncement(
      (data) {
        print('AnnouncementsPage: Received new announcement data: $data');
        // ตรวจสอบและปรับโครงสร้างข้อมูล
        if (data['createdByUser'] != null) {
          data['createdBy'] = data['createdByUser'];
        }
        setState(() {
          announcements.insert(0, data);
          print('AnnouncementsPage: Added new announcement to list. Total: ${announcements.length}');
        });
      },
      isInAnnouncementsPage: widget.isInAnnouncementsPage ?? (() => _isPageVisible), // Use callback from MainNavigation
      isAppInForeground: widget.isAppInForeground ?? (() => true), // Use callback from MainNavigation
    );
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
        if (currentPage < totalPages) {
          fetchAnnouncements(page: currentPage + 1);
        }
      }
    });
  }

  Future<void> fetchAnnouncements({int page = 1}) async {
    if (page == 1) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    }

    try {
      final url = '${ApiService.baseUrl}/api/announcements?page=$page';
      print('AnnouncementsPage: Fetching announcements from: $url');
      final response = await http.get(Uri.parse(url));
      print('AnnouncementsPage: API response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(json.decode(response.body));
        setState(() {
          if (page == 1) {
            announcements = data['announcements'];
          } else {
            announcements.addAll(data['announcements']);
          }
          currentPage = data['pagination']['currentPage'];
          totalPages = data['pagination']['totalPages'];
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'ไม่สามารถโหลดประกาศได้';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'เกิดข้อผิดพลาดในการเชื่อมต่อ';
        isLoading = false;
      });
    }
  }

  Future<void> _onRefresh() async {
    setState(() {
      currentPage = 1;
      totalPages = 1;
    });
    await fetchAnnouncements();
  }

  String formatDate(String dateString) {
    try {
      // แปลง ISO string เป็น DateTime (UTC)
      final date = DateTime.parse(dateString);
      // ใช้เวลาปัจจุบันเป็นเวลาไทย (UTC+7)
      final now = DateTime.now().toUtc().add(const Duration(hours: 7));
      final difference = now.difference(date);

      String relativeTime;
      if (difference.inDays == 0) {
        if (difference.inHours == 0) {
          if (difference.inMinutes == 0) {
            relativeTime = 'เพิ่งประกาศ';
          } else {
            relativeTime = '${difference.inMinutes} นาทีที่แล้ว';
          }
        } else {
          final hours = difference.inHours.abs();
          relativeTime = '$hours ชั่วโมงที่แล้ว';
        }
      } else if (difference.inDays == 1) {
        relativeTime = 'เมื่อวานนี้';
      } else if (difference.inDays < 7) {
        final days = difference.inDays.abs();
        relativeTime = '$days วันที่แล้ว';
      } else {
        final days = difference.inDays.abs();
        relativeTime = '$days วันที่แล้ว';
      }

      // แปลงเดือนเป็นภาษาไทย
      final thaiMonths = {
        1: 'มกราคม',
        2: 'กุมภาพันธ์',
        3: 'มีนาคม',
        4: 'เมษายน',
        5: 'พฤษภาคม',
        6: 'มิถุนายน',
        7: 'กรกฎาคม',
        8: 'สิงหาคม',
        9: 'กันยายน',
        10: 'ตุลาคม',
        11: 'พฤศจิกายน',
        12: 'ธันวาคม'
      };

      // แสดงเวลาที่แน่นอนในรูปแบบ UTC
      final day = date.day;
      final month = thaiMonths[date.month]!;
      final year = date.year + 543;
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');

      return '$relativeTime ($day $month $year $hour:$minute น.)';
    } catch (e) {
      return dateString;
    }
  }

  bool isNewAnnouncement(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      return now.difference(date).inHours < 24;
    } catch (e) {
      return false;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _socketService.offNewAnnouncement();
    _socketService.disconnect();
    
    _isPageVisible = false; // Set page as not visible
    // Notify that announcements page is hidden
    widget.onPageVisibilityChanged?.call(false);
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading && announcements.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null && announcements.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(errorMessage!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => fetchAnnouncements(),
              child: const Text('ลองใหม่'),
            ),
          ],
        ),
      );
    }

    // if (announcements.isEmpty) {
    //   return Center(
    //     child: Column(
    //       mainAxisAlignment: MainAxisAlignment.center,
    //       children: [
    //         Icon(
    //           Icons.announcement_outlined,
    //           size: 64,
    //           color: Colors.grey[400],
    //         ),
    //         const SizedBox(height: 16),
    //         Text(
    //           'ไม่มีประกาศหรือข่าวสาร ณ ขณะนี้',
    //           style: Theme.of(context).textTheme.titleMedium?.copyWith(
    //             color: Colors.grey[600],
    //           ),
    //         ),
    //       ],
    //     ),
    //   );
    // }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        return RefreshIndicator(
          onRefresh: _onRefresh,
          child: GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            controller: _scrollController,
            padding: const EdgeInsets.all(16.0),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isWide ? 2 : 1,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.2, // ปรับตามดีไซน์
            ),
            itemCount: announcements.length + (currentPage < totalPages ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == announcements.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              final announcement = announcements[index];
              final isNew = isNewAnnouncement(announcement['createdAt']);
              
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                child: Card(
                  elevation: 4,
                  shadowColor: Colors.black.withOpacity(1),
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: isNew 
                      ? BorderSide(color: Theme.of(context).primaryColor.withOpacity(0.5), width: 1)
                      : BorderSide.none,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AnnouncementDetailPage(
                            announcement: Map<String, dynamic>.from(announcement),
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      announcement['title'],
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(context).primaryColor,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      formatDate(announcement['createdAt']),
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.grey[600],
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isNew)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'ใหม่',
                                    style: TextStyle(
                                      color: Theme.of(context).primaryColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (announcement['imageUrl'] != null && announcement['imageUrl'].toString().isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                '${ApiService.baseUrl}${announcement['imageUrl']}',
                                fit: BoxFit.cover,
                                height: 120,
                                width: double.infinity,
                              ),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            announcement['content'],
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              height: 1.5,
                              color: Colors.grey[800],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'โดย: ${_getCreatorName(Map<String, dynamic>.from(announcement))}',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w300,
                                  fontSize: 10,
                                ),
                              ),
                              if (_getDepartment(Map<String, dynamic>.from(announcement)) != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _getDepartment(Map<String, dynamic>.from(announcement))!.length > 16 
                                        ? '${_getDepartment(Map<String, dynamic>.from(announcement))!.substring(0, 16)}...'
                                        : _getDepartment(Map<String, dynamic>.from(announcement))!,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _getCreatorName(Map<String, dynamic> announcement) {
    if (announcement['createdBy'] == null) return 'Unknown';
    if (announcement['createdBy'] is Map) {
      return announcement['createdBy']['fullNameThai'] ?? 
             announcement['createdBy']['fullName'] ?? 
             'Unknown';
    }
    return announcement['createdBy'].toString();
  }

  String? _getDepartment(Map<String, dynamic> announcement) {
    if (announcement['createdBy'] == null) return null;
    if (announcement['createdBy'] is Map) {
      return announcement['createdBy']['department']?.toString();
    }
    return announcement['department']?.toString();
  }
} 