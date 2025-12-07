/// Platform-agnostic interface for UDP sending
abstract class UdpSender {
  /// Send bytes to the specified address and port
  void send(List<int> data, String address, int port);
  
  /// Close the UDP socket
  void close();
}
