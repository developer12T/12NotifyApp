import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/api_service.dart';
import 'dart:math' as math;
import 'chat_page.dart';

class ChatRoom {
  final String id;
  final String name;
  final String description;
  final String admin;
  final Map<String, dynamic> lastMessage;
  final int unreadCount;
  final String color;
  final int memberCount;
  final String userRole;

  ChatRoom({
    required this.id,
    required this.name,
    required this.description,
    required this.admin,
    required this.lastMessage,
    required this.unreadCount,
    required this.color,
    required this.memberCount,
    required this.userRole,
  });

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      id: json['id'],
      name: json['name'],
      description: json['description'] ?? '',
      admin: json['admin'] ?? '',
      lastMessage: json['lastMessage'] ?? {'sender': 'ยังไม่มีข้อความ'},
      unreadCount: json['unreadCount'] ?? 0,
      color: json['color'] ?? '#2196F3',
      memberCount: json['memberCount'] ?? 1,
      userRole: json['userRole']?.toString().toLowerCase() ?? 'member',
    );
  }

  String get lastMessageText => lastMessage['message'] ?? '';
  String lastMessageSender(String? currentUserEmployeeId, String roomName) {
    final sender = lastMessage['sender'];
    print('lastMessageSender: sender = $currentUserEmployeeId');
    if (sender is Map && sender['employeeID'] != null && currentUserEmployeeId != null) {
      if (sender['employeeID'].toString() == currentUserEmployeeId) {
        return 'คุณ';
      }
      return sender['fullName'] ?? roomName;
    } else if (sender is String && sender.isNotEmpty) {
      return sender;
    }
    // ถ้าไม่มี sender เลย
    return roomName; // หรือจะใช้ '-' หรือ 'ระบบ' ก็ได้
  }
  String get lastMessageTime =>
      lastMessage['timestamp'] != null
          ? DateTime.parse(
            lastMessage['timestamp'],
          ).toString().substring(11, 16)
          : '';
}

class RoomPage extends StatefulWidget {
  final ApiService apiService;

  const RoomPage({super.key, required this.apiService});

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> with AutomaticKeepAliveClientMixin {
  String _userName = '';
  final List<ChatRoom> _chatRooms = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _currentUserEmployeeId;
  bool _isDisposed = false;
  bool _isFirstLoad = true;
  List<Map<String, dynamic>> _pendingMessages = [];  // Add queue for pending messages

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserEmployeeId();
    _loadUserData();
    _setupSocketListeners();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isFirstLoad) {
      _refreshData();
    }
    _isFirstLoad = false;

