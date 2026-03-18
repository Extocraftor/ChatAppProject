import 'package:web_socket_channel/web_socket_channel.dart';

import 'ws_channel_factory_stub.dart'
    if (dart.library.io) 'ws_channel_factory_io.dart'
    if (dart.library.html) 'ws_channel_factory_web.dart' as impl;

WebSocketChannel createWsChannel(Uri uri) => impl.createWsChannel(uri);
