import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/chat_models.dart';
import '../utils/ws_channel_factory.dart';

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
  Timer? _voicePingTimer;
  MediaStream? _localStream;
  final Map<int, RTCPeerConnection> _peerConnections = {};
  final Map<int, MediaStream> _remoteStreams = {};
  Future<void>? _leaveVoiceChannelTask;
  bool isSelfMuted = false;
  bool _voiceConnecting = false;
  bool _voiceJoinInProgress = false;
  String? voiceError;
  Timer? _voiceDiagnosticsTimer;
  bool _voiceDiagnosticsInFlight = false;
  final Map<int, DateTime> _pendingVoicePings = {};
  final Map<int, RTCPeerConnectionState> _peerConnectionStates = {};
  int _voicePingSequence = 0;
  int? _voicePingMs;
  DateTime? _voiceConnectedAt;
  DateTime? _lastVoicePongAt;
  double _voiceMicLevel = 0;
  double _voiceOutboundBitrateKbps = 0;
  double _voiceOutboundPacketsPerSecond = 0;
  int? _lastStatsBytesSent;
  int? _lastStatsPacketsSent;
  DateTime? _lastStatsSnapshotAt;

  // Interaction state
  Message? replyingTo;
  Message? editingMessage;
  int? highlightedMessageId;
  Timer? _highlightTimer;

  // Scrolling
  final ScrollController scrollController = ScrollController();

  bool get isVoiceConnecting => _voiceConnecting;
  bool get isVoiceSignalConnected =>
      activeVoiceChannel != null &&
      _voiceSignalChannel != null &&
      !_voiceConnecting;
  String get voiceSignalStatusLabel {
    if (_voiceConnecting) {
      return "Connecting";
    }
    if (isVoiceSignalConnected) {
      return "Connected";
    }
    if (activeVoiceChannel != null) {
      return "Disconnected";
    }
    return "Idle";
  }

  int? get voicePingMs => _voicePingMs;
  DateTime? get voiceConnectedAt => _voiceConnectedAt;
  DateTime? get lastVoicePongAt => _lastVoicePongAt;
  double get voiceMicLevel => _voiceMicLevel;
  double get voiceOutboundBitrateKbps => _voiceOutboundBitrateKbps;
  double get voiceOutboundPacketsPerSecond => _voiceOutboundPacketsPerSecond;
  int get activePeerConnectionCount => _peerConnections.length;
  int get remoteStreamCount => _remoteStreams.length;
  Map<int, RTCPeerConnectionState> get peerConnectionStates =>
      Map.unmodifiable(_peerConnectionStates);
  bool get hasLocalAudioTrack =>
      _localStream?.getAudioTracks().isNotEmpty == true;
  bool get isLocalMicTrackEnabled =>
      _localStream?.getAudioTracks().any((track) => track.enabled) == true;

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

    _channel = createWsChannel(
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

    if (_voiceJoinInProgress) {
      return false;
    }

    if (activeVoiceChannel?.id == channel.id && _voiceSignalChannel != null) {
      return true;
    }

    _voiceJoinInProgress = true;
    await leaveVoiceChannel(notify: false);

    _voiceConnecting = true;
    voiceError = null;
    notifyListeners();

    var failedStep = 'getUserMedia';
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });

      failedStep = 'signal connection';
      activeVoiceChannel = channel;
      final signalChannel = createWsChannel(
        Uri.parse("$wsUrl/voice/${channel.id}/${currentUser!.id}"),
      );
      await signalChannel.ready;
      _voiceSignalChannel = signalChannel;
      _voiceConnectedAt = DateTime.now();
      _resetVoiceDiagnostics();
      _startVoicePing();
      _startVoiceDiagnostics();

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
    } catch (e, stackTrace) {
      debugPrint('joinVoiceChannel failed during $failedStep: $e');
      debugPrintStack(stackTrace: stackTrace);
      voiceError = "Unable to join voice channel ($failedStep): $e";
      _voiceConnecting = false;
      await leaveVoiceChannel(notify: false, clearError: false);
      notifyListeners();
      return false;
    } finally {
      _voiceJoinInProgress = false;
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

      if (type == 'pong') {
        _handleVoicePong(payload);
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
    _peerConnectionStates[remoteUserId] =
        RTCPeerConnectionState.RTCPeerConnectionStateNew;

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
        notifyListeners();
      }
    };

    peerConnection.onConnectionState = (state) {
      _peerConnectionStates[remoteUserId] = state;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        unawaited(_closePeerConnection(remoteUserId));
      }
      notifyListeners();
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
    _voicePingTimer?.cancel();
    _voicePingTimer = null;
    _voiceDiagnosticsTimer?.cancel();
    _voiceDiagnosticsTimer = null;
    _voiceDiagnosticsInFlight = false;

    if (clearError) {
      voiceError = null;
    }

    final signalChannel = _voiceSignalChannel;
    _voiceSignalChannel = null;

    _voiceConnecting = false;
    activeVoiceChannel = null;
    isSelfMuted = false;
    _voiceConnectedAt = null;
    _resetVoiceDiagnostics();

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
    _peerConnectionStates.clear();

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

    _peerConnectionStates.remove(remoteUserId);

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

  void sendVoicePingNow() {
    _sendVoicePing();
  }

  void _startVoicePing() {
    _voicePingTimer?.cancel();
    _sendVoicePing();
    _voicePingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_voiceSignalChannel == null) {
        _voicePingTimer?.cancel();
        _voicePingTimer = null;
        return;
      }

      _sendVoicePing();
    });
  }

  void _sendVoicePing() {
    if (_voiceSignalChannel == null) {
      return;
    }

    _voicePingSequence += 1;
    final pingId = _voicePingSequence;
    _pendingVoicePings[pingId] = DateTime.now();

    if (_pendingVoicePings.length > 8) {
      final oldestPingId =
          _pendingVoicePings.keys.reduce((a, b) => a < b ? a : b);
      _pendingVoicePings.remove(oldestPingId);
    }

    _sendVoiceSignal({
      'type': 'ping',
      'ping_id': pingId,
    });
  }

  void _handleVoicePong(Map<String, dynamic> payload) {
    final now = DateTime.now();
    DateTime? pingSentAt;

    final pingId = _parseIntMetric(payload['ping_id']);
    if (pingId != null) {
      pingSentAt = _pendingVoicePings.remove(pingId);
    }

    if (pingSentAt == null && _pendingVoicePings.isNotEmpty) {
      final oldestPingId =
          _pendingVoicePings.keys.reduce((a, b) => a < b ? a : b);
      pingSentAt = _pendingVoicePings.remove(oldestPingId);
    }

    if (pingSentAt != null) {
      _voicePingMs = now.difference(pingSentAt).inMilliseconds;
    }

    _lastVoicePongAt = now;
    notifyListeners();
  }

  void _startVoiceDiagnostics() {
    _voiceDiagnosticsTimer?.cancel();
    _voiceDiagnosticsTimer =
        Timer.periodic(const Duration(milliseconds: 700), (_) {
      unawaited(_refreshVoiceDiagnostics());
    });
    unawaited(_refreshVoiceDiagnostics());
  }

  Future<void> _refreshVoiceDiagnostics() async {
    if (_voiceDiagnosticsInFlight ||
        _voiceSignalChannel == null ||
        activeVoiceChannel == null) {
      return;
    }

    _voiceDiagnosticsInFlight = true;
    try {
      final now = DateTime.now();
      final localAudioTracks =
          _localStream?.getAudioTracks() ?? <MediaStreamTrack>[];
      final localMicEnabled = localAudioTracks.any((track) => track.enabled);

      double? strongestAudioLevel;
      bool voiceActivity = false;
      int totalBytesSent = 0;
      int totalPacketsSent = 0;
      int? peerRttMs;

      for (final peerConnection in _peerConnections.values) {
        List<StatsReport> reports;
        try {
          reports = await peerConnection.getStats();
        } catch (_) {
          continue;
        }

        for (final report in reports) {
          final values = report.values;
          final reportType =
              (_readStringMetric(values, ['type']) ?? report.type)
                  .toLowerCase();
          final kind = _readStringMetric(
            values,
            ['kind', 'mediaType', 'media_type'],
          )?.toLowerCase();
          final isAudio = kind == 'audio' ||
              ((values['id']?.toString().toLowerCase().contains('audio')) ??
                  false);

          final audioLevel = _parseDoubleMetric(
            values['audioLevel'] ?? values['audio_level'],
          );
          if (audioLevel != null &&
              (reportType == 'media-source' ||
                  reportType == 'track' ||
                  reportType == 'outbound-rtp' ||
                  isAudio)) {
            if (strongestAudioLevel == null ||
                audioLevel > strongestAudioLevel) {
              strongestAudioLevel = audioLevel;
            }
          }

          final voiceActivityFlag =
              values['voiceActivityFlag'] ?? values['voice_activity_flag'];
          if (voiceActivityFlag == true ||
              voiceActivityFlag.toString().toLowerCase() == 'true') {
            voiceActivity = true;
          }

          if (reportType == 'outbound-rtp' && isAudio) {
            totalBytesSent +=
                _parseIntMetric(values['bytesSent'] ?? values['bytes_sent']) ??
                    0;
            totalPacketsSent += _parseIntMetric(
                  values['packetsSent'] ?? values['packets_sent'],
                ) ??
                0;
          }

          final currentRoundTripTime = _parseDoubleMetric(
            values['currentRoundTripTime'] ??
                values['roundTripTime'] ??
                values['round_trip_time'],
          );
          if (currentRoundTripTime != null &&
              currentRoundTripTime > 0 &&
              (reportType == 'candidate-pair' ||
                  reportType == 'remote-inbound-rtp')) {
            final rttMs = currentRoundTripTime > 10
                ? currentRoundTripTime.round()
                : (currentRoundTripTime * 1000).round();
            if (peerRttMs == null || rttMs < peerRttMs) {
              peerRttMs = rttMs;
            }
          }
        }
      }

      double targetMicLevel = 0;
      if (localMicEnabled && !isSelfMuted) {
        if (strongestAudioLevel != null) {
          targetMicLevel = strongestAudioLevel.clamp(0, 1).toDouble();
        } else if (voiceActivity) {
          targetMicLevel = 0.65;
        } else if (_lastStatsPacketsSent != null &&
            totalPacketsSent > _lastStatsPacketsSent!) {
          targetMicLevel = 0.35;
        }
      }

      final smoothedMicLevel =
          (_voiceMicLevel * 0.6 + targetMicLevel * 0.4).clamp(0.0, 1.0);

      double bitrateKbps = _voiceOutboundBitrateKbps;
      double packetsPerSecond = _voiceOutboundPacketsPerSecond;

      if (_lastStatsSnapshotAt != null &&
          _lastStatsBytesSent != null &&
          _lastStatsPacketsSent != null &&
          totalBytesSent >= _lastStatsBytesSent! &&
          totalPacketsSent >= _lastStatsPacketsSent!) {
        final elapsedMs = now.difference(_lastStatsSnapshotAt!).inMilliseconds;
        if (elapsedMs > 0) {
          final elapsedSeconds = elapsedMs / 1000;
          final byteDelta = totalBytesSent - _lastStatsBytesSent!;
          final packetDelta = totalPacketsSent - _lastStatsPacketsSent!;
          bitrateKbps = (byteDelta * 8) / elapsedSeconds / 1000;
          packetsPerSecond = packetDelta / elapsedSeconds;
        }
      } else {
        bitrateKbps = 0;
        packetsPerSecond = 0;
      }

      _lastStatsBytesSent = totalBytesSent;
      _lastStatsPacketsSent = totalPacketsSent;
      _lastStatsSnapshotAt = now;

      final pingFromPeerStats =
          (_voicePingMs == null || _voicePingMs == 0) ? peerRttMs : null;
      final hasMeaningfulChange =
          (_voiceMicLevel - smoothedMicLevel).abs() > 0.02 ||
              (_voiceOutboundBitrateKbps - bitrateKbps).abs() > 2 ||
              (_voiceOutboundPacketsPerSecond - packetsPerSecond).abs() > 0.5 ||
              pingFromPeerStats != null;

      _voiceMicLevel = smoothedMicLevel;
      _voiceOutboundBitrateKbps = bitrateKbps;
      _voiceOutboundPacketsPerSecond = packetsPerSecond;
      if (pingFromPeerStats != null) {
        _voicePingMs = pingFromPeerStats;
      }

      if (hasMeaningfulChange) {
        notifyListeners();
      }
    } finally {
      _voiceDiagnosticsInFlight = false;
    }
  }

  void _resetVoiceDiagnostics() {
    _pendingVoicePings.clear();
    _voicePingSequence = 0;
    _voicePingMs = null;
    _lastVoicePongAt = null;
    _voiceMicLevel = 0;
    _voiceOutboundBitrateKbps = 0;
    _voiceOutboundPacketsPerSecond = 0;
    _lastStatsBytesSent = null;
    _lastStatsPacketsSent = null;
    _lastStatsSnapshotAt = null;
  }

  String? _readStringMetric(Map<dynamic, dynamic> values, List<String> keys) {
    for (final key in keys) {
      final value = values[key];
      if (value != null) {
        final asString = value.toString();
        if (asString.isNotEmpty) {
          return asString;
        }
      }
    }
    return null;
  }

  int? _parseIntMetric(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  double? _parseDoubleMetric(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
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
    _voicePingTimer?.cancel();
    _voicePingTimer = null;
    _voiceDiagnosticsTimer?.cancel();
    _voiceDiagnosticsTimer = null;

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
    _peerConnectionStates.clear();
    _remoteStreams.clear();
    _pendingVoicePings.clear();
    _localStream = null;
    scrollController.dispose();
    _highlightTimer?.cancel();
    super.dispose();
  }
}
