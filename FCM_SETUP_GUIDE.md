# FCM (Firebase Cloud Messaging) Setup Guide

## 1. Dependencies Installation

Run this command to install Firebase dependencies:
```bash
flutter pub get
```

## 2. Firebase Project Setup

### Step 1: Create Firebase Project
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project or select existing project
3. Add your Android app to the project

### Step 2: Download Configuration Files

**For Android:**
1. Download `google-services.json` from Firebase Console
2. Place it in `android/app/google-services.json`

**For iOS:**
1. Download `GoogleService-Info.plist` from Firebase Console
2. Place it in `ios/Runner/GoogleService-Info.plist`

## 3. Android Configuration

### Build.gradle Files Updated ✅
- `android/app/build.gradle.kts` - Added Google Services plugin
- `android/build.gradle.kts` - Added buildscript dependencies

### AndroidManifest.xml Updated ✅
- Added FCM service configuration
- All required permissions are already present

## 4. iOS Configuration (if needed)

Add to `ios/Runner/Info.plist`:
```xml
<key>FirebaseAppDelegateProxyEnabled</key>
<false/>
```

## 5. Code Integration

### Main App Initialization ✅
The FCM service is already integrated in `lib/main.dart`:
```dart
// เริ่มต้น FCM Service
await FCMService.initialize();
```

### FCM Service Features ✅
- Background message handling
- Foreground message handling
- Token management
- Topic subscription
- Notification tap handling

## 6. Testing FCM

### Method 1: Firebase Console
1. Go to Firebase Console > Messaging
2. Send test message to your device
3. Check console logs for notification events

### Method 2: Server Integration
Send FCM message from your server:
```json
{
  "to": "FCM_TOKEN_HERE",
  "notification": {
    "title": "Test Title",
    "body": "Test Body"
  },
  "data": {
    "chat_id": "123",
    "type": "message"
  }
}
```

### Method 3: Demo Page
Use the FCM Demo page to test:
- Get FCM token
- Subscribe/unsubscribe to topics
- View token information

## 7. Server Integration

### Save FCM Token to Database
Update the `_saveTokenToDatabase` method in `lib/services/fcm_service.dart`:

```dart
static Future<void> _saveTokenToDatabase(String token) async {
  try {
    final response = await http.post(
      Uri.parse('https://your-api.com/save-fcm-token'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'user_id': getCurrentUserId(),
        'fcm_token': token,
        'platform': Platform.isAndroid ? 'android' : 'ios',
        'app_version': '1.0.0',
      }),
    );
    
    if (response.statusCode == 200) {
      print('FCMService: Token saved successfully');
    } else {
      print('FCMService: Failed to save token: ${response.statusCode}');
    }
  } catch (e) {
    print('FCMService: Error saving token: $e');
  }
}
```

### Send FCM Messages from Server
Example using Node.js:
```javascript
const admin = require('firebase-admin');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});

// Send message to specific token
async function sendNotification(token, title, body, data = {}) {
  const message = {
    notification: {
      title: title,
      body: body,
    },
    data: data,
    token: token,
  };

  try {
    const response = await admin.messaging().send(message);
    console.log('Successfully sent message:', response);
  } catch (error) {
    console.log('Error sending message:', error);
  }
}

// Send to topic
async function sendToTopic(topic, title, body, data = {}) {
  const message = {
    notification: {
      title: title,
      body: body,
    },
    data: data,
    topic: topic,
  };

  try {
    const response = await admin.messaging().send(message);
    console.log('Successfully sent message to topic:', response);
  } catch (error) {
    console.log('Error sending message to topic:', error);
  }
}
```

## 8. Notification Handling

### Background Notifications ✅
- Automatically handled by `_firebaseMessagingBackgroundHandler`
- Shows local notification when app is closed

### Foreground Notifications ✅
- Handled by `_handleForegroundMessage`
- Shows local notification when app is open

### Notification Tap Handling ✅
- Handles taps when app is terminated
- Handles taps when app is in background
- Navigates to appropriate screen based on data

## 9. Troubleshooting

### Common Issues:
1. **Token not generated**: Check Firebase configuration files
2. **Notifications not showing**: Check notification permissions
3. **Background not working**: Verify service in AndroidManifest.xml
4. **iOS not working**: Check APNs configuration

### Debug Commands:
```bash
# Check if dependencies are installed
flutter pub deps

# Clean and rebuild
flutter clean
flutter pub get
flutter run
```

## 10. Next Steps

1. **Test the integration** using the demo page
2. **Configure your server** to send FCM messages
3. **Customize notification handling** for your app's needs
4. **Add topic subscriptions** for different user groups
5. **Implement token refresh** handling on your server

## Files Modified/Created:
- ✅ `lib/services/fcm_service.dart` - FCM service implementation
- ✅ `lib/main.dart` - FCM initialization
- ✅ `android/app/build.gradle.kts` - Google Services plugin
- ✅ `android/build.gradle.kts` - Buildscript dependencies
- ✅ `android/app/src/main/AndroidManifest.xml` - FCM service
- ✅ `lib/pages/fcm_demo_page.dart` - Demo page for testing
- ✅ `FCM_SETUP_GUIDE.md` - This setup guide 