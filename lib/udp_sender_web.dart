// ignore_for_file: avoid_web_libraries_in_flutter, avoid_print
import 'dart:convert';
import 'dart:html' as html;
import 'udp_sender.dart';

/// Web implementation of UDP sender
/// 
/// Note: Browsers cannot send UDP packets directly due to security restrictions.
/// This implementation provides options:
/// 1. No-op mode (default) - just captures audio without sending
/// 2. WebSocket relay mode - sends to a WebSocket server that relays to UDP
/// 
/// To use WebSocket relay, set the wsRelayUrl before starting audio capture.
class WebUdpSender implements UdpSender {
  html.WebSocket? _webSocket;
  String? wsRelayUrl;
  bool _isConnected = false;
  
  WebUdpSender() {
    // Check if WebSocket relay URL is configured
    // Users can configure this through environment or by modifying the code
    wsRelayUrl = const String.fromEnvironment('WS_RELAY_URL');
    
    if (wsRelayUrl != null && wsRelayUrl!.isNotEmpty) {
      _connectWebSocket();
    } else {
      print('⚠️ Web platform: UDP multicast not available in browsers.');
      print('Audio capture and visualization will work, but packets won\'t be sent.');
      print('To enable UDP sending, set up a WebSocket relay server and configure WS_RELAY_URL.');
    }
  }
  
  void _connectWebSocket() {
    try {
      _webSocket = html.WebSocket(wsRelayUrl!);
      _webSocket!.onOpen.listen((_) {
        _isConnected = true;
        print('✓ Connected to WebSocket relay at $wsRelayUrl');
      });
      _webSocket!.onError.listen((e) {
        print('✗ WebSocket error: $e');
        _isConnected = false;
      });
      _webSocket!.onClose.listen((_) {
        _isConnected = false;
        print('WebSocket connection closed');
      });
    } catch (e) {
      print('Failed to connect to WebSocket relay: $e');
    }
  }
  
  @override
  void send(List<int> data, String address, int port) {
    if (_webSocket != null && _isConnected) {
      // Send packet info and data to WebSocket relay
      // The relay server should forward this as UDP to the specified address:port
      final payload = {
        'address': address,
        'port': port,
        'data': data,
      };
      _webSocket!.send(jsonEncode(payload));
    }
    // If no WebSocket, packets are silently dropped (visualization still works)
  }
  
  @override
  void close() {
    _webSocket?.close();
  }
}

UdpSender createUdpSender() => WebUdpSender();
