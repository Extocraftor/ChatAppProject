import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel createWsChannel(Uri uri) {
  final socketFuture = WebSocket.connect(
    uri.toString(),
    compression: CompressionOptions.compressionOff,
  ).then((socket) {
    socket.pingInterval = const Duration(seconds: 15);
    return socket;
  });

  return IOWebSocketChannel(socketFuture);
}
