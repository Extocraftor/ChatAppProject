import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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
  final Map<int, RTCVideoRenderer> _remoteAudioRenderers = {};
  final Map<int, double> _voiceParticipantVolumes = {};
  final Map<int, List<RTCIceCandidate>> _queuedRemoteIceCandidates = {};
  final Set<int> _remoteDescriptionReadyUsers = <int>{};
  Future<void> _voiceSignalProcessingQueue = Future.value();
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
  final List<MediaDeviceInfo> _audioInputDevices = [];
  String? _selectedAudioInputDeviceId;
  bool _audioInputDevicesLoading = false;
  bool _audioInputSwitching = false;
  RTCPeerConnection? _micProbeConnection;
  RTCRtpSender? _micProbeRtpSender;
  MediaStreamTrack? _micProbeTrack;
  double? _lastMicEnergy;
  double? _lastMicDuration;
  bool _isInputTestRunning = false;
  bool _isInputTestStarting = false;
  bool _inputTestUsesVoiceStream = false;
  String? _inputTestError;
  double _inputTestLevel = 0;
  MediaStream? _inputTestStream;
  RTCPeerConnection? _inputTestProbeConnection;
  RTCRtpSender? _inputTestProbeRtpSender;
  MediaStreamTrack? _inputTestProbeTrack;
  Timer? _inputTestTimer;
  double? _inputTestLastEnergy;
  double? _inputTestLastDuration;
  double? _inputTestRawAudioLevel;
  double? _inputTestRawEnergy;
  double? _inputTestRawDuration;
  double? _inputTestRawEstimatedLevel;
  bool _inputTestRawVoiceActivity = false;
  String _inputTestLevelSource = "none";
  DateTime? _inputTestLastSampleAt;
  final Map<String, String> _inputTestRawStats = {};

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
  Map<int, RTCVideoRenderer> get remoteAudioRenderers =>
      Map<int, RTCVideoRenderer>.unmodifiable(_remoteAudioRenderers);
  Map<int, RTCPeerConnectionState> get peerConnectionStates =>
      Map.unmodifiable(_peerConnectionStates);
  bool get hasLocalAudioTrack =>
      _localStream?.getAudioTracks().isNotEmpty == true;
  bool get isLocalMicTrackEnabled =>
      _localStream?.getAudioTracks().any((track) => track.enabled) == true;
  List<MediaDeviceInfo> get audioInputDevices =>
      List<MediaDeviceInfo>.unmodifiable(_audioInputDevices);
  String? get selectedAudioInputDeviceId => _selectedAudioInputDeviceId;
  bool get isAudioInputDevicesLoading => _audioInputDevicesLoading;
  bool get isAudioInputSwitching => _audioInputSwitching;
  bool get isInputTestRunning => _isInputTestRunning;
  bool get isInputTestStarting => _isInputTestStarting;
  bool get inputTestUsesVoiceStream => _inputTestUsesVoiceStream;
  String? get inputTestError => _inputTestError;
  double get inputTestLevel => _inputTestLevel;
  double? get inputTestRawAudioLevel => _inputTestRawAudioLevel;
  double? get inputTestRawEnergy => _inputTestRawEnergy;
  double? get inputTestRawDuration => _inputTestRawDuration;
  double? get inputTestRawEstimatedLevel => _inputTestRawEstimatedLevel;
  bool get inputTestRawVoiceActivity => _inputTestRawVoiceActivity;
  String get inputTestLevelSource => _inputTestLevelSource;
  DateTime? get inputTestLastSampleAt => _inputTestLastSampleAt;
  Map<String, String> get inputTestRawStats =>
      Map<String, String>.unmodifiable(_inputTestRawStats);
  Map<int, double> get voiceParticipantVolumes =>
      Map<int, double>.unmodifiable(_voiceParticipantVolumes);
  bool get canModerateChannels {
    final role = currentUser?.role.toLowerCase();
    return role == "admin" || role == "moderator";
  }
  bool canDeleteTextChannel(Channel channel) {
    final userId = currentUser?.id;
    if (userId == null) {
      return false;
    }
    if (canModerateChannels) {
      return true;
    }
    return channel.creatorUserId != null && channel.creatorUserId == userId;
  }

  bool canDeleteVoiceChannel(VoiceChannel channel) {
    final userId = currentUser?.id;
    if (userId == null) {
      return false;
    }
    if (canModerateChannels) {
      return true;
    }
    return channel.creatorUserId != null && channel.creatorUserId == userId;
  }

  double voiceParticipantVolumeFor(int userId) {
    return (_voiceParticipantVolumes[userId] ?? 1.0)
        .clamp(0.0, 2.0)
        .toDouble();
  }

  void setVoiceParticipantVolume(int userId, double volume) {
    final normalized = volume.clamp(0.0, 2.0);
    final previous = voiceParticipantVolumeFor(userId);
    if ((previous - normalized).abs() < 0.001) {
      return;
    }

    if ((normalized - 1.0).abs() < 0.001) {
      _voiceParticipantVolumes.remove(userId);
    } else {
      _voiceParticipantVolumes[userId] = normalized;
    }

    final renderer = _remoteAudioRenderers[userId];
    if (renderer != null) {
      unawaited(_applyRemoteRendererVolume(renderer, normalized));
    }

    notifyListeners();
  }

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
        await refreshAudioInputDevices(notify: false);
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
    final userId = currentUser?.id;
    if (userId == null) {
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/channels/?actor_user_id=$userId"),
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
    final userId = currentUser?.id;
    if (userId == null) {
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/voice-channels/?actor_user_id=$userId"),
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

      if (activeChannel != null) {
        final stillExists = channels.any((c) => c.id == activeChannel!.id);
        if (!stillExists) {
          _channel?.sink.close();
          _channel = null;
          activeChannel = null;
          messages = [];
        }
      }

      if (channels.isNotEmpty && activeChannel == null) {
        selectChannel(channels.first);
        return;
      }
      notifyListeners();
    }
  }

  Future<bool> deleteChannel(int channelId) async {
    final userId = currentUser?.id;
    if (userId == null) {
      return false;
    }

    try {
      final response = await http.delete(
        Uri.parse("$baseUrl/channels/$channelId?actor_user_id=$userId"),
      );
      if (response.statusCode != 200) {
        return false;
      }

      if (activeChannel?.id == channelId) {
        _channel?.sink.close();
        _channel = null;
        activeChannel = null;
        messages = [];
      }

      await fetchChannels();
      return true;
    } catch (_) {
      return false;
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

  Future<void> refreshAudioInputDevices({bool notify = true}) async {
    if (_audioInputDevicesLoading) {
      return;
    }

    _audioInputDevicesLoading = true;
    if (notify) {
      notifyListeners();
    }

    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      final seen = <String>{};
      final inputs = devices.where((device) {
        if (device.kind != 'audioinput') {
          return false;
        }

        final id = device.deviceId;
        if (id.isEmpty || seen.contains(id)) {
          return false;
        }
        seen.add(id);
        return true;
      }).toList();

      _audioInputDevices
        ..clear()
        ..addAll(inputs);

      final selectedExists = _selectedAudioInputDeviceId != null &&
          _audioInputDevices.any(
            (device) => device.deviceId == _selectedAudioInputDeviceId,
          );
      if (!selectedExists) {
        _selectedAudioInputDeviceId = _audioInputDevices.isNotEmpty
            ? _audioInputDevices.first.deviceId
            : null;
      }
    } catch (_) {
      // Ignore device enumeration failures.
    } finally {
      _audioInputDevicesLoading = false;
      if (notify) {
        notifyListeners();
      }
    }
  }

  Future<void> selectAudioInputDevice(String deviceId) async {
    if (deviceId == _selectedAudioInputDeviceId ||
        _audioInputSwitching ||
        _voiceJoinInProgress) {
      return;
    }

    _audioInputSwitching = true;
    _selectedAudioInputDeviceId = deviceId;
    notifyListeners();

    try {
      await _applyAudioInputPreference(deviceId);
      final currentChannel = activeVoiceChannel;
      if (currentChannel != null) {
        final joined =
            await joinVoiceChannel(currentChannel, forceRejoin: true);
        if (!joined && voiceError == null) {
          voiceError = "Unable to switch microphone input";
          notifyListeners();
        }
      }
      if (_isInputTestRunning) {
        await startInputTest(forceRestart: true);
      }
      await refreshAudioInputDevices(notify: false);
    } catch (error) {
      voiceError = "Unable to switch microphone input: $error";
      notifyListeners();
    } finally {
      _audioInputSwitching = false;
      notifyListeners();
    }
  }

  Future<void> startInputTest({bool forceRestart = false}) async {
    if (_isInputTestStarting) {
      return;
    }
    if (_isInputTestRunning && !forceRestart) {
      return;
    }

    _isInputTestStarting = true;
    _inputTestError = null;
    notifyListeners();

    try {
      await stopInputTest(notify: false);

      MediaStream? testStream;
      MediaStreamTrack? testTrack;
      bool usesVoiceStream = false;

      if (_localStream != null && activeVoiceChannel != null) {
        final voiceTracks = _localStream!.getAudioTracks();
        if (voiceTracks.isNotEmpty) {
          usesVoiceStream = true;
          testTrack = voiceTracks.first;
        }
      }

      if (testTrack == null) {
        await refreshAudioInputDevices(notify: false);

        final selectedInputId = _selectedAudioInputDeviceId;
        if (selectedInputId != null && selectedInputId.isNotEmpty) {
          await _applyAudioInputPreference(selectedInputId);
        }

        testStream = await navigator.mediaDevices.getUserMedia({
          'audio': _buildVoiceAudioConstraints(),
          'video': false,
        });
        final testTracks = testStream.getAudioTracks();
        if (testTracks.isEmpty) {
          throw Exception("No audio track returned by microphone");
        }
        testTrack = testTracks.first;
      }

      final probeConnection = await createPeerConnection(_rtcConfiguration);
      final probeSender = await probeConnection.addTrack(
        testTrack,
        usesVoiceStream ? _localStream! : testStream!,
      );
      final offer = await probeConnection.createOffer({
        'offerToReceiveAudio': false,
        'offerToReceiveVideo': false,
      });
      await probeConnection.setLocalDescription(offer);

      _inputTestStream = testStream;
      _inputTestProbeTrack = testTrack;
      _inputTestProbeConnection = probeConnection;
      _inputTestProbeRtpSender = probeSender;
      _inputTestUsesVoiceStream = usesVoiceStream;
      _isInputTestRunning = true;
      _inputTestLevel = 0;
      _inputTestLastEnergy = null;
      _inputTestLastDuration = null;
      _inputTestRawAudioLevel = null;
      _inputTestRawEnergy = null;
      _inputTestRawDuration = null;
      _inputTestRawEstimatedLevel = null;
      _inputTestRawVoiceActivity = false;
      _inputTestLevelSource = "none";
      _inputTestLastSampleAt = null;
      _inputTestRawStats.clear();

      _inputTestTimer?.cancel();
      _inputTestTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        unawaited(_sampleInputTestLevel());
      });
      unawaited(_sampleInputTestLevel());
    } catch (error) {
      _inputTestError = "Unable to start mic test: $error";
      await stopInputTest(notify: false);
    } finally {
      _isInputTestStarting = false;
      notifyListeners();
    }
  }

  Future<void> stopInputTest({bool notify = true}) async {
    _inputTestTimer?.cancel();
    _inputTestTimer = null;

    final probeSender = _inputTestProbeRtpSender;
    final probeConnection = _inputTestProbeConnection;
    final testStream = _inputTestStream;

    _inputTestProbeRtpSender = null;
    _inputTestProbeConnection = null;
    _inputTestProbeTrack = null;
    _inputTestStream = null;
    _isInputTestRunning = false;
    _inputTestUsesVoiceStream = false;
    _inputTestLevel = 0;
    _inputTestLastEnergy = null;
    _inputTestLastDuration = null;
    _inputTestRawAudioLevel = null;
    _inputTestRawEnergy = null;
    _inputTestRawDuration = null;
    _inputTestRawEstimatedLevel = null;
    _inputTestRawVoiceActivity = false;
    _inputTestLevelSource = "none";
    _inputTestLastSampleAt = null;
    _inputTestRawStats.clear();

    if (probeSender != null) {
      try {
        await probeSender.dispose();
      } catch (_) {
        // Ignore sender disposal failures during teardown.
      }
    }

    if (probeConnection != null) {
      probeConnection.onIceCandidate = null;
      probeConnection.onTrack = null;
      probeConnection.onConnectionState = null;
      await _closePeerConnectionSafely(probeConnection);
    }

    if (testStream != null) {
      await _disposeStreamSafely(testStream);
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> _sampleInputTestLevel() async {
    if (!_isInputTestRunning) {
      return;
    }

    final probeConnection = _inputTestProbeConnection;
    final probeTrack = _inputTestProbeTrack;
    if (probeConnection == null || probeTrack == null) {
      return;
    }

    double? strongestAudioLevel;
    double? totalAudioEnergy;
    double? totalSamplesDuration;
    bool voiceActivity = false;
    final rawStats = <String, String>{
      'track_id': probeTrack.id.toString(),
      'track_kind': probeTrack.kind.toString(),
      'track_enabled': probeTrack.enabled.toString(),
    };

    try {
      final reports = await probeConnection.getStats();
      final sample = _extractMicDiagnosticsFromStats(
        reports,
        includeInbound: false,
      );
      strongestAudioLevel = sample.audioLevel;
      totalAudioEnergy = sample.totalAudioEnergy;
      totalSamplesDuration = sample.totalSamplesDuration;
      voiceActivity = sample.voiceActivity;
      rawStats.addAll(_summarizeStatsReports(reports, prefix: 'pc'));
    } catch (error) {
      rawStats['pc_error'] = error.toString();
    }

    final probeSender = _inputTestProbeRtpSender;
    if (probeSender != null) {
      try {
        final reports = await probeSender.getStats();
        final sample = _extractMicDiagnosticsFromStats(
          reports,
          includeInbound: false,
        );
        if (sample.audioLevel != null &&
            (strongestAudioLevel == null ||
                sample.audioLevel! > strongestAudioLevel)) {
          strongestAudioLevel = sample.audioLevel;
        }
        voiceActivity = voiceActivity || sample.voiceActivity;
        if (sample.totalAudioEnergy != null &&
            sample.totalSamplesDuration != null &&
            (totalSamplesDuration == null ||
                sample.totalSamplesDuration! > totalSamplesDuration)) {
          totalAudioEnergy = sample.totalAudioEnergy;
          totalSamplesDuration = sample.totalSamplesDuration;
        }
        rawStats.addAll(_summarizeStatsReports(reports, prefix: 'sender'));
      } catch (_) {
        rawStats['sender_error'] = 'failed to read sender stats';
      }
    }

    final estimatedLevel = _estimateInputTestLevelFromEnergy(
      totalAudioEnergy,
      totalSamplesDuration,
    );

    final testTrackEnabled = probeTrack.enabled;
    double targetLevel = 0;
    String levelSource = "none";
    if (testTrackEnabled) {
      if (strongestAudioLevel != null) {
        targetLevel = strongestAudioLevel.clamp(0.0, 1.0).toDouble();
        levelSource = "audio_level";
      } else if (estimatedLevel != null) {
        targetLevel = estimatedLevel;
        levelSource = "energy";
      } else if (voiceActivity) {
        targetLevel = 0.35;
        levelSource = "voice_activity";
      } else {
        targetLevel = 0.04;
        levelSource = "track_present";
      }
    }

    final smoothed = (_inputTestLevel * 0.65 + targetLevel * 0.35)
        .clamp(0.0, 1.0)
        .toDouble();
    _inputTestRawAudioLevel = strongestAudioLevel;
    _inputTestRawEnergy = totalAudioEnergy;
    _inputTestRawDuration = totalSamplesDuration;
    _inputTestRawEstimatedLevel = estimatedLevel;
    _inputTestRawVoiceActivity = voiceActivity;
    _inputTestLevelSource = levelSource;
    _inputTestLastSampleAt = DateTime.now();
    _inputTestRawStats
      ..clear()
      ..addAll(rawStats);

    if ((_inputTestLevel - smoothed).abs() > 0.002 ||
        (_inputTestLevel == 0 && smoothed > 0)) {
      _inputTestLevel = smoothed;
    }
    notifyListeners();
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

  Future<bool> joinVoiceChannel(
    VoiceChannel channel, {
    bool forceRejoin = false,
  }) async {
    if (currentUser == null) {
      return false;
    }

    if (_voiceJoinInProgress) {
      return false;
    }

    if (!forceRejoin &&
        activeVoiceChannel?.id == channel.id &&
        _voiceSignalChannel != null) {
      return true;
    }

    _voiceJoinInProgress = true;
    await leaveVoiceChannel(notify: false);

    _voiceConnecting = true;
    voiceError = null;
    notifyListeners();

    var failedStep = 'enumerate input devices';
    try {
      await refreshAudioInputDevices(notify: false);

      final selectedInputId = _selectedAudioInputDeviceId;
      if (selectedInputId != null && selectedInputId.isNotEmpty) {
        failedStep = 'apply audio input preference';
        await _applyAudioInputPreference(selectedInputId);
      }

      failedStep = 'getUserMedia';
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': _buildVoiceAudioConstraints(),
        'video': false,
      });

      failedStep = 'set up mic diagnostics';
      await _startMicProbe();
      await refreshAudioInputDevices(notify: false);

      failedStep = 'signal connection';
      activeVoiceChannel = channel;
      final signalChannel = createWsChannel(
        Uri.parse("$wsUrl/voice/${channel.id}/${currentUser!.id}"),
      );
      await signalChannel.ready;
      _voiceSignalChannel = signalChannel;
      _voiceConnectedAt = DateTime.now();
      _resetVoiceDiagnostics();
      _queuedRemoteIceCandidates.clear();
      _remoteDescriptionReadyUsers.clear();
      _voiceSignalProcessingQueue = Future.value();
      _startVoicePing();
      _startVoiceDiagnostics();

      _voiceSignalChannel!.stream.listen(
        _enqueueVoiceSignal,
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

  void _enqueueVoiceSignal(dynamic data) {
    _voiceSignalProcessingQueue = _voiceSignalProcessingQueue
        .then((_) => _handleVoiceSignal(data))
        .catchError((_) {
      // Keep the queue alive even if one payload fails.
    });
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
        final participantIds = participants.map((p) => p.userId).toSet();
        _voiceParticipantVolumes.removeWhere(
          (userId, _) => !participantIds.contains(userId),
        );

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
          _voiceParticipantVolumes.remove(userId);
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
      if (event.track.kind != 'audio') {
        return;
      }

      final remoteStream = event.streams.isNotEmpty
          ? event.streams.first
          : _remoteStreams[remoteUserId];
      if (remoteStream == null) {
        return;
      }

      _remoteStreams[remoteUserId] = remoteStream;
      unawaited(_attachRemoteAudioRenderer(remoteUserId, remoteStream));
      notifyListeners();
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

    _remoteDescriptionReadyUsers.remove(remoteUserId);
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
    _remoteDescriptionReadyUsers.add(fromUserId);
    await _flushQueuedIceCandidates(fromUserId, peerConnection);

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
    _remoteDescriptionReadyUsers.add(fromUserId);
    await _flushQueuedIceCandidates(fromUserId, peerConnection);
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

    final parsedCandidate = RTCIceCandidate(
      candidate,
      sdpMid is String ? sdpMid : null,
      sdpMLineIndex is int ? sdpMLineIndex : null,
    );

    final peerConnection = await _ensurePeerConnection(fromUserId);
    if (!_remoteDescriptionReadyUsers.contains(fromUserId)) {
      _queuedRemoteIceCandidates
          .putIfAbsent(fromUserId, () => <RTCIceCandidate>[])
          .add(parsedCandidate);
      return;
    }

    try {
      await peerConnection.addCandidate(parsedCandidate);
    } catch (_) {
      _queuedRemoteIceCandidates
          .putIfAbsent(fromUserId, () => <RTCIceCandidate>[])
          .add(parsedCandidate);
    }
  }

  Future<void> _flushQueuedIceCandidates(
    int remoteUserId,
    RTCPeerConnection peerConnection,
  ) async {
    final queuedCandidates = _queuedRemoteIceCandidates.remove(remoteUserId);
    if (queuedCandidates == null || queuedCandidates.isEmpty) {
      return;
    }

    for (final candidate in queuedCandidates) {
      try {
        await peerConnection.addCandidate(candidate);
      } catch (_) {
        _queuedRemoteIceCandidates
            .putIfAbsent(remoteUserId, () => <RTCIceCandidate>[])
            .add(candidate);
      }
    }
  }

  void _sendVoiceSignal(Map<String, dynamic> payload) {
    final signalChannel = _voiceSignalChannel;
    if (signalChannel == null) {
      return;
    }

    signalChannel.sink.add(jsonEncode(payload));
  }

  Map<String, dynamic> _buildVoiceAudioConstraints() {
    final constraints = <String, dynamic>{
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
    };

    final selectedInputId = _selectedAudioInputDeviceId;
    if (selectedInputId != null && selectedInputId.isNotEmpty) {
      if (kIsWeb) {
        constraints['deviceId'] = {'exact': selectedInputId};
      } else {
        constraints['deviceId'] = selectedInputId;
        constraints['optional'] = [
          {'sourceId': selectedInputId},
        ];
      }
    }

    return constraints;
  }

  Future<void> _applyAudioInputPreference(String deviceId) async {
    try {
      await Helper.selectAudioInput(deviceId);
    } catch (_) {
      // Not all platforms expose native input switching.
    }
  }

  Future<void> _startMicProbe() async {
    await _stopMicProbe();

    final localStream = _localStream;
    final audioTracks = localStream?.getAudioTracks() ?? <MediaStreamTrack>[];
    if (localStream == null || audioTracks.isEmpty) {
      return;
    }
    final localTrack = audioTracks.first;

    try {
      final probeConnection = await createPeerConnection(_rtcConfiguration);
      _micProbeConnection = probeConnection;
      _micProbeRtpSender =
          await probeConnection.addTrack(localTrack, localStream);
      _micProbeTrack = localTrack;

      final offer = await probeConnection.createOffer({
        'offerToReceiveAudio': false,
        'offerToReceiveVideo': false,
      });
      await probeConnection.setLocalDescription(offer);
    } catch (error, stackTrace) {
      debugPrint('Mic probe initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      await _stopMicProbe();
    }
  }

  Future<void> _stopMicProbe() async {
    final probeConnection = _micProbeConnection;
    final probeRtpSender = _micProbeRtpSender;
    _micProbeConnection = null;
    _micProbeRtpSender = null;
    _micProbeTrack = null;

    if (probeRtpSender != null) {
      try {
        await probeRtpSender.dispose();
      } catch (_) {
        // Ignore sender disposal failures during teardown.
      }
    }

    if (probeConnection != null) {
      probeConnection.onIceCandidate = null;
      probeConnection.onTrack = null;
      probeConnection.onConnectionState = null;
      await _closePeerConnectionSafely(probeConnection);
    }
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
    _queuedRemoteIceCandidates.clear();
    _remoteDescriptionReadyUsers.clear();
    _voiceSignalProcessingQueue = Future.value();
    if (_inputTestUsesVoiceStream) {
      await stopInputTest(notify: false);
    }
    _resetVoiceDiagnostics();
    await _stopMicProbe();

    if (signalChannel != null) {
      await signalChannel.sink.close();
    }

    for (final userId in _peerConnections.keys.toList()) {
      await _closePeerConnection(userId);
    }

    _peerConnections.clear();

    for (final userId in _remoteAudioRenderers.keys.toList()) {
      await _disposeRemoteAudioRenderer(userId);
    }

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
    _voiceParticipantVolumes.clear();
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

    _remoteDescriptionReadyUsers.remove(remoteUserId);
    _queuedRemoteIceCandidates.remove(remoteUserId);
    _peerConnectionStates.remove(remoteUserId);
    await _disposeRemoteAudioRenderer(remoteUserId);

    final remoteStream = _remoteStreams.remove(remoteUserId);
    if (remoteStream != null) {
      await _disposeStreamSafely(remoteStream);
    }
  }

  Future<void> _attachRemoteAudioRenderer(
    int remoteUserId,
    MediaStream remoteStream,
  ) async {
    var renderer = _remoteAudioRenderers[remoteUserId];
    var shouldNotify = false;

    if (renderer == null) {
      renderer = RTCVideoRenderer();
      await renderer.initialize();
      _remoteAudioRenderers[remoteUserId] = renderer;
      shouldNotify = true;
    }

    final currentStream = renderer.srcObject;
    if (currentStream == null || currentStream.id != remoteStream.id) {
      renderer.srcObject = remoteStream;
      try {
        renderer.muted = false;
      } catch (_) {
        // Some platforms throw if mute toggling isn't supported for this stream.
      }
      shouldNotify = true;
    }
    await _applyRemoteRendererVolume(
      renderer,
      voiceParticipantVolumeFor(remoteUserId),
    );

    if (shouldNotify) {
      notifyListeners();
    }
  }

  Future<bool> deleteVoiceChannel(int channelId) async {
    final userId = currentUser?.id;
    if (userId == null) {
      return false;
    }

    try {
      final response = await http.delete(
        Uri.parse("$baseUrl/voice-channels/$channelId?actor_user_id=$userId"),
      );
      if (response.statusCode != 200) {
        return false;
      }

      if (activeVoiceChannel?.id == channelId) {
        await leaveVoiceChannel(notify: false);
      }

      await fetchVoiceChannels();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _applyRemoteRendererVolume(
    RTCVideoRenderer renderer,
    double volume,
  ) async {
    final normalized = volume.clamp(0.0, 1.0).toDouble();
    try {
      renderer.muted = normalized <= 0.001;
    } catch (_) {
      // Some platforms throw if mute toggling isn't supported for this stream.
    }

    final stream = renderer.srcObject;
    final audioTracks = stream?.getAudioTracks() ?? const <MediaStreamTrack>[];
    if (audioTracks.isEmpty) {
      return;
    }

    for (final track in audioTracks) {
      try {
        await Helper.setVolume(
          normalized <= 0.001 ? 0.0001 : normalized,
          track,
        );
      } catch (_) {
        // Ignore volume failures on platforms that don't support remote track gain.
      }
    }
  }

  Future<void> _disposeRemoteAudioRenderer(int remoteUserId) async {
    final renderer = _remoteAudioRenderers.remove(remoteUserId);
    if (renderer == null) {
      return;
    }

    try {
      renderer.srcObject = null;
    } catch (_) {
      // Ignore renderer detachment failures during teardown.
    }

    try {
      await renderer.dispose();
    } catch (_) {
      // Ignore renderer disposal failures during teardown.
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
        Timer.periodic(const Duration(milliseconds: 260), (_) {
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
      double? probeTotalAudioEnergy;
      double? probeTotalSamplesDuration;
      int totalBytesSent = 0;
      int totalPacketsSent = 0;
      int? peerRttMs;

      final probeConnection = _micProbeConnection;
      final probeTrack = _micProbeTrack;
      if (probeConnection != null && probeTrack != null) {
        try {
          final probeReports = await probeConnection.getStats();
          final probeSample = _extractMicDiagnosticsFromStats(
            probeReports,
            includeInbound: false,
          );
          if (probeSample.audioLevel != null) {
            strongestAudioLevel = probeSample.audioLevel;
          }
          voiceActivity = voiceActivity || probeSample.voiceActivity;
          if (probeSample.totalAudioEnergy != null &&
              probeSample.totalSamplesDuration != null) {
            probeTotalAudioEnergy = probeSample.totalAudioEnergy;
            probeTotalSamplesDuration = probeSample.totalSamplesDuration;
          }
        } catch (_) {
          // Ignore probe stats failures and fall back to peer stats.
        }
      }

      final probeRtpSender = _micProbeRtpSender;
      if (probeRtpSender != null) {
        try {
          final probeReports = await probeRtpSender.getStats();
          final probeSample = _extractMicDiagnosticsFromStats(
            probeReports,
            includeInbound: false,
          );
          if (probeSample.audioLevel != null) {
            strongestAudioLevel = probeSample.audioLevel;
          }
          voiceActivity = voiceActivity || probeSample.voiceActivity;
          if (probeSample.totalAudioEnergy != null &&
              probeSample.totalSamplesDuration != null &&
              (probeTotalSamplesDuration == null ||
                  probeSample.totalSamplesDuration! >
                      probeTotalSamplesDuration)) {
            probeTotalAudioEnergy = probeSample.totalAudioEnergy;
            probeTotalSamplesDuration = probeSample.totalSamplesDuration;
          }
        } catch (_) {
          // Ignore probe stats failures and fall back to peer stats.
        }
      }

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

      final energyEstimatedMicLevel = _estimateMicLevelFromEnergy(
        probeTotalAudioEnergy,
        probeTotalSamplesDuration,
      );
      if (energyEstimatedMicLevel != null &&
          (strongestAudioLevel == null ||
              energyEstimatedMicLevel > strongestAudioLevel)) {
        strongestAudioLevel = energyEstimatedMicLevel;
      }
      if (energyEstimatedMicLevel != null && energyEstimatedMicLevel > 0.03) {
        voiceActivity = true;
      }

      double targetMicLevel = 0;
      if (localMicEnabled && !isSelfMuted) {
        if (strongestAudioLevel != null) {
          targetMicLevel = strongestAudioLevel.clamp(0, 1).toDouble();
        } else if (voiceActivity) {
          targetMicLevel = 0.45;
        } else if (_lastStatsPacketsSent != null &&
            totalPacketsSent > _lastStatsPacketsSent!) {
          targetMicLevel = 0.35;
        } else {
          // Keep a tiny baseline so users can tell the input track exists.
          targetMicLevel = 0.02;
        }
      }

      final isRising = targetMicLevel > _voiceMicLevel;
      final smoothingWeight = isRising ? 0.72 : 0.48;
      final smoothedMicLevel = (_voiceMicLevel * (1 - smoothingWeight) +
              targetMicLevel * smoothingWeight)
          .clamp(0.0, 1.0);

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
          (_voiceMicLevel - smoothedMicLevel).abs() > 0.01 ||
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

  _MicDiagnosticsSample _extractMicDiagnosticsFromStats(
    List<StatsReport> reports, {
    bool includeInbound = true,
  }) {
    double? audioLevel;
    bool voiceActivity = false;
    double? totalAudioEnergy;
    double? totalSamplesDuration;

    for (final report in reports) {
      final values = report.values;
      final reportType =
          (_readStringMetric(values, ['type']) ?? report.type).toLowerCase();
      final kind = _readStringMetric(
        values,
        ['kind', 'mediaType', 'media_type'],
      )?.toLowerCase();
      final likelyAudioReportType = reportType == 'outbound-rtp' ||
          reportType == 'inbound-rtp' ||
          reportType == 'remote-inbound-rtp' ||
          reportType == 'remote-outbound-rtp' ||
          reportType == 'media-source' ||
          reportType == 'track';
      final isAudio = kind == 'audio' ||
          likelyAudioReportType ||
          reportType.contains('audio') ||
          ((values['id']?.toString().toLowerCase().contains('audio')) ?? false);
      if (!isAudio && reportType != 'media-source' && reportType != 'track') {
        continue;
      }

      if (!includeInbound &&
          (reportType == 'inbound-rtp' ||
              reportType == 'remote-inbound-rtp' ||
              reportType == 'remote-outbound-rtp')) {
        continue;
      }

      final currentAudioLevel = _parseDoubleMetric(
        values['audioLevel'] ??
            values['audio_level'] ??
            values['audioInputLevel'] ??
            values['audio_input_level'] ??
            values['inputLevel'] ??
            values['input_level'],
      );
      if (currentAudioLevel != null &&
          (audioLevel == null || currentAudioLevel > audioLevel)) {
        audioLevel = currentAudioLevel;
      }

      final voiceActivityFlag =
          values['voiceActivityFlag'] ?? values['voice_activity_flag'];
      if (voiceActivityFlag == true ||
          voiceActivityFlag.toString().toLowerCase() == 'true') {
        voiceActivity = true;
      }

      final energy = _parseDoubleMetric(
        values['totalAudioEnergy'] ?? values['total_audio_energy'],
      );
      final duration = _parseDoubleMetric(
        values['totalSamplesDuration'] ?? values['total_samples_duration'],
      );
      if (energy != null &&
          duration != null &&
          (totalSamplesDuration == null || duration > totalSamplesDuration)) {
        totalAudioEnergy = energy;
        totalSamplesDuration = duration;
      }
    }

    return _MicDiagnosticsSample(
      audioLevel: audioLevel,
      voiceActivity: voiceActivity,
      totalAudioEnergy: totalAudioEnergy,
      totalSamplesDuration: totalSamplesDuration,
    );
  }

  Map<String, String> _summarizeStatsReports(
    List<StatsReport> reports, {
    required String prefix,
  }) {
    int audioRelatedReports = 0;
    int reportsWithAudioLevel = 0;
    double? maxAudioLevel;
    double? latestEnergy;
    double? latestDuration;
    bool voiceActivitySeen = false;
    String? firstAudioType;
    String? firstAudioId;
    final interestingKeys = <String>{};

    for (final report in reports) {
      final values = report.values;
      final reportType =
          (_readStringMetric(values, ['type']) ?? report.type).toLowerCase();
      final kind = _readStringMetric(
        values,
        ['kind', 'mediaType', 'media_type'],
      )?.toLowerCase();
      final likelyAudioReportType = reportType == 'outbound-rtp' ||
          reportType == 'inbound-rtp' ||
          reportType == 'remote-inbound-rtp' ||
          reportType == 'remote-outbound-rtp' ||
          reportType == 'media-source' ||
          reportType == 'track';
      final isAudio = kind == 'audio' ||
          likelyAudioReportType ||
          reportType.contains('audio') ||
          ((values['id']?.toString().toLowerCase().contains('audio')) ?? false);
      if (!isAudio) {
        continue;
      }

      audioRelatedReports += 1;
      firstAudioType ??= reportType;
      firstAudioId ??= report.id;

      for (final key in values.keys) {
        final keyText = key.toString();
        final lowerKey = keyText.toLowerCase();
        if (lowerKey.contains('audio') ||
            lowerKey.contains('level') ||
            lowerKey.contains('energy') ||
            lowerKey.contains('sample') ||
            lowerKey.contains('voice')) {
          interestingKeys.add(keyText);
        }
      }

      final audioLevel = _parseDoubleMetric(
        values['audioLevel'] ??
            values['audio_level'] ??
            values['audioInputLevel'] ??
            values['audio_input_level'] ??
            values['inputLevel'] ??
            values['input_level'],
      );
      if (audioLevel != null) {
        reportsWithAudioLevel += 1;
        if (maxAudioLevel == null || audioLevel > maxAudioLevel) {
          maxAudioLevel = audioLevel;
        }
      }

      final energy = _parseDoubleMetric(
        values['totalAudioEnergy'] ?? values['total_audio_energy'],
      );
      final duration = _parseDoubleMetric(
        values['totalSamplesDuration'] ?? values['total_samples_duration'],
      );
      if (energy != null) {
        latestEnergy = energy;
      }
      if (duration != null) {
        latestDuration = duration;
      }

      final voiceFlag =
          values['voiceActivityFlag'] ?? values['voice_activity_flag'];
      if (voiceFlag == true || voiceFlag.toString().toLowerCase() == 'true') {
        voiceActivitySeen = true;
      }
    }

    return {
      '${prefix}_reports_total': reports.length.toString(),
      '${prefix}_reports_audio_related': audioRelatedReports.toString(),
      '${prefix}_reports_with_audio_level': reportsWithAudioLevel.toString(),
      if (firstAudioType != null) '${prefix}_first_audio_type': firstAudioType,
      if (firstAudioId != null) '${prefix}_first_audio_id': firstAudioId,
      if (maxAudioLevel != null)
        '${prefix}_max_audio_level': maxAudioLevel.toStringAsFixed(5),
      if (latestEnergy != null)
        '${prefix}_latest_total_audio_energy': latestEnergy.toStringAsFixed(5),
      if (latestDuration != null)
        '${prefix}_latest_total_samples_duration':
            latestDuration.toStringAsFixed(5),
      '${prefix}_voice_activity': voiceActivitySeen.toString(),
      if (interestingKeys.isNotEmpty)
        '${prefix}_interesting_keys': interestingKeys.take(16).join(', '),
    };
  }

  double? _estimateMicLevelFromEnergy(
    double? totalAudioEnergy,
    double? totalSamplesDuration,
  ) {
    if (totalAudioEnergy == null || totalSamplesDuration == null) {
      _lastMicEnergy = null;
      _lastMicDuration = null;
      return null;
    }

    final previousEnergy = _lastMicEnergy;
    final previousDuration = _lastMicDuration;
    _lastMicEnergy = totalAudioEnergy;
    _lastMicDuration = totalSamplesDuration;

    if (previousEnergy == null || previousDuration == null) {
      return null;
    }

    final energyDelta = totalAudioEnergy - previousEnergy;
    final durationDelta = totalSamplesDuration - previousDuration;
    if (durationDelta <= 0 || energyDelta < 0) {
      return null;
    }

    final averagePower = energyDelta / durationDelta;
    if (!averagePower.isFinite) {
      return null;
    }

    return (averagePower * 6).clamp(0.0, 1.0).toDouble();
  }

  double? _estimateInputTestLevelFromEnergy(
    double? totalAudioEnergy,
    double? totalSamplesDuration,
  ) {
    if (totalAudioEnergy == null || totalSamplesDuration == null) {
      _inputTestLastEnergy = null;
      _inputTestLastDuration = null;
      return null;
    }

    final previousEnergy = _inputTestLastEnergy;
    final previousDuration = _inputTestLastDuration;
    _inputTestLastEnergy = totalAudioEnergy;
    _inputTestLastDuration = totalSamplesDuration;

    if (previousEnergy == null || previousDuration == null) {
      return null;
    }

    final energyDelta = totalAudioEnergy - previousEnergy;
    final durationDelta = totalSamplesDuration - previousDuration;
    if (durationDelta <= 0 || energyDelta < 0) {
      return null;
    }

    final averagePower = energyDelta / durationDelta;
    if (!averagePower.isFinite) {
      return null;
    }

    return (averagePower * 6).clamp(0.0, 1.0).toDouble();
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
    _lastMicEnergy = null;
    _lastMicDuration = null;
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
    _inputTestTimer?.cancel();
    _inputTestTimer = null;
    unawaited(_stopMicProbe());
    unawaited(stopInputTest(notify: false));

    for (final peerConnection in _peerConnections.values) {
      peerConnection.onIceCandidate = null;
      peerConnection.onTrack = null;
      peerConnection.onConnectionState = null;
      unawaited(_closePeerConnectionSafely(peerConnection));
    }

    for (final stream in _remoteStreams.values.toSet()) {
      unawaited(_disposeStreamSafely(stream));
    }
    for (final userId in _remoteAudioRenderers.keys.toList()) {
      unawaited(_disposeRemoteAudioRenderer(userId));
    }

    final localStream = _localStream;
    if (localStream != null) {
      unawaited(_disposeStreamSafely(localStream));
    }

    _peerConnections.clear();
    _peerConnectionStates.clear();
    _remoteStreams.clear();
    _remoteAudioRenderers.clear();
    _queuedRemoteIceCandidates.clear();
    _remoteDescriptionReadyUsers.clear();
    _voiceSignalProcessingQueue = Future.value();
    _pendingVoicePings.clear();
    _localStream = null;
    scrollController.dispose();
    _highlightTimer?.cancel();
    super.dispose();
  }
}

class _MicDiagnosticsSample {
  const _MicDiagnosticsSample({
    this.audioLevel,
    required this.voiceActivity,
    this.totalAudioEnergy,
    this.totalSamplesDuration,
  });

  final double? audioLevel;
  final bool voiceActivity;
  final double? totalAudioEnergy;
  final double? totalSamplesDuration;
}
