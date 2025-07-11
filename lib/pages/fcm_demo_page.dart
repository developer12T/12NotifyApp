import 'package:flutter/material.dart';
import '../services/fcm_service.dart';

class FCMDemoPage extends StatefulWidget {
  const FCMDemoPage({super.key});

  @override
  State<FCMDemoPage> createState() => _FCMDemoPageState();
}

class _FCMDemoPageState extends State<FCMDemoPage> {
  String? _fcmToken;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _getFCMToken();
  }

  Future<void> _getFCMToken() async {
    setState(() {
      _isLoading = true;
    });

    try {
      String? token = await FCMService.getToken();
      setState(() {
        _fcmToken = token;
        _isLoading = false;
      });
      print('FCM Token: $token');
    } catch (e) {
      print('Error getting FCM token: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _subscribeToTopic() async {
    try {
      await FCMService.subscribeToTopic('announcements');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subscribed to announcements topic')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error subscribing: $e')),
      );
    }
  }

  Future<void> _unsubscribeFromTopic() async {
    try {
      await FCMService.unsubscribeFromTopic('announcements');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unsubscribed from announcements topic')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error unsubscribing: $e')),
      );
    }
  }

  Future<void> _testFCMSetup() async {
    try {
      await FCMService.testFCMSetup();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('FCM Test completed - check console logs')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('FCM Test error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FCM Demo'),
        backgroundColor: const Color(0xFF00569D),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FCM Token',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_isLoading)
                      const CircularProgressIndicator()
                    else if (_fcmToken != null)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: SelectableText(
                          _fcmToken!,
                          style: const TextStyle(fontSize: 12),
                        ),
                      )
                    else
                      const Text('No token available'),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _getFCMToken,
                      child: const Text('Refresh Token'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Topic Management',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _subscribeToTopic,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Subscribe to Announcements'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _unsubscribeFromTopic,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Unsubscribe'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
                                const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Testing',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _testFCMSetup,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Test FCM Setup'),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'To test FCM notifications:\n'
                              '1. Use Firebase Console to send a test message\n'
                              '2. Or use your server to send FCM messages\n'
                              '3. Check the console logs for notification events',
                              style: TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
          ],
        ),
      ),
    );
  }
} 