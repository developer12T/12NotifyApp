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
  bool _isSocketSetup = false; // Track if socket is already setup

  @override
  void initState() {
    super.initState();
    print('AnnouncementsPage: initState called');
    _isPageVisible = true; // Set page as visible
    _isSocketSetup = false; // Reset socket setup flag
    
    _initializeServices();
    fetchAnnouncements();
    _setupScrollListener();
    
    // Notify that announcements page is visible
    widget.onPageVisibilityChanged?.call(true);
    print('AnnouncementsPage: initState completed');
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
    if (_isSocketSetup) {
      print('AnnouncementsPage: Socket already setup, skipping...');
      return;
    }
    
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
        
        // Handle different data structures
        Map<String, dynamic> announcementData;
        
        if (data is List && data.isNotEmpty) {
          // If data is a list, get the first item
          final firstItem = data[0];
          if (firstItem is Map<String, dynamic>) {
            if (firstItem['data'] != null) {
              // If data is nested under 'data' key
              announcementData = Map<String, dynamic>.from(firstItem['data']);
            } else {
              // If data is directly available
              announcementData = Map<String, dynamic>.from(firstItem);
            }
          } else {
            print('AnnouncementsPage: Invalid data structure in list');
            return;
          }
        } else if (data is Map<String, dynamic>) {
          if (data['data'] != null) {
            // If data is nested under 'data' key
            announcementData = Map<String, dynamic>.from(data['data']);
          } else {
            // If data is directly available
            announcementData = Map<String, dynamic>.from(data);
          }
        } else {
          print('AnnouncementsPage: Invalid data type: ${data.runtimeType}');
          return;
        }
        
        // Handle createdBy field
        if (announcementData['createdByUser'] != null) {
          announcementData['createdBy'] = announcementData['createdByUser'];
        }
        
        print('AnnouncementsPage: Processed announcement data: $announcementData');
        print('AnnouncementsPage: Current announcements count: ${announcements.length}');
        
        // ตรวจสอบว่าประกาศนี้มีอยู่แล้วหรือไม่ เพื่อป้องกันการซ้ำ
        final announcementId = announcementData['id']?.toString();
        final existingAnnouncement = announcements.any((announcement) => 
          announcement['id']?.toString() == announcementId
        );
        
        if (!existingAnnouncement) {
          setState(() {
            isLoading = false; 
            announcements.insert(0, announcementData);
            print('AnnouncementsPage: Added new announcement to list. Total: ${announcements.length}');
          });
          
          // ไม่ต้องทดสอบการแจ้งเตือนที่นี่ เพราะ SocketService จะจัดการแล้ว
          // _testNotificationForNewAnnouncement(announcementData);
        } else {
          print('AnnouncementsPage: Announcement already exists, skipping...');
          print('AnnouncementsPage: Duplicate announcement ID: $announcementId');
        }
      },
      isInAnnouncementsPage: widget.isInAnnouncementsPage ?? (() => _isPageVisible), // Use callback from MainNavigation
      isAppInForeground: widget.isAppInForeground ?? (() => true), // Use callback from MainNavigation
    );
    
    _isSocketSetup = true;
    print('AnnouncementsPage: Socket setup completed');
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
    print('AnnouncementsPage: dispose called');
    _scrollController.dispose();
    
    // Cleanup socket listeners
    if (_isSocketSetup) {
      _socketService.offNewAnnouncement();
      _isSocketSetup = false;
      print('AnnouncementsPage: Socket listeners cleaned up');
    }
    
    // Don't disconnect the socket here as it might be used by other pages
    // _socketService.disconnect();
    
    _isPageVisible = false; // Set page as not visible
    
    // Notify that announcements page is hidden
    widget.onPageVisibilityChanged?.call(false);
    
    print('AnnouncementsPage: dispose completed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading && announcements.isEmpty) {
      return Scaffold(
        body: const Center(child: CircularProgressIndicator()),
        // floatingActionButton: FloatingActionButton.extended(
        //   onPressed: () {
        //     showModalBottomSheet(
        //       context: context,
        //       builder: (context) => Container(
        //         padding: const EdgeInsets.all(16),
        //         child: Column(
        //           mainAxisSize: MainAxisSize.min,
        //           children: [
        //             const Text(
        //               'ทดสอบการแจ้งเตือน',
        //               style: TextStyle(
        //                 fontSize: 18,
        //                 fontWeight: FontWeight.bold,
        //               ),
        //             ),
        //             const SizedBox(height: 16),
        //             Row(
        //               children: [
        //                 Expanded(
        //                   child: ElevatedButton.icon(
        //                     onPressed: () {
        //                       Navigator.pop(context);
        //                       _testNotification();
        //                     },
        //                     icon: const Icon(Icons.notifications),
        //                     label: const Text('ทดสอบ NotiService'),
        //                   ),
        //                 ),
        //                 const SizedBox(width: 8),
        //                 Expanded(
        //                   child: ElevatedButton.icon(
        //                     onPressed: () {
        //                       Navigator.pop(context);
        //                       _testSocketNotification();
        //                     },
        //                     icon: const Icon(Icons.wifi),
        //                     label: const Text('ทดสอบ Socket'),
        //                   ),
        //                 ),
        //               ],
        //             ),
        //             const SizedBox(height: 8),
        //             Row(
        //               children: [
        //                 Expanded(
        //                   child: ElevatedButton.icon(
        //                     onPressed: () {
        //                       Navigator.pop(context);
        //                       _testNotiServiceDirectly();
        //                     },
        //                     icon: const Icon(Icons.notification_add),
        //                     label: const Text('ทดสอบ NotiService โดยตรง'),
        //                   ),
        //                 ),
        //               ],
        //             ),
        //           ],
        //         ),
        //       ),
        //     );
        //   },
        //   icon: const Icon(Icons.notifications),
        //   label: const Text('ทดสอบ'),
        // ),
      );
    }

    if (errorMessage != null && announcements.isEmpty) {
      return Scaffold(
        body: Center(
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
        ),
        // floatingActionButton: FloatingActionButton.extended(
        //   onPressed: () {
        //     showModalBottomSheet(
        //       context: context,
        //       builder: (context) => Container(
        //         padding: const EdgeInsets.all(16),
        //         child: Column(
        //           mainAxisSize: MainAxisSize.min,
        //           children: [
        //             const Text(
        //               'ทดสอบการแจ้งเตือน',
        //               style: TextStyle(
        //                 fontSize: 18,
        //                 fontWeight: FontWeight.bold,
        //               ),
        //             ),
        //             const SizedBox(height: 16),
        //             Row(
        //               children: [
        //                 Expanded(
        //                   child: ElevatedButton.icon(
        //                     onPressed: () {
        //                       Navigator.pop(context);
        //                       _testNotification();
        //                     },
        //                     icon: const Icon(Icons.notifications),
        //                     label: const Text('ทดสอบ NotiService'),
        //                   ),
        //                 ),
        //                 const SizedBox(width: 8),
        //                 Expanded(
        //                   child: ElevatedButton.icon(
        //                     onPressed: () {
        //                       Navigator.pop(context);
        //                       _testSocketNotification();
        //                     },
        //                     icon: const Icon(Icons.wifi),
        //                     label: const Text('ทดสอบ Socket'),
        //                   ),
        //                 ),
        //               ],
        //             ),
        //           ],
        //         ),
        //       ),
        //     );
        //   },
        //   icon: const Icon(Icons.notifications),
        //   label: const Text('ทดสอบ'),
        // ),
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
        return Scaffold(
          body: RefreshIndicator(
            onRefresh: _onRefresh,
            child: GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              controller: _scrollController,
              padding: const EdgeInsets.all(16.0),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: isWide ? 300 : double.infinity,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.9,
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
                        padding: const EdgeInsets.all(12.0),
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
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
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
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'ใหม่',
                                      style: TextStyle(
                                        color: Theme.of(context).primaryColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (announcement['imageUrl'] != null && announcement['imageUrl'].toString().isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  '${ApiService.baseUrl}${announcement['imageUrl']}',
                                  fit: BoxFit.cover,
                                  height: 80,
                                  width: double.infinity,
                                ),
                              ),
                            const SizedBox(height: 6),
                            Expanded(
                              child: Text(
                                announcement['content'],
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  height: 1.3,
                                  color: Colors.grey[800],
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'โดย: ${_getCreatorName(Map<String, dynamic>.from(announcement))}',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w300,
                                      fontSize: 9,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_getDepartment(Map<String, dynamic>.from(announcement)) != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      _getDepartment(Map<String, dynamic>.from(announcement))!.length > 10 
                                          ? '${_getDepartment(Map<String, dynamic>.from(announcement))!.substring(0, 10)}...'
                                          : _getDepartment(Map<String, dynamic>.from(announcement))!,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.grey[700],
                                        fontSize: 9,
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
          ),
          // floatingActionButton: FloatingActionButton.extended(
          //   onPressed: () {
          //     showModalBottomSheet(
          //       context: context,
          //       builder: (context) => Container(
          //         padding: const EdgeInsets.all(16),
          //         child: Column(
          //           mainAxisSize: MainAxisSize.min,
          //           children: [
          //             const Text(
          //               'ทดสอบการแจ้งเตือน',
          //               style: TextStyle(
          //                 fontSize: 18,
          //                 fontWeight: FontWeight.bold,
          //               ),
          //             ),
          //             const SizedBox(height: 16),
          //             Row(
          //               children: [
          //                 Expanded(
          //                   child: ElevatedButton.icon(
          //                     onPressed: () {
          //                       Navigator.pop(context);
          //                       _testNotification();
          //                     },
          //                     icon: const Icon(Icons.notifications),
          //                     label: const Text('ทดสอบ NotiService'),
          //                   ),
          //                 ),
          //                 const SizedBox(width: 8),
          //                 Expanded(
          //                   child: ElevatedButton.icon(
          //                     onPressed: () {
          //                       Navigator.pop(context);
          //                       _testSocketNotification();
          //                     },
          //                     icon: const Icon(Icons.wifi),
          //                     label: const Text('ทดสอบ Socket'),
          //                   ),
          //                 ),
          //               ],
          //             ),
          //           ],
          //         ),
          //       ),
          //     );
          //   },
          //   icon: const Icon(Icons.notifications),
          //   label: const Text('ทดสอบ'),
          // ),
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

  Future<void> _testNotification() async {
    print('AnnouncementsPage: Testing notification...');
    try {
      await _notiService.showNotification(
        title: 'ทดสอบการแจ้งเตือนจาก AnnouncementsPage',
        body: 'นี่คือการทดสอบระบบการแจ้งเตือนจากหน้า Announcements',
        payload: 'test_from_announcements',
      );
      print('AnnouncementsPage: Test notification sent successfully');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('การแจ้งเตือนถูกส่งแล้ว'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('AnnouncementsPage: Error sending test notification: $e');
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

  Future<void> _testSocketNotification() async {
    print('AnnouncementsPage: Testing socket notification...');
    try {
      await _socketService.testAnnouncementNotification();
      print('AnnouncementsPage: Socket test notification sent successfully');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('การแจ้งเตือนจาก Socket ถูกส่งแล้ว'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      print('AnnouncementsPage: Error sending socket test notification: $e');
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

  Future<void> _testNotiServiceDirectly() async {
    print('AnnouncementsPage: Testing NotiService directly...');
    try {
      // ทดสอบการแจ้งเตือนโดยตรงจาก NotiService
      await _notiService.showNotification(
        title: 'ทดสอบ NotiService โดยตรง',
        body: 'นี่คือการทดสอบ NotiService โดยตรงจาก AnnouncementsPage',
        payload: 'direct_noti_test',
      );
      print('AnnouncementsPage: Direct NotiService test sent successfully');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('การแจ้งเตือนจาก NotiService ถูกส่งแล้ว'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('AnnouncementsPage: Error sending direct NotiService test: $e');
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
} 