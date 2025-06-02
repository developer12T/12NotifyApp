import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DirectMessagePage extends StatefulWidget {
  final String recipientId;
  final String recipientName;
  final String? recipientImage;

  const DirectMessagePage({
    super.key,
    required this.recipientId,
    required this.recipientName,
    this.recipientImage,
  });

  @override
  State<DirectMessagePage> createState() => _DirectMessagePageState();
}

class _DirectMessagePageState extends State<DirectMessagePage> {

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  bool isSending = false;
  final String currentUserId = 'EMP001';


 
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = MediaQuery.of(context).size.width > 600;
    
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.engineering,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text(
              'ยังไม่พร้อมใช้งาน',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

