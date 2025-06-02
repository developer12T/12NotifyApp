import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;

class WebViewPage extends StatefulWidget {
  final String url;
  final String title;

  const WebViewPage({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String _currentTitle = '';
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    _currentTitle = widget.title;
    _initializeController();
  }

  void _initializeController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            print('WebView: Page started loading: $url');
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) async {
            print('WebView: Page finished loading: $url');
            setState(() {
              _isLoading = false;
            });
            
            // อัพเดท navigation state
            final canGoBack = await _controller.canGoBack();
            final canGoForward = await _controller.canGoForward();
            setState(() {
              _canGoBack = canGoBack;
              _canGoForward = canGoForward;
            });

            // อัพเดท title
            final title = await _controller.getTitle();
            if (title != null && title.isNotEmpty) {
              setState(() {
                _currentTitle = title;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            print('WebView error: ${error.description}');
            print('Error code: ${error.errorCode}');
            print('Error type: ${error.errorType}');
            print('URL: ${error.url}');
            
            String errorMessage = 'เกิดข้อผิดพลาดในการโหลดหน้าเว็บ';
            
            // แปลง error code เป็นข้อความที่เข้าใจง่าย
            switch (error.errorCode) {
              case -1:
                errorMessage = 'ไม่สามารถเชื่อมต่อกับเซิร์ฟเวอร์ได้';
                break;
              case -2:
                errorMessage = 'ไม่พบหน้าเว็บที่ต้องการ';
                break;
              case -3:
                errorMessage = 'การเชื่อมต่อถูกยกเลิก';
                break;
              case -4:
                errorMessage = 'ไม่สามารถเข้าถึงอินเทอร์เน็ตได้';
                break;
              case -5:
                errorMessage = 'ไม่สามารถเข้าถึง URL ได้ (ERR_CLEARTEXT_NOT_PERMITTED)';
                break;
              case -6:
                errorMessage = 'การเชื่อมต่อหมดเวลา';
                break;
              case -7:
                errorMessage = 'ไม่สามารถเข้าถึงเซิร์ฟเวอร์ได้';
                break;
              case -8:
                errorMessage = 'การเชื่อมต่อถูกปฏิเสธ';
                break;
              case -9:
                errorMessage = 'URL ไม่ถูกต้อง';
                break;
              case -10:
                errorMessage = 'ไม่สามารถเข้าถึงไฟล์ได้';
                break;
              case -11:
                errorMessage = 'การเชื่อมต่อถูกบล็อก';
                break;
              case -12:
                errorMessage = 'ไม่สามารถเข้าถึงเซิร์ฟเวอร์ได้';
                break;
              case -13:
                errorMessage = 'การเชื่อมต่อถูกยกเลิก';
                break;
              case -14:
                errorMessage = 'ไม่สามารถเข้าถึงเซิร์ฟเวอร์ได้';
                break;
              case -15:
                errorMessage = 'ไม่สามารถเข้าถึงเซิร์ฟเวอร์ได้';
                break;
              case -16:
                errorMessage = 'ไม่สามารถเข้าถึงเซิร์ฟเวอร์ได้';
                break;
              case -17:
                errorMessage = 'ไม่สามารถเข้าถึงเซิร์ฟเวอร์ได้';
                break;
              case -18:
                errorMessage = 'ไม่สามารถเข้าถึงเซิร์ฟเวอร์ได้';
                break;
              case -19:
                errorMessage = 'ไม่สามารถเข้าถึงเซิร์ฟเวอร์ได้';
                break;
              case -20:
                errorMessage = 'ไม่สามารถเข้าถึงเซิร์ฟเวอร์ได้';
                break;
              case -21:
                errorMessage = 'ไม่สามารถเข้าถึงเซิร์ฟเวอร์ได้';
                break;
              case -22:
                errorMessage = 'ไม่สามารถเข้าถึงเซิร์ฟเวอร์ได้';
                break;
              case -23:
                errorMessage = 'ไม่สามารถเข้าถึงเซิร์ฟเวอร์ได้';
                break;
              case -24:
                errorMessage = 'ไม่สามารถเข้าถึงเซิร์ฟเวอร์ได้';
                break;
              case -25:
                errorMessage = 'ไม่สามารถเข้าถึงเซิร์ฟเวอร์ได้';
                break;
              case -26:
                errorMessage = 'ไม่สามารถเข้าถึงเซิร์ฟเวอร์ได้';
                break;
              case -27:
                errorMessage = 'ไม่สามารถเข้าถึงเซิร์ฟเวอร์ได้';
                break;
              case -28:
                errorMessage = 'ไม่สามารถเข้าถึงเซิร์ฟเวอร์ได้';
                break;
              case -29:
                errorMessage = 'ไม่สามารถเข้าถึงเซิร์ฟเวอร์ได้';
                break;
              case -30:
                errorMessage = 'ไม่สามารถเข้าถึงเซิร์ฟเวอร์ได้';
                break;
              default:
                errorMessage = 'เกิดข้อผิดพลาด: ${error.description}';
            }

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(errorMessage),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 5),
                  action: SnackBarAction(
                    label: 'เปิดในเบราว์เซอร์',
                    textColor: Colors.white,
                    onPressed: () async {
                      try {
                        final uri = Uri.parse(widget.url);
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } catch (e) {
                        print('Error launching external browser: $e');
                      }
                    },
                  ),
                ),
              );
            }
          },
          onNavigationRequest: (NavigationRequest request) async {
            print('WebView: Navigation requested to: ${request.url}');
            
            // ถ้าเป็น Windows ให้เปิดใน Chrome
            if (Platform.isWindows) {
              try {
                final uri = Uri.parse(request.url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                  return NavigationDecision.prevent; // ป้องกันการโหลดใน WebView
                }
              } catch (e) {
                print('Error launching external browser: $e');
              }
            }
            
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 1,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentTitle,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.url.isNotEmpty)
              Text(
                Uri.parse(widget.url).host,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // Navigation buttons
          IconButton(
            icon: Icon(
              Icons.arrow_back_ios,
              color: _canGoBack ? Colors.black87 : Colors.grey[400],
            ),
            onPressed: _canGoBack
                ? () async {
                    await _controller.goBack();
                  }
                : null,
          ),
          IconButton(
            icon: Icon(
              Icons.arrow_forward_ios,
              color: _canGoForward ? Colors.black87 : Colors.grey[400],
            ),
            onPressed: _canGoForward
                ? () async {
                    await _controller.goForward();
                  }
                : null,
          ),
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
          // Share/Open in browser
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (String value) async {
              switch (value) {
                case 'refresh':
                  await _controller.reload();
                  break;
                case 'open_browser':
                  // ใช้ url_launcher เพื่อเปิดในเบราว์เซอร์ภายนอก
                  // await launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication);
                  break;
                case 'copy_url':
                  // Copy URL to clipboard
                  // await Clipboard.setData(ClipboardData(text: widget.url));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('คัดลอก URL แล้ว')),
                    );
                  }
                  break;
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 20),
                    SizedBox(width: 12),
                    Text('รีเฟรช'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'open_browser',
                child: Row(
                  children: [
                    Icon(Icons.open_in_browser, size: 20),
                    SizedBox(width: 12),
                    Text('เปิดในเบราว์เซอร์'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'copy_url',
                child: Row(
                  children: [
                    Icon(Icons.copy, size: 20),
                    SizedBox(width: 12),
                    Text('คัดลอก URL'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Container(
              color: Colors.white,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'กำลังโหลด...',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      // เพิ่ม bottom navigation สำหรับการควบคุมพิเศษ
      bottomNavigationBar: Container(
        height: 60,
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: Icon(
                Icons.arrow_back_ios,
                color: _canGoBack ? Colors.blue : Colors.grey[400],
              ),
              onPressed: _canGoBack
                  ? () async {
                      await _controller.goBack();
                    }
                  : null,
              tooltip: 'กลับ',
            ),
            IconButton(
              icon: Icon(
                Icons.arrow_forward_ios,
                color: _canGoForward ? Colors.blue : Colors.grey[400],
              ),
              onPressed: _canGoForward
                  ? () async {
                      await _controller.goForward();
                    }
                  : null,
              tooltip: 'ไปข้างหน้า',
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.blue),
              onPressed: () => _controller.reload(),
              tooltip: 'รีเฟรช',
            ),
            IconButton(
              icon: const Icon(Icons.home, color: Colors.blue),
              onPressed: () => _controller.loadRequest(Uri.parse(widget.url)),
              tooltip: 'หน้าแรก',
            ),
          ],
        ),
      ),
    );
  }
} 