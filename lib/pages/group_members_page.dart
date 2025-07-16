import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/api_service.dart';

class GroupMembersPage extends StatefulWidget {
  final String roomId;
  const GroupMembersPage({Key? key, required this.roomId}) : super(key: key);

  @override
  State<GroupMembersPage> createState() => _GroupMembersPageState();
}

class _GroupMembersPageState extends State<GroupMembersPage> {
  List<dynamic> members = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchMembers();
  }

  Future<void> fetchMembers() async {
    setState(() { isLoading = true; });
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/rooms/${widget.roomId}'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('API Response: $data'); // Debug log
        
        // ตรวจสอบข้อมูลรูปภาพ
        for (var member in data['data']['members'] ?? []) {
          print('Member: ${member['fullName']}');
          print('Profile Image: ${member['profileImage']}');
        }
        
        setState(() {
          members = data['data']['members'] ?? [];
          isLoading = false;
        });
      } else {
        setState(() { isLoading = false; });
      }
    } catch (e) {
      print('Fetch members error: $e');
      setState(() { isLoading = false; });
    }
  }

  String getRoleLabel(String? role) {
    switch (role?.toLowerCase()) {
      case 'owner': return 'เจ้าของ';
      case 'admin': return 'สมาชิก';
      default: return 'สมาชิก';
    }
  }

  Color getRoleColor(BuildContext context, String? role) {
    final theme = Theme.of(context);
    switch (role?.toLowerCase()) {
      case 'owner': return theme.colorScheme.primary;
      case 'admin': return Colors.grey;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('สมาชิกในกลุ่ม'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 1,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : members.isEmpty
              ? const Center(child: Text('ไม่พบสมาชิกในกลุ่ม'))
              : SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.group, color: theme.colorScheme.primary, size: 28),
                            const SizedBox(width: 8),
                            Text(
                              'สมาชิกในกลุ่ม',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                                fontSize: 20,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                '${members.length} คน',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: members.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final member = members[index];
                            return Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        image: member['profileImage'] != null && member['profileImage'].toString().isNotEmpty
                                          ? DecorationImage(
                                              image: NetworkImage(member['profileImage']),
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                        color: theme.colorScheme.primary.withOpacity(0.1),
                                      ),
                                      child: member['profileImage'] == null || member['profileImage'].toString().isEmpty
                                          ? const Icon(Icons.person, size: 28)
                                          : null,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            member['fullName'] ?? '-',
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            member['department'] ?? '-',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: getRoleColor(context, member['role']).withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        getRoleLabel(member['role']),
                                        style: TextStyle(
                                          color: getRoleColor(context, member['role']),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
} 