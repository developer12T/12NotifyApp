import 'package:flutter/material.dart';

class SideNavigation extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemTapped;
  final String userName;
  final int announcementBadgeCount;

  const SideNavigation({
    Key? key,
    required this.selectedIndex,
    required this.onItemTapped,
    required this.userName,
    this.announcementBadgeCount = 0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      color: const Color(0xFF26334D),
      child: Column(
        children: [
          // Navigation icons (top)
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Column(
              children: [
                _buildNavIcon(
                  context,
                  icon: Icons.notifications_active,
                  index: 0,
                  badge: announcementBadgeCount,
                  tooltip: 'ประกาศ',
                ),
                const SizedBox(height: 12),
                _buildNavIcon(
                  context,
                  icon: Icons.people_alt,
                  index: 1,
                  tooltip: 'กลุ่ม',
                ),
                const SizedBox(height: 12),
                _buildNavIcon(
                  context,
                  icon: Icons.question_answer,
                  index: 2,
                  tooltip: 'แชท',
                ),
                const SizedBox(height: 12),
                _buildNavIcon(
                  context,
                  icon: Icons.account_circle_rounded,
                  index: 3,
                  tooltip: 'ข้อมูลส่วนตัว',
                ),
              ],
            ),
          ),
          const Spacer(),
          // Logout (bottom) - temporarily commented out
          /*
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: IconButton(
              icon: const Icon(Icons.logout, color: Colors.white70, size: 24),
              tooltip: 'ออกจากระบบ',
              onPressed: () {
                // ควรให้ main_navigation จัดการ logout จริง
                // สามารถใช้ callback หรือ context.read ได้ถ้าต้องการ
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('กดออกจากระบบ')),
                );
              },
            ),
          ),
          */
        ],
      ),
    );
  }

  Widget _buildNavIcon(
    BuildContext context, {
    required IconData icon,
    required int index,
    String? tooltip,
    int badge = 0,
  }) {
    final bool isSelected = selectedIndex == index;
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onItemTapped(index),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isSelected ? Colors.white.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : Colors.white70,
                size: 24,
              ),
              if (badge > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 14,
                    ),
                    child: Text(
                      badge > 99 ? '99+' : badge.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
} 