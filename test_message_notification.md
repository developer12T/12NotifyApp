# การทดสอบการแจ้งเตือนข้อความใหม่

## 🎯 เป้าหมาย
ทดสอบการแจ้งเตือนข้อความใหม่ในห้องแชท

## 📋 ขั้นตอนการทดสอบ

### ขั้นตอนที่ 1: เตรียมการ
1. รันแอป
2. เข้าหน้า "กลุ่ม"
3. ตรวจสอบ logs ต่อไปนี้:
   - `=== _handleChatRoomEntry called ===`
   - `Current chat room ID before: ""`
   - `User left chat room: null`

### ขั้นตอนที่ 2: เข้าห้องแชท
1. กดเข้าไปในห้องแชท A
2. ตรวจสอบ logs:
   - `=== _handleChatRoomEntry called ===`
   - `Room ID: "room_id_here"`
   - `Current chat room ID after entering: "room_id_here"`

### ขั้นตอนที่ 3: ออกจากห้องแชท
1. กดปุ่ม back เพื่อออกจากห้องแชท
2. ตรวจสอบ logs:
   - `=== _handleChatRoomEntry called ===`
   - `Room ID: ""`
   - `Current chat room ID after leaving: null`

### ขั้นตอนที่ 4: ส่งข้อความจากอุปกรณ์อื่น
1. ใช้อุปกรณ์อื่นหรือบอทส่งข้อความในห้อง A
2. ตรวจสอบ logs:
   - `=== รับข้อความใหม่ ===`
   - `=== New Message in Room room_id_here ===`
   - `=== _isUserInChatRoom Check ===`
   - `Is user in chat room: false`
   - `User not in chat room, showing notification`
   - `Calling onNewMessageNotification with count: X`
   - `onNewMessageNotification called successfully`

### ขั้นตอนที่ 5: ตรวจสอบการแจ้งเตือน
1. ตรวจสอบว่ามีการแจ้งเตือนปรากฏหรือไม่
2. ตรวจสอบ logs:
   - `=== handleNewMessageNotification called ===`
   - `Type: room`
   - `Unread count: X`
   - `Showing notification...`
   - `Message notification sent successfully`

## 🔍 การ Debug

### หากไม่มีการแจ้งเตือน

#### ตรวจสอบ 1: การออกจากห้องแชท
- ตรวจสอบว่า `_handleChatRoomEntry` ถูกเรียกเมื่อออกจากห้อง
- ตรวจสอบว่า `_currentChatRoomId` ถูกตั้งเป็น `null`

#### ตรวจสอบ 2: การรับข้อความใหม่
- ตรวจสอบว่า `newMessage` event ถูกรับ
- ตรวจสอบว่า `_handleNewMessage` ถูกเรียก
- ตรวจสอบว่า `_isUserInChatRoom` return `false`

#### ตรวจสอบ 3: การเรียก callback
- ตรวจสอบว่า `onNewMessageNotification` callback ไม่เป็น `null`
- ตรวจสอบว่า callback ถูกเรียกด้วย count ที่ถูกต้อง

#### ตรวจสอบ 4: การแสดงการแจ้งเตือน
- ตรวจสอบว่า `handleNewMessageNotification` ถูกเรียก
- ตรวจสอบว่า `_showMessageNotification` ถูกเรียก
- ตรวจสอบว่า `NotificationService.showNotification` ถูกเรียก

## 📝 Logs ที่ต้องตรวจสอบ

### เมื่อออกจากห้องแชท:
```
=== _handleChatRoomEntry called ===
Room ID: ""
Current chat room ID before: "room_id_here"
User left chat room: room_id_here
Current chat room ID after leaving: "null"
```

### เมื่อรับข้อความใหม่:
```
=== รับข้อความใหม่ ===
=== New Message in Room room_id_here ===
=== _isUserInChatRoom Check ===
Checking room ID: "room_id_here"
Current chat room ID: "null"
Is user in chat room: false
User not in chat room, showing notification
Calling onNewMessageNotification with count: 1
onNewMessageNotification callback exists: true
onNewMessageNotification called successfully
```

### เมื่อแสดงการแจ้งเตือน:
```
=== handleNewMessageNotification called ===
Type: room
Unread count: 1
App in foreground: true
Showing notification...
Message notification sent successfully
```

## 🚨 ปัญหาที่อาจเกิดขึ้น

### ปัญหา 1: ไม่มีการเรียก _handleChatRoomEntry
**สาเหตุ**: `onEnterChatRoom` callback ไม่ถูกส่งหรือไม่ทำงาน
**แก้ไข**: ตรวจสอบการส่ง callback ใน `chat_page.dart`

### ปัญหา 2: _currentChatRoomId ไม่ถูก reset
**สาเหตุ**: `_handleChatRoomEntry` ไม่ทำงานเมื่อออกจากห้อง
**แก้ไข**: ตรวจสอบการเรียก callback เมื่อ dispose

### ปัญหา 3: _isUserInChatRoom return true
**สาเหตุ**: `_currentChatRoomId` ไม่เป็น `null` เมื่อออกจากห้อง
**แก้ไข**: ตรวจสอบการ reset ใน `_handleChatRoomEntry`

### ปัญหา 4: onNewMessageNotification เป็น null
**สาเหตุ**: callback ไม่ถูกส่งจาก `main_navigation.dart`
**แก้ไข**: ตรวจสอบการส่ง callback ใน `RoomPage`

### ปัญหา 5: handleNewMessageNotification ไม่ถูกเรียก
**สาเหตุ**: callback ไม่ทำงาน
**แก้ไข**: ตรวจสอบการส่ง callback ใน `main_navigation.dart` 