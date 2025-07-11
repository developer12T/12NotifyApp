import 'package:flutter/material.dart';

class LoadingPage extends StatefulWidget {
  final VoidCallback onFinish;
  const LoadingPage({super.key, required this.onFinish});

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      widget.onFinish();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 24),
            Text(
              'กำลังโหลดข้อมูล...'
              ,style: TextStyle(fontSize: 18, color: const Color(0xFF00569D)),
            ),
          ],
        ),
      ),
    );
  }
}
