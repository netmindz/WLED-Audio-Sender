/// Platform-agnostic interface for UDP sending
abstract class UdpSender {
  /// Send bytes to the specified address and port
  void send(List<int> data, String address, int port);
  
  /// Close the UDP socket
  void close();
  
  /// Factory constructor to create the appropriate implementation
  /// based on the platform
  factory UdpSender() {
    if (identical(0, 0.0)) {
      // JavaScript numbers (web platform)
      return _createWebSender();
    } else {
      // Dart VM (native platforms)
      return _createNativeSender();
    }
  }
  
  static UdpSender _createWebSender() => throw UnsupportedError(
    'Cannot create UDP sender without the correct platform implementation');
  
  static UdpSender _createNativeSender() => throw UnsupportedError(
    'Cannot create UDP sender without the correct platform implementation');
}
