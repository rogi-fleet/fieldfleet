import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Wraps its [child] with a slim "No internet connection" banner at the top
/// whenever the device has no network. The banner auto-dismisses when
/// connectivity is restored.
class ConnectivityBanner extends StatefulWidget {
  final Widget child;

  const ConnectivityBanner({super.key, required this.child});

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner>
    with SingleTickerProviderStateMixin {
  bool _isOffline = false;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  late final AnimationController _controller;
  late final Animation<double> _heightAnimation;
  Timer? _offlineTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _heightAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    try {
      _subscription = Connectivity()
          .onConnectivityChanged
          .listen(_handleConnectivityChange);

      // Check initial connectivity state
      Connectivity().checkConnectivity().then(_handleConnectivityChange);
    } catch (_) {
      // connectivity_plus may throw on unsupported platforms; banner stays hidden
    }
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final offline = results.isEmpty ||
        (results.length == 1 && results.first == ConnectivityResult.none);

    if (!offline) {
      // Came back online — cancel any pending offline timer immediately
      _offlineTimer?.cancel();
      _offlineTimer = null;
      if (_isOffline) {
        setState(() => _isOffline = false);
        _controller.reverse();
      }
      return;
    }

    if (_isOffline) return; // Already showing banner

    // Debounce: only show banner if still offline after 3 seconds.
    // Prevents false-positives on Flutter web where navigator.onLine briefly
    // flips during failed network requests (e.g. a storage upload error).
    _offlineTimer?.cancel();
    _offlineTimer = Timer(const Duration(seconds: 3), () async {
      if (!mounted) return;
      // The browser NetworkInformation API behind connectivity_plus can
      // falsely report "none" (seen after file-chooser focus changes). Trust
      // it only when an actual request also fails.
      if (await _isActuallyReachable()) return;
      if (!mounted) return;
      setState(() => _isOffline = true);
      _controller.forward();
    });
  }

  /// Real reachability probe: on web fetch our own origin (cache-busted), on
  /// mobile/desktop fall back to the connectivity_plus verdict re-checked.
  Future<bool> _isActuallyReachable() async {
    try {
      if (kIsWeb) {
        final probe = Uri.base.replace(
          path: '/favicon.png',
          queryParameters: {
            'connectivity': DateTime.now().millisecondsSinceEpoch.toString(),
          },
        );
        final response = await http
            .get(probe)
            .timeout(const Duration(seconds: 4));
        return response.statusCode < 500;
      }
      final recheck = await Connectivity().checkConnectivity();
      return !(recheck.isEmpty ||
          (recheck.length == 1 && recheck.first == ConnectivityResult.none));
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _offlineTimer?.cancel();
    _subscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizeTransition(
          sizeFactor: _heightAnimation,
          axisAlignment: -1,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: double.infinity,
              color: Colors.grey.shade800,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top,
                bottom: 8,
                left: 16,
                right: 16,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.wifi_off, size: 14, color: Colors.white70),
                  const SizedBox(width: 8),
                  const Text(
                    'No internet connection',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