    // Process any pending messages
    if (_pendingMessages.isNotEmpty) {
      print('Processing ${_pendingMessages.length} pending messages');
      for (final message in _pendingMessages) {
        _processMessageUpdate(message);
      }
      _pendingMessages.clear();
    }
  }

  Future<void> _refreshData() async {
    print('\n=== Refreshing Room Data ===');
    if (!_isDisposed) {
      setState(() {
        _isLoading = true;
      });
      
      print('Fetching rooms...');
      await _fetchRooms();
      print('Current rooms after fetch: ${_chatRooms.map((r) => '${r.id} (${r.name})').join(', ')}');
      
      // Process any pending messages after refresh
      if (_pendingMessages.isNotEmpty) {
        print('\nProcessing ${_pendingMessages.length} pending messages after refresh');
        for (final message in _pendingMessages) {
          print('\nProcessing pending message for room: ${message['room']}');
          _processMessageUpdate(message);
        }
        _pendingMessages.clear();
      }
    }
  }

  void _updateRoomWithNewMessage(Map<String, dynamic> notification) {
    print('\n=== Processing New Message ===');
    print('Widget mounted: $mounted');
    print('Widget disposed: $_isDisposed');
    print('Message room ID: ${notification['room']}');
    print('Current rooms: ${_chatRooms.map((r) => r.id).join(', ')}');
    print('Full notification: $notification');

    // If widget is not mounted, add to pending messages queue
    if (!mounted) {
      print('Widget not mounted, adding message to pending queue');
      _pendingMessages.add(notification);
      print('Current pending messages count: ${_pendingMessages.length}');
      return;
    }

    if (_isDisposed) {
      print('Widget disposed, skipping update');
      return;
    }

    _processMessageUpdate(notification);
  }

  void _processMessageUpdate(Map<String, dynamic> notification) {
    print('\n=== Processing Message Update ===');
    final messageRoomId = notification['room']?.toString();
    print('Processing message for room: $messageRoomId');
    
    setState(() {
      final updatedRooms = List<ChatRoom>.from(_chatRooms);
      bool foundMatchingRoom = false;

      for (int i = 0; i < updatedRooms.length; i++) {
        final room = updatedRooms[i];
        print('Checking room: ${room.id} against message room: $messageRoomId');
        
        // Check both room and roomId fields
        if (room.id == messageRoomId) {
          print('Found matching room: ${room.id}');
          print('Current room data:');
          print('- Name: ${room.name}');
          print('- Last message: ${room.lastMessage}');
          print('- Unread count: ${room.unreadCount}');

          final sender = notification['sender'];
          final isCurrentUser = sender is Map && 
                              sender['employeeID']?.toString() == _currentUserEmployeeId;
          print('Is current user: $isCurrentUser');

          int newUnreadCount = room.unreadCount;
          if (!isCurrentUser) {
            newUnreadCount++;
            print('Incrementing unread count to: $newUnreadCount');
          }

          final newLastMessage = {
            'sender': sender ?? 'ยังไม่มีข้อความ',
            'message': notification['message'] ?? '',
            'timestamp': notification['timestamp'] ?? DateTime.now().toIso8601String(),
          };
          print('New last message: $newLastMessage');

          final updatedRoom = ChatRoom(
            id: room.id,
            name: room.name,
            description: room.description,
            admin: room.admin,
            lastMessage: newLastMessage,
            unreadCount: newUnreadCount,
            color: room.color,
            memberCount: room.memberCount,
            userRole: room.userRole,
          );

          updatedRooms.removeAt(i);
          updatedRooms.insert(0, updatedRoom);
          foundMatchingRoom = true;
          print('Room updated successfully');
          break;
        }
      }

      if (!foundMatchingRoom) {
        print('No matching room found for message room ID: $messageRoomId');
        print('Available rooms: ${updatedRooms.map((r) => r.id).join(', ')}');
      }

      if (foundMatchingRoom) {
        _chatRooms.clear();
        _chatRooms.addAll(updatedRooms);
        print('Updated rooms list: ${_chatRooms.map((r) => '${r.id} (${r.name})').join(', ')}');
      }
    });
  }

  void _setupSocketListeners() {
    print('Setting up socket listeners');

    widget.apiService.onNewMessage((notification) {
      print('Received notification in HomePage: $notification');

      if (mounted) {
        setState(() {
          for (int i = 0; i < _chatRooms.length; i++) {
            final room = _chatRooms[i];
            if (room.id == notification['room']) {
              print('Updating room: ${room.id}');

              final isCurrentUser = notification['sender'] is Map && 
                                  notification['sender']['employeeID']?.toString() == _currentUserEmployeeId;

              int newUnreadCount = room.unreadCount;
              if (!isCurrentUser) {
                newUnreadCount++;
              }

              final newLastMessage = {
                'sender': notification['sender'] ?? 'ยังไม่มีข้อความ',
                'message': notification['message'] ?? '',
                'timestamp': notification['timestamp'] ?? DateTime.now().toIso8601String(),
              };

              _chatRooms[i] = ChatRoom(
                id: room.id,
                name: room.name,
                description: room.description,
                admin: room.admin,
                lastMessage: newLastMessage,
                unreadCount: newUnreadCount,
                color: room.color,
                memberCount: room.memberCount,
                userRole: room.userRole,
              );

              if (i > 0) {
                final updatedRoom = _chatRooms.removeAt(i);
                _chatRooms.insert(0, updatedRoom);
              }

              print('Room updated: ${_chatRooms[0].lastMessage}');
              print('New unread count: $newUnreadCount');
            }
          }
        });
      }
    });

    widget.apiService.socket?.on('messagesRead', (data) {
      print('Messages read event received: $data');
      if (mounted && data is Map) {
        final roomId = data['roomId']?.toString();
        if (roomId != null) {
          setState(() {
            for (int i = 0; i < _chatRooms.length; i++) {
              if (_chatRooms[i].id == roomId) {
                _chatRooms[i] = ChatRoom(
                  id: _chatRooms[i].id,
                  name: _chatRooms[i].name,
                  description: _chatRooms[i].description,
                  admin: _chatRooms[i].admin,
                  lastMessage: _chatRooms[i].lastMessage,
                  unreadCount: 0,
                  color: _chatRooms[i].color,
                  memberCount: _chatRooms[i].memberCount,
                  userRole: _chatRooms[i].userRole,
                );
                break;
              }
            }
          });
        }
      }
    });
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('user');
      if (userJson != null) {
        final userData = jsonDecode(userJson);
        if (!_isDisposed) {
          setState(() {
            _userName = userData['username'] ?? '';
          });
        }
      }
      await _fetchRooms();
    } catch (e) {
      if (!_isDisposed) {
        setState(() {
          _errorMessage = 'Failed to load user data: $e';
        });
      }
    }
  }

  Future<void> _fetchRooms() async {
    try {
      if (!_isDisposed) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }

      final rooms = await widget.apiService.fetchRooms();

      // Leave all rooms first
      await widget.apiService.leaveAllRooms();

      if (!_isDisposed) {
        setState(() {
          _chatRooms.clear();
          _chatRooms.addAll(rooms.map((room) => ChatRoom.fromJson(room)));
          _isLoading = false;
        });
      }

      // Join all rooms to receive notifications
      for (final room in _chatRooms) {
        print('Joining room: ${room.id}');
        await widget.apiService.joinRoom(room.id);
      }
    } catch (e) {
      print('Error fetching rooms: $e');
      if (!_isDisposed) {
        setState(() {
          _errorMessage = 'Failed to fetch rooms: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user');
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return WillPopScope(
      onWillPop: () async {
        await _refreshData();
        return true;
      },
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: _refreshData,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _refreshData,
                            child: const Text('ลองใหม่'),
                          ),
                        ],
                      ),
                    )
                  : _chatRooms.isEmpty
                      ? const Center(child: Text('No chat rooms available'))
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _chatRooms.length,
                          itemBuilder: (context, index) {
                            final room = _chatRooms[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              child: Material(
                                color: Colors.white,
                                elevation: 2,
                                borderRadius: BorderRadius.circular(8),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () async {
                                    print('\n=== Room Tap Handler ===');
                                    print('Room ID: ${room.id}');
                                    print('Room Name: ${room.name}');
                                    print('Current User ID: $_currentUserEmployeeId');
                                    
                                    try {
                                      print('Attempting to mark room as read...');
                                      await widget.apiService.markRoomAsRead(room.id);
                                      print('Successfully marked room as read');

                                      if (!_isDisposed) {
                                        print('Updating local room state...');
                                        setState(() {
                                          final roomIndex = _chatRooms.indexWhere((r) => r.id == room.id);
                                          if (roomIndex != -1) {
                                            print('Found room at index $roomIndex, updating unread count to 0');
                                            _chatRooms[roomIndex] = ChatRoom(
                                              id: room.id,
                                              name: room.name,
                                              description: room.description,
                                              admin: room.admin,
                                              lastMessage: room.lastMessage,
                                              unreadCount: 0,
                                              color: room.color,
                                              memberCount: room.memberCount,
                                              userRole: room.userRole,
                                            );
                                          } else {
                                            print('Room not found in local state');
                                          }
                                        });
                                      }

                                      if (mounted) {
                                        print('Navigating to chat page...');
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => ChatPage(
                                              roomId: room.id,
                                              roomName: room.name,
                                              apiService: widget.apiService,
                                              userRole: room.userRole,
                                            ),
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      print('❌ Error in room tap handler:');
                                      print('Error type: ${e.runtimeType}');
                                      print('Error message: $e');
                                      print('Stack trace: ${StackTrace.current}');
                                      
                                      if (mounted) {
                                        String errorMessage = 'ไม่สามารถอัพเดทสถานะการอ่านได้';
                                        if (e is Exception) {
                                          errorMessage += ': ${e.toString()}';
                                        }
                                        
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(errorMessage),
                                            backgroundColor: Colors.red,
                                            duration: const Duration(seconds: 5),
                                            action: SnackBarAction(
                                              label: 'ลองอีกครั้ง',
                                              textColor: Colors.white,
                                              onPressed: () async {
                                                try {
                                                  await widget.apiService.markRoomAsRead(room.id);
                                                  if (mounted) {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (context) => ChatPage(
                                                          roomId: room.id,
                                                          roomName: room.name,
                                                          apiService: widget.apiService,
                                                          userRole: room.userRole,
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                } catch (retryError) {
                                                  if (mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: Text('ไม่สามารถอัพเดทสถานะการอ่านได้: ${retryError.toString()}'),
                                                        backgroundColor: Colors.red,
                                                      ),
                                                    );
                                                  }
                                                }
                                              },
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  child: Container(
                                    height: 80,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Container(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.grey.withOpacity(0.2),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                            border: Border.all(color: Colors.grey.shade200, width: 2),
                                          ),
                                          child: CircleAvatar(
                                            radius: 28,
                                            backgroundColor: Color(int.parse(room.color.replaceAll('#', '0xFF'))),
                                            child: Text(
                                              room.name.substring(0, 1),
                                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Row(
                                                      children: [
                                                        Text(
                                                          room.name,
                                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                        const SizedBox(width: 6),
                                                        Icon(Icons.group, size: 15, color: Colors.grey.shade400),
                                                        Text(
                                                          ' (${room.memberCount})',
                                                          style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Text(
                                                    room.lastMessageTime,
                                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                '${room.lastMessageSender(_currentUserEmployeeId, room.name)}: ${room.lastMessageText}',
                                                style: const TextStyle(fontSize: 14, color: Colors.grey),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (room.unreadCount > 0)
                                          Container(
                                            margin: const EdgeInsets.only(left: 10),
                                            width: 28,
                                            height: 28,
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
                                              room.unreadCount.toString(),
                                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
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
      ),
    );
  }

  void _showCreateRoomDialog() {
    // Implementation of _showCreateRoomDialog method
  }

  Future<void> _loadCurrentUserEmployeeId() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    if (userJson != null) {
      final userData = jsonDecode(userJson);
      setState(() {
        _currentUserEmployeeId = userData['employeeID']?.toString();
      });
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
