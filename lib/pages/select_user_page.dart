import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/api_service.dart';
import 'direct_message_page.dart';

class SelectUserPage extends StatefulWidget {
  final ApiService apiService;
  final String? currentUserId;

  const SelectUserPage({
    super.key, 
    required this.apiService,
    required this.currentUserId,
  });

  @override
  State<SelectUserPage> createState() => _SelectUserPageState();
}

class _SelectUserPageState extends State<SelectUserPage> with SingleTickerProviderStateMixin {
  List<dynamic> allUsers = [];
  List<dynamic> filteredUsers = [];
  List<String> departments = [];
  String? selectedDepartment;
  final TextEditingController _searchController = TextEditingController();
  bool isLoading = true;
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
    fetchUsers();
  }

  Future<void> fetchUsers() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/users'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          // Filter out current user and inactive users
          allUsers = (data['data'] as List<dynamic>)
              .where((user) => 
                user['status'] != 0 && 
                user['employeeID'].toString() != widget.currentUserId
              )
              .toList();
          filteredUsers = allUsers;
          // Extract unique departments
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

  void _startChat(Map<String, dynamic> user) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => DirectMessagePage(
          recipientId: user['employeeID'].toString(),
          recipientName: user['fullNameThai'] ?? user['fullName'] ?? 'ไม่ระบุชื่อ',
          recipientImage: user['imgUrl'],
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
      appBar: AppBar(
        title: const Text(
          'เลือกผู้ใช้',
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
                            
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: theme.dividerColor.withOpacity(0.1),
                                ),
                              ),
                              child: InkWell(
                                onTap: () => _startChat(user),
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
                                            Text(
                                              user['fullNameThai'] ?? user['fullName'] ?? 'ไม่ระบุชื่อ',
                                              style: theme.textTheme.titleMedium?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
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
                                      Icon(
                                        Icons.chat_bubble_outline,
                                        color: theme.colorScheme.primary,
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
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
  }
} 