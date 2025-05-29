import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AnnouncementDetailPage extends StatelessWidget {
  final Map<String, dynamic> announcement;
  const AnnouncementDetailPage({Key? key, required this.announcement}) : super(key: key);

  String formatThaiDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      const thaiMonths = [
        '',
        'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
        'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'
      ];
      final day = date.day;
      final month = thaiMonths[date.month];
      final year = date.year + 543;
      return '$day $month $year';
    } catch (e) {
      return dateString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(announcement['title'] ?? 'รายละเอียดประกาศ'),
        backgroundColor: const Color(0xFF00569D),
        foregroundColor: Colors.white,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 700;
          if (isWide) {
            // Desktop/Tablet: รูปซ้าย ข้อความขวา
            return Padding(
              padding: const EdgeInsets.all(32),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image (left)
                  if (announcement['imageUrl'] != null && announcement['imageUrl'].toString().isNotEmpty)
                    Expanded(
                      flex: 2,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          '${ApiService.baseUrl}${announcement['imageUrl']}',
                          fit: BoxFit.contain,
                          height: constraints.maxHeight > 0
                              ? (constraints.maxHeight * 0.7).clamp(200, 800)
                              : 350,
                          width: double.infinity,
                        ),
                      ),
                    ),
                  const SizedBox(width: 32),
                  // Text content (right)
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          announcement['title'] ?? '',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 28,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          announcement['content'] ?? '',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontSize: 18,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (announcement['createdAt'] != null)
                          Text(
                            'วันที่ประกาศ: ${formatThaiDate(announcement['createdAt'])}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 16),
                          ),
                        if (announcement['createdBy'] != null)
                          Text(
                            'โดย: ' +
                              (announcement['createdBy'] is Map
                                ? (announcement['createdBy']['fullNameThai'] ??
                                   announcement['createdBy']['fullName'] ??
                                   'Unknown')
                                : (announcement['createdBy']?.toString() ?? 'Unknown')),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 16),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          } else {
            // Mobile: เดิม
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (announcement['imageUrl'] != null && announcement['imageUrl'].toString().isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        '${ApiService.baseUrl}${announcement['imageUrl']}',
                        fit: BoxFit.contain,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    announcement['title'] ?? '',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    announcement['content'] ?? '',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  if (announcement['createdAt'] != null)
                    Text(
                      'วันที่ประกาศ: ${formatThaiDate(announcement['createdAt'])}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (announcement['createdBy'] != null)
                    Text(
                      'โดย: ' +
                        (announcement['createdBy'] is Map
                          ? (announcement['createdBy']['fullNameThai'] ??
                             announcement['createdBy']['fullName'] ??
                             'Unknown')
                          : (announcement['createdBy']?.toString() ?? 'Unknown')),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            );
          }
        },
      ),
    );
  }
} 