import 'udp_sender.dart';

/// Stub implementation - should never be used
class StubUdpSender implements UdpSender {
  @override
  void send(List<int> data, String address, int port) {
    throw UnsupportedError('UDP sender not available on this platform');
  }
  
  @override
  void close() {
    throw UnsupportedError('UDP sender not available on this platform');
  }
}

UdpSender createUdpSender() => StubUdpSender();
