import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/chat_models.dart';

class AppState extends ChangeNotifier {
  // static const String baseUrl = "http://127.0.0.1:8000";
  // static const String wsUrl = "ws://127.0.0.1:8000/ws";
  static const String baseUrl = "https://extochatapp.onrender.com";
  static const String wsUrl = "wss://extochatapp.onrender.com/ws";

  User? currentUser;
  List<Channel> channels = [];
  Channel? activeChannel;
  WebSocketChannel? _channel;
  List<Message> messages = [];

  // Interaction state
  Message? replyingTo;
  Message? editingMessage;
  int? highlightedMessageId;
  Timer? _highlightTimer;

  // Scrolling
  final ScrollController scrollController = ScrollController();

  Future<String?> register(String username, String password) async {
    try {
      print("Attempting to register at: $baseUrl/users/");
      final response = await http.post(
        Uri.parse("$baseUrl/users/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"username": username, "password": password}),
      );

      print("Server Response Status: ${response.statusCode}");
      print("Server Response Body: ${response.body}");

      if (response.statusCode == 200) {
        return null; // Success
      } else {
        try {
          final data = jsonDecode(response.body);
          return data['detail'] ?? "Registration failed";
        } catch (e) {
          return "Server error (Non-JSON): ${response.body}";
        }
      }
    } catch (e) {
      return "Connection error: $e";
    }
  }

  Future<String?> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/login/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"username": username, "password": password}),
      );
      if (response.statusCode == 200) {
        currentUser = User.fromJson(jsonDecode(response.body));
        await fetchChannels();
        notifyListeners();
        return null; // Success
      } else {
        final data = jsonDecode(response.body);
        return data['detail'] ?? "Login failed";
      }
    } catch (e) {
      return "Connection error";
    }
  }

  Future<bool> createChannel(String name, String? description) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/channels/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"name": name, "description": description}),
      );
      if (response.statusCode == 200) {
        await fetchChannels(); // Refresh list
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> fetchChannels() async {
    final response = await http.get(Uri.parse("$baseUrl/channels/"));
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      channels = data.map((c) => Channel.fromJson(c)).toList();
      if (channels.isNotEmpty && activeChannel == null) {
        selectChannel(channels.first);
      }
      notifyListeners();
    }
  }

  Future<void> fetchMessages(int channelId) async {
    final response =
        await http.get(Uri.parse("$baseUrl/channels/$channelId/messages/"));
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      messages = data.map((m) => Message.fromJson(m)).toList();
      notifyListeners();
      _scrollToBottom();
    }
  }

  void selectChannel(Channel channel) {
    activeChannel = channel;
    messages = [];
    replyingTo = null;
    editingMessage = null;
    _channel?.sink.close();

    fetchMessages(channel.id);

    _channel = WebSocketChannel.connect(
      Uri.parse("$wsUrl/${channel.id}/${currentUser!.id}"),
    );

    _channel!.stream.listen((data) {
      final json = jsonDecode(data);
      final type = json['type'] ?? 'new_message';

      if (type == 'new_message') {
        final newMessage = Message.fromJson(json);
        messages.add(newMessage);
        _scrollToBottom();
      } else if (type == 'edit_message') {
        final id = json['id'];
        final content = json['content'];
        final index = messages.indexWhere((m) => m.id == id);
        if (index != -1) {
          messages[index] = messages[index].copyWith(content: content);
        }
      } else if (type == 'delete_message') {
        final id = json['id'];
        messages.removeWhere((m) => m.id == id);
      }
      notifyListeners();
    });

    notifyListeners();
  }

  void setReplyingTo(Message? message) {
    replyingTo = message;
    editingMessage = null;
    notifyListeners();
  }

  void setEditingMessage(Message? message) {
    editingMessage = message;
    replyingTo = null;
    notifyListeners();
  }

  void highlightMessage(int id) {
    highlightedMessageId = id;
    notifyListeners();

    scrollToMessage(id);

    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      highlightedMessageId = null;
      notifyListeners();
    });
  }

  void scrollToMessage(int id) {
    final index = messages.indexWhere((m) => m.id == id);
    if (index != -1 && scrollController.hasClients) {
      final position = index * 60.0;
      scrollController.animateTo(
        position,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void sendMessage(String content) {
    if (content.isEmpty || _channel == null) return;

    if (editingMessage != null) {
      final messageData = {
        "type": "edit_message",
        "id": editingMessage!.id,
        "content": content,
      };
      _channel!.sink.add(jsonEncode(messageData));
      editingMessage = null;
    } else {
      final messageData = {
        "type": "new_message",
        "content": content,
        "parent_id": replyingTo?.id,
      };
      _channel!.sink.add(jsonEncode(messageData));
      replyingTo = null;
    }
    notifyListeners();
  }

  void deleteMessage(int messageId) {
    if (_channel != null) {
      final messageData = {
        "type": "delete_message",
        "id": messageId,
      };
      _channel!.sink.add(jsonEncode(messageData));
    }
  }

  @override
  void dispose() {
    scrollController.dispose();
    _highlightTimer?.cancel();
    super.dispose();
  }
}
