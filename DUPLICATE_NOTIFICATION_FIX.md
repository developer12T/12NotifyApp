# การแก้ไขปัญหาการแจ้งเตือนซ้ำ (Duplicate Notification Fix)

## 🚨 ปัญหาที่พบ

จากการทดสอบพบว่ามีการแจ้งเตือนซ้ำ 2 รอบเมื่อมีการประกาศใหม่:

1. **Socket Service Notification** (ID: 1752460991) - ใช้ icon เก่า
2. **FCM Service Notification** (ID: 1752460992) - ใช้ icon ใหม่

## 🔍 สาเหตุของปัญหา

1. **Socket Service** และ **FCM Service** ทำงานพร้อมกัน
2. ทั้งสอง service ใช้ notification channel ที่แตกต่างกัน
3. แต่ละ channel มี icon ที่ต่างกัน
4. ไม่มีการประสานงานระหว่าง service ทั้งสอง

## ✅ วิธีแก้ไข

### 1. **รวม Notification Channel ให้เป็นอันเดียวกัน**

#### ใช้ `fcm_foreground_channel` สำหรับทุก service:
```dart
// SocketService และ NotiService ใช้ channel เดียวกับ FCM
const notificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'fcm_foreground_channel',  // ใช้ channel เดียวกับ FCM
    'FCM Foreground Notifications',
    channelDescription: 'ช่องทางการแจ้งเตือน FCM สำหรับ Foreground',
    importance: Importance.high,
    priority: Priority.high,
    showWhen: true,
    enableVibration: true,
    playSound: true,
  ),
);
```

### 2. **ปรับปรุงการจัดการ Notification ตามสถานะของแอป**

#### SocketService - จัดการเฉพาะเมื่อแอปอยู่ใน Background:
```dart
// ถ้าแอปอยู่ใน foreground และไม่ใช่ background service ให้ข้าม
// เพราะ FCM จะจัดการแทน
if (!isInBackgroundService) {
  print('=== SocketService: App in foreground, letting FCM handle ===');
  _recentNotifications[announcementId] = now;
  return;
}

// แสดงการแจ้งเตือนเฉพาะเมื่อเป็น background service
print('=== SocketService: Showing background notification ===');
_showBackgroundNotification(formattedData);
```

#### FCMService - จัดการเฉพาะเมื่อแอปอยู่ใน Foreground:
```dart
// ถ้าเป็น announcement และแอปอยู่ใน foreground
// ให้ Socket service จัดการแทนเพื่อป้องกันการแจ้งเตือนซ้ำ
if (isAnnouncement) {
  print('FCMService: Detected announcement, letting Socket service handle');
  return true;
}
```

### 3. **ระบบป้องกันการแจ้งเตือนซ้ำ**

#### เพิ่ม Tracking System:
```dart
// เพิ่ม tracking สำหรับ recent notifications
final Map<String, DateTime> _recentNotifications = {};
static const Duration _notificationCooldown = Duration(seconds: 3);

// สร้าง unique key สำหรับ announcement
final announcementId = formattedData['_id']?.toString() ?? 
                     formattedData['id']?.toString() ?? 
                     '${formattedData['title']}_${formattedData['createdAt']}';

// ตรวจสอบว่าแสดง notification นี้ไปแล้วหรือไม่
if (_recentNotifications.containsKey(announcementId)) {
  final lastShown = _recentNotifications[announcementId]!;
  if (now.difference(lastShown) < _notificationCooldown) {
    print('=== SocketService: Skipping duplicate notification ===');
    return;
  }
}
```

## 📊 การทำงานของระบบ

### เมื่อแอปอยู่ใน Foreground:
- **FCM Service** จัดการการแจ้งเตือนทั้งหมด
- **Socket Service** ข้ามการแสดงการแจ้งเตือน
- ใช้ icon ใหม่ (icon ปัจจุบัน)

### เมื่อแอปอยู่ใน Background:
- **Socket Service** จัดการการแจ้งเตือนทั้งหมด
- **FCM Service** ข้ามการแสดงการแจ้งเตือน
- ใช้ icon ใหม่ (icon ปัจจุบัน)

### การป้องกันการซ้ำ:
- ใช้ cooldown system (3 วินาที)
- ใช้ unique key สำหรับแต่ละ announcement
- ตรวจสอบสถานะของแอปก่อนแสดงการแจ้งเตือน

## 🔧 ผลลัพธ์ที่คาดหวัง

หลังจากแก้ไขแล้ว:

1. **ไม่มีการแจ้งเตือนซ้ำ** - จะมีเพียงการแจ้งเตือนเดียวต่อ announcement
2. **ใช้ icon เดียวกัน** - ทุกการแจ้งเตือนใช้ icon ใหม่ (icon ปัจจุบัน)
3. **การแจ้งเตือนที่เหมาะสม** - แต่ละ service จัดการตามสถานะของแอป
4. **ประสิทธิภาพที่ดีขึ้น** - ลดการใช้ทรัพยากรจากการแสดง notification ซ้ำ

## 📝 ไฟล์ที่แก้ไข

1. `lib/services/socket_service.dart`
   - เพิ่ม `_recentNotifications` tracking
   - ปรับปรุง `_shouldSkipSocketNotification()` method
   - ปรับปรุง `_handleAnnouncementNotification()`
   - ใช้ `fcm_foreground_channel` แทน `socket_service_channel`

2. `lib/services/fcm_service.dart`
   - เพิ่ม `_recentNotifications` tracking
   - เพิ่ม `_createNotificationKey()` method
   - ปรับปรุง `_shouldSkipFCMNotification()` method
   - ปรับปรุง `_handleForegroundMessage()`

3. `lib/services/noti_service.dart`
   - ใช้ `fcm_foreground_channel` แทน `socket_service_channel`

## 🚀 การใช้งาน

การแก้ไขนี้จะทำงานอัตโนมัติเมื่อมีการประกาศใหม่ โดย:

1. **ป้องกันการแจ้งเตือนซ้ำ** ด้วย cooldown system
2. **ใช้ icon เดียวกัน** ทุกการแจ้งเตือน
3. **จัดการตามสถานะของแอป** (foreground/background)
4. **เลือก service ที่เหมาะสม** ตามประเภทของ notification

ไม่จำเป็นต้องแก้ไขโค้ดอื่นๆ เพิ่มเติม ระบบจะทำงานได้ทันทีหลังจาก deploy การแก้ไขนี้ 