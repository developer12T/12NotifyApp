import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/api_service.dart';

class AddMembersPage extends StatefulWidget {
  final String roomId;

  const AddMembersPage({super.key, required this.roomId});

  @override
  State<AddMembersPage> createState() => _AddMembersPageState();
}

class _AddMembersPageState extends State<AddMembersPage> with SingleTickerProviderStateMixin {
  List<dynamic> allUsers = [];
  List<dynamic> filteredUsers = [];
  List<dynamic> selectedUsers = [];
  List<String> existingMemberIds = [];
  List<Map<String, dynamic>> existingMembers = [];
  List<String> departments = [];
  String? selectedDepartment;
  String? currentUserId;
  final TextEditingController _searchController = TextEditingController();
  bool isLoading = true;
  bool isAddingMembers = false;
  bool isRemovingMember = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
    fetchCurrentUser();
    fetchUsers();
    fetchExistingMembers();
  }

  Future<void> fetchCurrentUser() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/users/current'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          currentUserId = data['employeeID']?.toString();
        });
      }
    } catch (e) {
      print('Error fetching current user: $e');
    }
  }

  Future<void> fetchUsers() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/users'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          allUsers = (data['data'] as List<dynamic>)
              .where((user) => user['status'] != 0)
              .toList();
          filteredUsers = allUsers;
          // Extract unique departments, excluding null values
          departments = allUsers
              .where((user) => user['department'] != null)
              .map((user) => user['department'] as String)
              .toSet()
              .toList();
          departments.sort();
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ไม่สามารถโหลดข้อมูลผู้ใช้ได้')),
          );
        }
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เกิดข้อผิดพลาดในการเชื่อมต่อ')),
        );
      }
    }
  }

  Future<void> fetchExistingMembers() async {
    try {
      print('Fetching existing members for room: ${widget.roomId}');
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/rooms/${widget.roomId}/members'),
      );

      print('Existing members response status: ${response.statusCode}');
      print('Existing members response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['members'] != null && data['members'] is List) {
          final members = data['members'] as List<dynamic>;
          setState(() {
            existingMembers = members.map((member) => {
              'employeeID': member['employeeID'].toString(),
              'role': member['role'].toString(),
            }).toList();
            existingMemberIds = members
                .where((member) => member['employeeID'] != null)
                .map((member) => member['employeeID'].toString())
                .toList();
          });
          print('Parsed existing member IDs: $existingMemberIds');
        } else {
          print('Invalid response structure: $data');
          setState(() {
            existingMembers = [];
            existingMemberIds = [];
          });
        }
      } else {
        print('Error fetching existing members: ${response.statusCode}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ไม่สามารถโหลดข้อมูลสมาชิกที่มีอยู่ได้ (${response.statusCode})')),
          );
        }
      }
    } catch (e, stackTrace) {
      print('Exception fetching existing members: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เกิดข้อผิดพลาดในการเชื่อมต่อ')),
        );
      }
    }
  }

  bool isRoomOwner(String employeeId) {
    try {
      for (var member in existingMembers) {
        if (member['employeeID'].toString() == employeeId) {
          return member['role']?.toString().toLowerCase() == 'owner';
        }
      }
      return false;
    } catch (e) {
      print('Error in isRoomOwner: $e');
      return false;
    }
  }

  bool isAdmin(String employeeId) {
    try {
      for (var member in existingMembers) {
        if (member['employeeID'].toString() == employeeId) {
          return member['role']?.toString().toLowerCase() == 'admin';
        }
      }
      return false;
    } catch (e) {
      print('Error in isAdmin: $e');
      return false;
    }
  }

  void filterUsers(String query) {
    setState(() {
      filteredUsers = allUsers.where((user) {
        final fullName = user['fullNameThai']?.toString().toLowerCase() ?? '';
        final department = user['department']?.toString().toLowerCase() ?? '';
        final searchLower = query.toLowerCase();
        
        bool matchesSearch = fullName.contains(searchLower) || 
                           department.contains(searchLower);
        bool matchesDepartment = selectedDepartment == null || 
                               user['department'] == selectedDepartment;
        
        return matchesSearch && matchesDepartment;
      }).toList();
    });
  }

  Future<void> addMembers() async {
    if (selectedUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกสมาชิกอย่างน้อย 1 คน')),
      );
      return;
    }

    try {
      setState(() {
        isAddingMembers = true;
      });
      final requestBody = {
        'members': selectedUsers.map((user) => {
          'empId': user['employeeID'],
          'role': 'User'
        }).toList(),
      };
      
      print('Adding members to room ${widget.roomId}');
      print('Request body: ${jsonEncode(requestBody)}');

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/rooms/${widget.roomId}/members'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      print('Add members response status: ${response.statusCode}');
      print('Add members response body: ${response.body}');

      if (response.statusCode == 200) {
        print('Successfully added members');
        setState(() {
          existingMemberIds.addAll(
            selectedUsers.map((user) => user['employeeID'].toString())
          );
          selectedUsers.clear();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('เพิ่มสมาชิกเรียบร้อยแล้ว')),
          );
        }
      } else {
        print('Error adding members: ${response.statusCode}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ไม่สามารถเพิ่มสมาชิกได้ (${response.statusCode})')),
          );
        }
      }
    } catch (e, stackTrace) {
      print('Exception adding members: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เกิดข้อผิดพลาดในการเชื่อมต่อ')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isAddingMembers = false;
        });
      }
    }
  }

  Future<void> removeMember(String empId) async {
    try {
      setState(() {
        isRemovingMember = true;
      });
      print('Removing member $empId from room ${widget.roomId}');
      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/api/rooms/${widget.roomId}/members/$empId'),
      );

      print('Remove member response status: ${response.statusCode}');
      print('Remove member response body: ${response.body}');

      if (response.statusCode == 200) {
        setState(() {
          existingMemberIds.remove(empId);
        });
        print('Successfully removed member $empId');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ลบสมาชิกออกจากห้องแล้ว')),
          );
        }
      } else {
        print('Error removing member: ${response.statusCode}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ไม่สามารถลบสมาชิกได้ (${response.statusCode})')),
          );
        }
      }
    } catch (e, stackTrace) {
      print('Exception removing member: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เกิดข้อผิดพลาดในการเชื่อมต่อ')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isRemovingMember = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Stack(
      children: [
        Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            title: const Text(
              'เพิ่มสมาชิก',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
            ),
            elevation: 0,
            centerTitle: true,
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: Colors.white,
            leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(0),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: selectedUsers.isEmpty || isAddingMembers ? null : addMembers,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white.withOpacity(0.5),
                  ),
                  icon: isAddingMembers
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              selectedUsers.isEmpty ? Colors.white.withOpacity(0.5) : Colors.white,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.check_circle_outline,
                          color: selectedUsers.isEmpty ? Colors.white.withOpacity(0.5) : Colors.white,
                        ),
                  label: Text(
                    'เพิ่ม ${selectedUsers.isEmpty ? '' : '(${selectedUsers.length})'}',
                    style: TextStyle(
                      color: selectedUsers.isEmpty ? Colors.white.withOpacity(0.5) : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'ค้นหาชื่อหรือแผนก...',
                          prefixIcon: Icon(Icons.search, color: theme.colorScheme.primary),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: theme.dividerColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: theme.colorScheme.primary),
                          ),
                          filled: true,
                          fillColor: theme.scaffoldBackgroundColor,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onChanged: filterUsers,
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            FilterChip(
                              label: const Text('ทั้งหมด'),
                              selected: selectedDepartment == null,
                              onSelected: (selected) {
                                setState(() {
                                  selectedDepartment = null;
                                  filterUsers(_searchController.text);
                                });
                              },
                              backgroundColor: theme.scaffoldBackgroundColor,
                              selectedColor: theme.colorScheme.primary.withOpacity(0.2),
                              checkmarkColor: theme.colorScheme.primary,
                              labelStyle: TextStyle(
                                color: selectedDepartment == null
                                    ? theme.colorScheme.primary
                                    : theme.textTheme.bodyMedium?.color,
                                fontWeight: selectedDepartment == null
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: selectedDepartment == null
                                      ? theme.colorScheme.primary
                                      : theme.dividerColor.withOpacity(0.5),
                                ),
                              ),
                            ),
                            ...departments.map((department) => Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: FilterChip(
                                label: Text(department),
                                selected: selectedDepartment == department,
                                onSelected: (selected) {
                                  setState(() {
                                    selectedDepartment = selected ? department : null;
                                    filterUsers(_searchController.text);
                                  });
                                },
                                backgroundColor: theme.scaffoldBackgroundColor,
                                selectedColor: theme.colorScheme.primary.withOpacity(0.2),
                                checkmarkColor: theme.colorScheme.primary,
                                labelStyle: TextStyle(
                                  color: selectedDepartment == department
                                      ? theme.colorScheme.primary
                                      : theme.textTheme.bodyMedium?.color,
                                  fontWeight: selectedDepartment == department
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: selectedDepartment == department
                                        ? theme.colorScheme.primary
                                        : theme.dividerColor.withOpacity(0.5),
                                  ),
                                ),
                              ),
                            )).toList(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: isLoading
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
                      : filteredUsers.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.search_off_rounded,
                                    size: 64,
                                    color: theme.textTheme.bodySmall?.color,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'ไม่พบผู้ใช้ที่ค้นหา',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      color: theme.textTheme.bodySmall?.color,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: filteredUsers.length,
                              itemBuilder: (context, index) {
                                final user = filteredUsers[index];
                                final isSelected = selectedUsers.contains(user);
                                final isExistingMember = existingMemberIds.contains(user['employeeID'].toString());
                                final isOwner = isExistingMember && isRoomOwner(user['employeeID'].toString());
                                
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: isSelected || isExistingMember
                                          ? theme.colorScheme.primary.withOpacity(0.5)
                                          : theme.dividerColor.withOpacity(0.1),
                                    ),
                                  ),
                                  child: InkWell(
                                    onTap: isExistingMember ? null : () {
                                      setState(() {
                                        if (isSelected) {
                                          selectedUsers.remove(user);
                                        } else {
                                          selectedUsers.add(user);
                                        }
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        children: [
                                          if (user['imgUrl'] != null)
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(24),
                                              child: Image.network(
                                                user['imgUrl'],
                                                width: 48,
                                                height: 48,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) {
                                                  return Container(
                                                    width: 48,
                                                    height: 48,
                                                    decoration: BoxDecoration(
                                                      color: theme.colorScheme.primary.withOpacity(0.1),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: Center(
                                                      child: Text(
                                                        user['fullNameThai']?.toString().characters.first.toUpperCase() ?? '?',
                                                        style: TextStyle(
                                                          color: theme.colorScheme.primary,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 18,
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            )
                                          else
                                            Container(
                                              width: 48,
                                              height: 48,
                                              decoration: BoxDecoration(
                                                color: theme.colorScheme.primary.withOpacity(0.1),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  user['fullNameThai']?.toString().characters.first.toUpperCase() ?? '?',
                                                  style: TextStyle(
                                                    color: theme.colorScheme.primary,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 18,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        user['fullNameThai'] ?? user['fullName'] ?? 'ไม่ระบุชื่อ',
                                                        style: theme.textTheme.titleMedium?.copyWith(
                                                          fontWeight: FontWeight.w600,
                                                          color: isExistingMember ? theme.textTheme.bodySmall?.color : null,
                                                        ),
                                                      ),
                                                    )
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                if (user['department'] != null)
                                                  Text(
                                                    user['department'],
                                                    style: theme.textTheme.bodyMedium?.copyWith(
                                                      color: theme.textTheme.bodySmall?.color,
                                                    ),
                                                  )
                                                else if (user['position'] != null)
                                                  Text(
                                                    user['position'],
                                                    style: theme.textTheme.bodyMedium?.copyWith(
                                                      color: theme.textTheme.bodySmall?.color,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          if (isExistingMember)
                                            isOwner
                                                ? IconButton(
                                                    icon: Icon(
                                                      Icons.manage_accounts,
                                                      size: 24,
                                                      color: theme.colorScheme.primary,
                                                    ),
                                                    onPressed: null,
                                                  )
                                                : isAdmin(user['employeeID'].toString())
                                                    ? IconButton(
                                                        icon: Icon(
                                                          Icons.admin_panel_settings,
                                                          size: 24,
                                                          color: const Color.fromARGB(255, 236, 200, 52),
                                                        ),
                                                        onPressed: null,
                                                      )
                                                    : IconButton(
                                                        icon: Icon(
                                                          Icons.delete_outline,
                                                          size: 24,
                                                          color: theme.colorScheme.error,
                                                        ),
                                                        onPressed: () {
                                                          showModalBottomSheet<bool>(
                                                            context: context,
                                                            shape: const RoundedRectangleBorder(
                                                              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                                                            ),
                                                            isScrollControlled: true,
                                                            builder: (BuildContext context) {
                                                              return Padding(
                                                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                                                                child: Column(
                                                                  mainAxisSize: MainAxisSize.min,
                                                                  children: [
                                                                    Icon(Icons.delete_outline, color: theme.colorScheme.error, size: 48),
                                                                    const SizedBox(height: 12),
                                                                    const Text(
                                                                      'ลบสมาชิก',
                                                                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                                                    ),
                                                                    const SizedBox(height: 8),
                                                                    const Text(
                                                                      'คุณต้องการลบสมาชิกนี้ออกจากห้องใช่หรือไม่?',
                                                                      style: TextStyle(fontSize: 16),
                                                                    ),
                                                                    const SizedBox(height: 24),
                                                                    Row(
                                                                      children: [
                                                                        Expanded(
                                                                          child: ElevatedButton(
                                                                            style: ElevatedButton.styleFrom(
                                                                              backgroundColor: theme.colorScheme.error,
                                                                              foregroundColor: Colors.white,
                                                                              shape: RoundedRectangleBorder(
                                                                                borderRadius: BorderRadius.circular(8),
                                                                              ),
                                                                            ),
                                                                            onPressed: () {
                                                                              Navigator.pop(context);
                                                                              removeMember(user['employeeID'].toString());
                                                                            },
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
                                                                            onPressed: () => Navigator.pop(context),
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
                                                        },
                                                      )
                                          else
                                            Container(
                                              width: 24,
                                              height: 24,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: isSelected
                                                    ? theme.colorScheme.primary
                                                    : theme.dividerColor.withOpacity(0.1),
                                              ),
                                              child: isSelected
                                                  ? const Icon(
                                                      Icons.check,
                                                      size: 16,
                                                      color: Colors.white,
                                                    )
                                                  : null,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        ),
        if (isRemovingMember)
          Container(
            color: Colors.black.withOpacity(0.3),
            child: Center(
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'กำลังลบสมาชิก...',
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
  }
} 