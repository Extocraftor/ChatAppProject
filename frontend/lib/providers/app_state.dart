import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/chat_models.dart';

class AppState extends ChangeNotifier {
  // static const String baseUrl = "http://127.0.0.1:8000";
  // static const String wsUrl = "ws://127.0.0.1:8000/ws";
  static const String baseUrl = "https://extochatapp.onrender.com";
  static const String wsUrl = "wss://extochatapp.onrender.com/ws";

  static const Map<String, dynamic> _rtcConfiguration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
  };

  User? currentUser;
  List<Channel> channels = [];
  Channel? activeChannel;
  WebSocketChannel? _channel;
  List<Message> messages = [];

  List<VoiceChannel> voiceChannels = [];
  VoiceChannel? activeVoiceChannel;
  final Map<int, VoiceParticipant> voiceParticipants = {};
  WebSocketChannel? _voiceSignalChannel;
  MediaStream? _localStream;
  final Map<int, RTCPeerConnection> _peerConnections = {};
  final Map<int, MediaStream> _remoteStreams = {};
  Future<void>? _leaveVoiceChannelTask;
  bool isSelfMuted = false;
  bool _voiceConnecting = false;
  String? voiceError;

  // Interaction state
  Message? replyingTo;
  Message? editingMessage;
  int? highlightedMessageId;
  Timer? _highlightTimer;

  // Scrolling
  final ScrollController scrollController = ScrollController();

  bool get isVoiceConnecting => _voiceConnecting;

  Future<String?> register(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/users/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"username": username, "password": password}),
      );

      if (response.statusCode == 200) {
        return null;
      }

      try {
        final data = jsonDecode(response.body);
        return data['detail'] ?? "Registration failed";
      } catch (_) {
        return "Server error (Non-JSON): ${response.body}";
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
        await fetchVoiceChannels();
        notifyListeners();
        return null;
      }

      final data = jsonDecode(response.body);
      return data['detail'] ?? "Login failed";
    } catch (_) {
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
        await fetchChannels();
        return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> createVoiceChannel(String name, String? description) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/voice-channels/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"name": name, "description": description}),
      );

      if (response.statusCode == 200) {
        await fetchVoiceChannels();
        return true;
      }

      return false;
    } catch (_) {
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

  Future<void> fetchVoiceChannels() async {
    final response = await http.get(Uri.parse("$baseUrl/voice-channels/"));
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      voiceChannels = data.map((c) => VoiceChannel.fromJson(c)).toList();

      if (activeVoiceChannel != null) {
        final stillExists =
            voiceChannels.any((c) => c.id == activeVoiceChannel!.id);
        if (!stillExists) {
          await leaveVoiceChannel();
        }
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

  Future<bool> joinVoiceChannel(VoiceChannel channel) async {
    if (currentUser == null) {
      return false;
    }

    if (activeVoiceChannel?.id == channel.id && _voiceSignalChannel != null) {
      return true;
    }

    await leaveVoiceChannel(notify: false);

    _voiceConnecting = true;
    voiceError = null;
    notifyListeners();

    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });

      activeVoiceChannel = channel;
      _voiceSignalChannel = WebSocketChannel.connect(
        Uri.parse("$wsUrl/voice/${channel.id}/${currentUser!.id}"),
      );

      _voiceSignalChannel!.stream.listen(
        (data) {
          unawaited(_handleVoiceSignal(data));
        },
        onDone: () {
          _handleVoiceSocketClosed();
        },
        onError: (error) {
          _handleVoiceSocketClosed(error: error);
        },
        cancelOnError: true,
      );

      _voiceConnecting = false;
      notifyListeners();
      return true;
    } catch (e) {
      voiceError = "Unable to join voice channel: $e";
      _voiceConnecting = false;
      await leaveVoiceChannel(notify: false, clearError: false);
      notifyListeners();
      return false;
    }
  }

  void _handleVoiceSocketClosed({Object? error}) {
    if (activeVoiceChannel == null) {
      return;
    }

    voiceError = error == null
        ? "Voice channel disconnected"
        : "Voice connection error: $error";

    unawaited(leaveVoiceChannel(notify: true, clearError: false));
  }

  Future<void> _handleVoiceSignal(dynamic data) async {
    try {
      final Map<String, dynamic> payload = jsonDecode(data);
      final type = payload['type'];

      if (type == 'voice_state') {
        final participants = (payload['participants'] as List<dynamic>? ?? [])
            .whereType<Map<dynamic, dynamic>>()
            .map((p) => VoiceParticipant.fromJson(Map<String, dynamic>.from(p)))
            .toList();

        voiceParticipants
          ..clear()
          ..addEntries(participants.map((p) => MapEntry(p.userId, p)));

        notifyListeners();
        return;
      }

      if (type == 'participant_joined') {
        final participant = VoiceParticipant.fromJson(payload);
        voiceParticipants[participant.userId] = participant;

        if (participant.userId != currentUser?.id) {
          await _createOfferForUser(participant.userId);
        }

        notifyListeners();
        return;
      }

      if (type == 'participant_left') {
        final userId = payload['user_id'];
        if (userId is int) {
          voiceParticipants.remove(userId);
          await _closePeerConnection(userId);
          notifyListeners();
        }
        return;
      }

      if (type == 'mute_state') {
        final userId = payload['user_id'];
        final isMuted = payload['is_muted'] == true;
        if (userId is int) {
          final current = voiceParticipants[userId];
          if (current != null) {
            voiceParticipants[userId] = current.copyWith(isMuted: isMuted);
          }
          notifyListeners();
        }
        return;
      }

      if (type == 'offer') {
        await _handleOffer(payload);
        return;
      }

      if (type == 'answer') {
        await _handleAnswer(payload);
        return;
      }

      if (type == 'ice_candidate') {
        await _handleRemoteIceCandidate(payload);
        return;
      }
    } catch (_) {
      // Ignore malformed signaling payloads.
    }
  }

  Future<RTCPeerConnection> _ensurePeerConnection(int remoteUserId) async {
    final existing = _peerConnections[remoteUserId];
    if (existing != null) {
      return existing;
    }

    final peerConnection = await createPeerConnection(_rtcConfiguration);
    _peerConnections[remoteUserId] = peerConnection;

    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        await peerConnection.addTrack(track, _localStream!);
      }
    }

    peerConnection.onIceCandidate = (candidate) {
      final candidateValue = candidate.candidate;
      if (candidateValue == null || candidateValue.isEmpty) {
        return;
      }

      _sendVoiceSignal({
        'type': 'ice_candidate',
        'target_user_id': remoteUserId,
        'candidate': {
          'candidate': candidateValue,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    peerConnection.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStreams[remoteUserId] = event.streams.first;
      }
    };

    peerConnection.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        unawaited(_closePeerConnection(remoteUserId));
        notifyListeners();
      }
    };

    return peerConnection;
  }

  Future<void> _createOfferForUser(int remoteUserId) async {
    if (currentUser == null || remoteUserId == currentUser!.id) {
      return;
    }

    final peerConnection = await _ensurePeerConnection(remoteUserId);

    final offer = await peerConnection.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });

    await peerConnection.setLocalDescription(offer);

    _sendVoiceSignal({
      'type': 'offer',
      'target_user_id': remoteUserId,
      'sdp': {
        'sdp': offer.sdp,
        'type': offer.type,
      },
    });
  }

  Future<void> _handleOffer(Map<String, dynamic> payload) async {
    final fromUserId = payload['from_user_id'];
    final sdpData = payload['sdp'];

    if (fromUserId is! int || sdpData is! Map<dynamic, dynamic>) {
      return;
    }
    final normalizedSdp = Map<String, dynamic>.from(sdpData);

    final remoteSdp = normalizedSdp['sdp'];
    final remoteType = normalizedSdp['type'];
    if (remoteSdp is! String || remoteType is! String) {
      return;
    }

    final peerConnection = await _ensurePeerConnection(fromUserId);
    await peerConnection.setRemoteDescription(
      RTCSessionDescription(remoteSdp, remoteType),
    );

    final answer = await peerConnection.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });

    await peerConnection.setLocalDescription(answer);

    _sendVoiceSignal({
      'type': 'answer',
      'target_user_id': fromUserId,
      'sdp': {
        'sdp': answer.sdp,
        'type': answer.type,
      },
    });
  }

  Future<void> _handleAnswer(Map<String, dynamic> payload) async {
    final fromUserId = payload['from_user_id'];
    final sdpData = payload['sdp'];

    if (fromUserId is! int || sdpData is! Map<dynamic, dynamic>) {
      return;
    }
    final normalizedSdp = Map<String, dynamic>.from(sdpData);

    final peerConnection = _peerConnections[fromUserId];
    if (peerConnection == null) {
      return;
    }

    final remoteSdp = normalizedSdp['sdp'];
    final remoteType = normalizedSdp['type'];
    if (remoteSdp is! String || remoteType is! String) {
      return;
    }

    await peerConnection.setRemoteDescription(
      RTCSessionDescription(remoteSdp, remoteType),
    );
  }

  Future<void> _handleRemoteIceCandidate(Map<String, dynamic> payload) async {
    final fromUserId = payload['from_user_id'];
    final candidateData = payload['candidate'];

    if (fromUserId is! int || candidateData is! Map<dynamic, dynamic>) {
      return;
    }
    final normalizedCandidate = Map<String, dynamic>.from(candidateData);

    final candidate = normalizedCandidate['candidate'];
    final sdpMid = normalizedCandidate['sdpMid'];
    final sdpMLineIndex = normalizedCandidate['sdpMLineIndex'];

    if (candidate is! String) {
      return;
    }

    final peerConnection = await _ensurePeerConnection(fromUserId);
    await peerConnection.addCandidate(
      RTCIceCandidate(
        candidate,
        sdpMid is String ? sdpMid : null,
        sdpMLineIndex is int ? sdpMLineIndex : null,
      ),
    );
  }

  void _sendVoiceSignal(Map<String, dynamic> payload) {
    final signalChannel = _voiceSignalChannel;
    if (signalChannel == null) {
      return;
    }

    signalChannel.sink.add(jsonEncode(payload));
  }

  void toggleMute() {
    final stream = _localStream;
    if (stream == null || currentUser == null) {
      return;
    }

    isSelfMuted = !isSelfMuted;

    for (final track in stream.getAudioTracks()) {
      track.enabled = !isSelfMuted;
    }

    final selfParticipant = voiceParticipants[currentUser!.id];
    if (selfParticipant != null) {
      voiceParticipants[currentUser!.id] =
          selfParticipant.copyWith(isMuted: isSelfMuted);
    }

    _sendVoiceSignal({
      'type': 'mute_state',
      'is_muted': isSelfMuted,
    });

    notifyListeners();
  }

  Future<void> leaveVoiceChannel(
      {bool notify = true, bool clearError = true}) async {
    final existingTask = _leaveVoiceChannelTask;
    if (existingTask != null) {
      await existingTask;
      if (notify) {
        notifyListeners();
      }
      return;
    }

    final task = _leaveVoiceChannelInternal(
      notify: notify,
      clearError: clearError,
    );
    _leaveVoiceChannelTask = task;

    try {
      await task;
    } finally {
      if (identical(_leaveVoiceChannelTask, task)) {
        _leaveVoiceChannelTask = null;
      }
    }
  }

  Future<void> _leaveVoiceChannelInternal({
    required bool notify,
    required bool clearError,
  }) async {
    if (clearError) {
      voiceError = null;
    }

    final signalChannel = _voiceSignalChannel;
    _voiceSignalChannel = null;

    _voiceConnecting = false;
    activeVoiceChannel = null;
    isSelfMuted = false;

    if (signalChannel != null) {
      await signalChannel.sink.close();
    }

    for (final userId in _peerConnections.keys.toList()) {
      await _closePeerConnection(userId);
    }

    _peerConnections.clear();

    for (final stream in _remoteStreams.values.toSet()) {
      await _disposeStreamSafely(stream);
    }
    _remoteStreams.clear();

    final localStream = _localStream;
    _localStream = null;
    if (localStream != null) {
      await _disposeStreamSafely(localStream);
    }

    voiceParticipants.clear();

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> _closePeerConnection(int remoteUserId) async {
    final peerConnection = _peerConnections.remove(remoteUserId);
    if (peerConnection != null) {
      peerConnection.onIceCandidate = null;
      peerConnection.onTrack = null;
      peerConnection.onConnectionState = null;
      await _closePeerConnectionSafely(peerConnection);
    }

    final remoteStream = _remoteStreams.remove(remoteUserId);
    if (remoteStream != null) {
      await _disposeStreamSafely(remoteStream);
    }
  }

  Future<void> _closePeerConnectionSafely(
      RTCPeerConnection peerConnection) async {
    try {
      await peerConnection.close();
    } catch (_) {
      // Ignore already-closed peer connections during teardown races.
    }
  }

  Future<void> _disposeStreamSafely(MediaStream stream) async {
    for (final track in stream.getTracks()) {
      try {
        track.stop();
      } catch (_) {
        // Track may already be stopped by the platform.
      }
    }

    try {
      await stream.dispose();
    } catch (error) {
      if (!_isMissingStreamError(error)) {
        rethrow;
      }
    }
  }

  bool _isMissingStreamError(Object error) {
    if (error is PlatformException) {
      final code = error.code.toLowerCase();
      final message = (error.message ?? '').toLowerCase();
      return code.contains('mediastreamdisposefailed') &&
          message.contains('not found');
    }

    final errorText = error.toString().toLowerCase();
    return errorText.contains('mediastreamdisposefailed') &&
        errorText.contains('not found');
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
    if (content.isEmpty || _channel == null) {
      return;
    }

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
    _channel?.sink.close();
    _voiceSignalChannel?.sink.close();

    for (final peerConnection in _peerConnections.values) {
      peerConnection.onIceCandidate = null;
      peerConnection.onTrack = null;
      peerConnection.onConnectionState = null;
      unawaited(_closePeerConnectionSafely(peerConnection));
    }

    for (final stream in _remoteStreams.values.toSet()) {
      unawaited(_disposeStreamSafely(stream));
    }

    final localStream = _localStream;
    if (localStream != null) {
      unawaited(_disposeStreamSafely(localStream));
    }

    _peerConnections.clear();
    _remoteStreams.clear();
    _localStream = null;
    scrollController.dispose();
    _highlightTimer?.cancel();
    super.dispose();
  }
}
