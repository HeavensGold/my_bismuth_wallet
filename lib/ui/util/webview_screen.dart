import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:my_bismuth_wallet/appstate_container.dart';
import 'package:my_bismuth_wallet/styles.dart';

class WebViewScreen extends StatefulWidget {
  final String url;
  final String title;

  const WebViewScreen({
    Key? key,
    required this.url,
    required this.title,
  }) : super(key: key);

  @override
  _WebViewScreenState createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _errorMessage = 'Failed to load page: ${error.description}';
              });
            }
          },
        ),
      );

    // Load the URL
    _controller.loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: StateContainer.of(context).curTheme.backgroundDark,
        iconTheme: IconThemeData(
          color: StateContainer.of(context).curTheme.text,
        ),
        title: Text(
          widget.title.isNotEmpty ? widget.title : 'Explorer',
          style: TextStyle(
            color: StateContainer.of(context).curTheme.text,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              _controller.reload();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_errorMessage != null)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: StateContainer.of(context).curTheme.text60,
                  ),
                  SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: AppStyles.textStyleParagraph(context),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _errorMessage = null;
                        _isLoading = true;
                      });
                      _controller.reload();
                    },
                    child: Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          StateContainer.of(context).curTheme.primary,
                    ),
                  ),
                ],
              ),
            )
          else
            WebViewWidget(controller: _controller),
          if (_isLoading && _errorMessage == null)
            Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  StateContainer.of(context).curTheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
