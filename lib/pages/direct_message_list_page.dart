import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/api_service.dart';
import 'direct_message_page.dart';
import 'select_user_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class DirectMessageListPage extends StatefulWidget {
  final ApiService apiService;

  const DirectMessageListPage({super.key, required this.apiService});

  @override
  State<DirectMessageListPage> createState() => _DirectMessageListPageState();
}

class _DirectMessageListPageState extends State<DirectMessageListPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  List<Map<String, dynamic>> conversations = [];
  String? currentUserId;
  bool isLoading = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late IO.Socket socket;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
    _initializeSocket();
    loadCurrentUser();
  }

  void _initializeSocket() {
    socket = IO.io(ApiService.baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });

    socket.onConnect((_) {
      print('Socket connected');
    });

    socket.onDisconnect((_) {
      print('Socket disconnected');
    });

    socket.on('newDirectMessage', (data) {
      print('Received new direct message: $data');
      _handleNewMessage(data);
    });

    socket.on('newDirectMessageNotification', (data) {
      print('Received new direct message notification: $data');
      _handleNewMessageNotification(data);
    });
  }

  void _handleNewMessage(Map<String, dynamic> messageData) async {
    if (currentUserId == null || !mounted) return;

    try {
      // ถ้าเป็นข้อความใหม่จาก user ที่ยังไม่มีประวัติด้วย
      if (messageData['sender'] != null && messageData['sender']['employeeID'] != null) {
        final senderId = messageData['sender']['employeeID'].toString();
        
        // ตรวจสอบว่ามี conversation อยู่แล้วหรือไม่
        final existingIndex = conversations.indexWhere((conv) {
          return conv['participantId'].toString() == senderId;
        });

        if (existingIndex == -1) {
          // ถ้าไม่มี conversation อยู่ ให้ดึงข้อมูล user เพิ่มเติม
          try {
            final userDetails = await widget.apiService.getUserInfo(senderId);
            if (userDetails != null && mounted) {
              setState(() {
                // สร้าง conversation ใหม่
                final newConversation = {
                  'participantId': senderId,
                  'participant': {
                    'employeeID': userDetails['employeeID'],
                    'fullNameThai': userDetails['fullNameThai'],
                    'fullName': userDetails['fullName'],
                    'imgUrl': userDetails['imgUrl'],
                    'department': userDetails['department'],
                  },
                  'lastMessage': {
                    'message': messageData['message'],
                    'createdAt': messageData['createdAt'],
                    'sender': messageData['sender'],
                    'isImage': messageData['isImage'] ?? false,
                    'isFile': messageData['isFile'] ?? false,
                  },
                  'unreadCount': 1,
                  'participants': [currentUserId, senderId],
                };
                conversations.insert(0, newConversation);
              });
              return;
            }
          } catch (e) {
            print('Error fetching user details: $e');
          }
        }

        // ถ้ามี conversation อยู่แล้ว หรือไม่สามารถดึงข้อมูล user ได้
        setState(() {
          if (existingIndex != -1) {
            // อัพเดท conversation ที่มีอยู่
            final updatedConversation = Map<String, dynamic>.from(conversations[existingIndex]);
            updatedConversation['lastMessage'] = {
              'message': messageData['message'],
              'createdAt': messageData['createdAt'],
              'sender': messageData['sender'],
              'isImage': messageData['isImage'] ?? false,
              'isFile': messageData['isFile'] ?? false,
            };
            updatedConversation['unreadCount'] = (updatedConversation['unreadCount'] ?? 0) + 1;
            
            // ย้าย conversation ไปไว้ด้านบน
            conversations.removeAt(existingIndex);
            conversations.insert(0, updatedConversation);
          } else {
            // ถ้าไม่สามารถดึงข้อมูล user ได้ ให้สร้าง conversation แบบพื้นฐาน
            final newConversation = {
              'participantId': senderId,
              'participant': messageData['sender'],
              'lastMessage': {
                'message': messageData['message'],
                'createdAt': messageData['createdAt'],
                'sender': messageData['sender'],
                'isImage': messageData['isImage'] ?? false,
                'isFile': messageData['isFile'] ?? false,
              },
              'unreadCount': 1,
              'participants': [currentUserId, senderId],
            };
            conversations.insert(0, newConversation);
          }
        });
      }
    } catch (e) {
      print('Error handling new message: $e');
    }
  }

  void _handleNewMessageNotification(Map<String, dynamic> notificationData) {
    if (!mounted) return;

    try {
      // อัพเดท unread count สำหรับ conversation
      setState(() {
        final existingIndex = conversations.indexWhere((conv) {
          return conv['participantId'].toString() == notificationData['sender']['employeeID'].toString();
        });

        if (existingIndex != -1) {
          // อัพเดท conversation ที่มีอยู่
          final updatedConversation = Map<String, dynamic>.from(conversations[existingIndex]);
          updatedConversation['unreadCount'] = (updatedConversation['unreadCount'] ?? 0) + 1;
          conversations[existingIndex] = updatedConversation;
        } else if (notificationData['sender'] != null) {
          // ถ้าไม่มี conversation และมีข้อมูล sender ให้สร้างใหม่
          final newConversation = {
            'participantId': notificationData['sender']['employeeID'],
            'participant': notificationData['sender'],
            'lastMessage': {
              'message': notificationData['message'],
              'createdAt': notificationData['timestamp'],
              'sender': notificationData['sender'],
            },
            'unreadCount': 1,
            'participants': [currentUserId, notificationData['sender']['employeeID']],
          };
          conversations.insert(0, newConversation);
        }
      });
    } catch (e) {
      print('Error handling new message notification: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print('\n=== App Resumed - Refreshing Direct Messages ===');
      loadCurrentUser();
      if (!socket.connected) {
        socket.connect();
      }
    } else if (state == AppLifecycleState.paused) {
      socket.disconnect();
    }
  }

  void loadCurrentUser() async {
    final userData = await getCurrentUserFromPrefs();
    if (userData != null) {
      setState(() {
        currentUserId = userData['employeeID']?.toString();
      });
      print('fetchCurrentUser (from prefs): currentUserId = $currentUserId');
      _loadConversations();
    } else {
      print('fetchCurrentUser: No user data in SharedPreferences');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _loadConversations() async {
    print('_loadConversations called, currentUserId = $currentUserId');
    if (currentUserId == null) {
      print('Cannot load conversations: currentUserId is null');
      setState(() {
        isLoading = false;
      });
      return;
    }

    print('\n=== Loading Direct Message Conversations ===');
    print('Current User ID: $currentUserId');

    try {
      final url = Uri.parse(
        '${ApiService.baseUrl}/api/direct-messages/conversations',
      ).replace(
        queryParameters: {
          'employeeId': currentUserId,
          'page': '1',
          'limit': '20',
        },
      );

      print('Fetching conversations from: $url');
      final response = await http.get(url);
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      setState(() {
        isLoading = false;
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success']) {
            conversations = List<Map<String, dynamic>>.from(data['data']);
            print('Loaded ${conversations.length} conversations');
          } else {
            print('API returned success: false');
            conversations = [];
          }
        } else {
          print('API returned status code: ${response.statusCode}');
          conversations = [];
        }
      });

      if (response.statusCode != 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถโหลดประวัติการสนทนาได้')),
        );
      }
    } catch (e) {
      print('Error loading conversations: $e');
      setState(() {
        isLoading = false;
        conversations = [];
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เกิดข้อผิดพลาดในการเชื่อมต่อ')),
        );
      }
    }
  }

  void _startNewChat() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => SelectUserPage(
              apiService: widget.apiService,
              currentUserId: currentUserId,
            ),
      ),
    );

    if (result != null && mounted) {
      _loadConversations(); // Reload conversations after starting new chat
    }
  }

  void _openChat(Map<String, dynamic> conversation) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => DirectMessagePage(
              recipientId: conversation['participantId'].toString(),
              recipientName:
                  conversation['participant']['fullNameThai'] ??
                  conversation['participant']['fullName'] ??
                  'ไม่ระบุชื่อ',
              recipientImage: conversation['participant']['imgUrl'],
              apiService: widget.apiService,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      floatingActionButton: FloatingActionButton(
        onPressed: _startNewChat,
        backgroundColor: theme.colorScheme.primary,
        child: const Icon(Icons.person_add_alt_1, color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child:
            isLoading
                ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'กำลังโหลดข้อมูล...',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                )
                : conversations.isEmpty
                ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 64,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'ยังไม่มีประวัติการสนทนา',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                )
                : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: conversations.length,
                  itemBuilder: (context, index) {
                    final conversation = conversations[index];
                    final participant = conversation['participant'];
                    final lastMessage = conversation['lastMessage'];
                    final unreadCount = conversation['unreadCount'] ?? 0;

                    // เวลาข้อความล่าสุด
                    String lastMsgTime = '';
                    if (lastMessage != null &&
                        lastMessage['createdAt'] != null) {
                      try {
                        // ถ้า createdAt เป็น String รูปแบบ "05/06/2025 21:25"
                        if (lastMessage['createdAt'] is String) {
                          DateTime date = DateFormat(
                            'dd/MM/yyyy HH:mm',
                          ).parse(lastMessage['createdAt']);
                          lastMsgTime =
                              '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                        }
                        // ถ้า createdAt เป็น DateTime object
                        else if (lastMessage['createdAt'] is DateTime) {
                          DateTime date = lastMessage['createdAt'];
                          lastMsgTime =
                              '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                        }
                      } catch (e) {
                        print('Error parsing createdAt: $e');
                        lastMsgTime = '';
                      }
                    }
                    // ชื่อผู้ส่ง
                    String senderName = 'คุณ';
                    if (lastMessage != null && lastMessage['sender'] != null) {
                      if (lastMessage['sender']['employeeID'].toString() !=
                          currentUserId) {
                        senderName = lastMessage['sender']['fullName'] ?? '';
                      }
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                      child: Material(
                        color: Colors.white,
                        elevation: 2,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap:
                              () => _openChat(
                                conversation,
                              ), // เพิ่ม loading, mark as read ได้
                          child: Container(
                            height: 70,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor: Colors.blue,
                                  backgroundImage:
                                      participant['imgUrl'] != null
                                          ? NetworkImage(participant['imgUrl'])
                                          : null,
                                  child:
                                      participant['imgUrl'] == null
                                          ? Text(
                                            (participant['fullNameThai'] ??
                                                participant['fullName'] ??
                                                '?')[0],
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          )
                                          : null,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              participant['fullNameThai'] ??
                                                  participant['fullName'] ??
                                                  'ไม่ระบุชื่อ',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w500,
                                                fontSize: 12,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            lastMsgTime,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey.shade400,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        lastMessage != null
                                            ? '$senderName: ${lastMessage['message'] ?? (lastMessage['isImage'] == true
                                                    ? 'รูปภาพ'
                                                    : lastMessage['isFile'] == true
                                                    ? 'ไฟล์'
                                                    : '')}'
                                            : '',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                if (unreadCount > 0)
                                  Container(
                                    margin: const EdgeInsets.only(left: 10),
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade400,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.green.withOpacity(0.2),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      unreadCount.toString(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
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
    );
  }

  String _formatDate(String dateStr) {
    final date = DateTime.parse(dateStr);
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'เมื่อวาน';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} วันที่แล้ว';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Future<Map<String, dynamic>?> getCurrentUserFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    if (userJson != null) {
      return jsonDecode(userJson) as Map<String, dynamic>;
    }
    return null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    socket.dispose();
    super.dispose();
  }
}
