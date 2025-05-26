import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'dart:io' show Platform;
import 'pages/login_page.dart';
import 'pages/main_navigation.dart';
import 'pages/chat_page.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'services/notification_service.dart'; 

class CustomDebugBanner extends StatelessWidget {
  const CustomDebugBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Banner(
      message: 'ALPHA-TEST',
      location: BannerLocation.topStart,
      color: Colors.red,
      child: Container(),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load .env file
  await dotenv.load(fileName: ".env");
  
  // เริ่มต้นการแจ้งเตือนเฉพาะบน platform ที่รองรับ
  if (Platform.isAndroid || Platform.isIOS) {
    final notificationService = NotificationService();
    await notificationService.init();
  }
  
  final prefs = await SharedPreferences.getInstance();
  final userData = prefs.getString('user');

  runApp(MyApp(initialRoute: userData != null ? '/main' : '/login'));
}

class MyApp extends StatelessWidget {
  final String initialRoute;

  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NotiOneTwo',
      debugShowCheckedModeBanner: false,  // ปิด debug banner ปกติ
      builder: (context, child) {
        return Banner(
          message: 'ALPHA-TEST',
          location: BannerLocation.bottomEnd,
          color: Colors.red,
          child: child!,
        );
      },
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF004B93)),
        useMaterial3: true,
      ),
      initialRoute: initialRoute,
      routes: {
        '/login': (context) => const LoginPage(),
        '/main': (context) => const MainNavigation(),
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        title: Text(widget.title + ' 12Trading'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('token');
              await prefs.remove('user');
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
