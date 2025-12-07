import 'dart:io';
import 'udp_sender.dart';

/// Native (non-web) implementation of UDP sender using dart:io
class NativeUdpSender implements UdpSender {
  RawDatagramSocket? _socket;
  
  NativeUdpSender() {
    RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)
        .then((RawDatagramSocket s) {
      _socket = s;
    });
  }
  
  @override
  void send(List<int> data, String address, int port) {
    _socket?.send(data, InternetAddress(address), port);
  }
  
  @override
  void close() {
    _socket?.close();
  }
}

UdpSender createUdpSender() => NativeUdpSender();
