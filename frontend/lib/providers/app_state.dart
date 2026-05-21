import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as media_kit;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models/chat_models.dart';
import '../utils/ws_channel_factory.dart';

class AppState extends ChangeNotifier {
  static const String baseUrl = "http://150.230.149.68:8000";
  static const String wsUrl = "ws://150.230.149.68:8000/ws";
  // static const String baseUrl = "https://extochatapp.onrender.com";
  // static const String wsUrl = "wss://extochatapp.onrender.com/ws";
  static const int _musicBotUserId = -1;
  static const double _defaultVoiceParticipantVolume = 1.0;
  static const double _defaultMusicBotVolume = 0.2;

  static const Map<String, dynamic> _rtcConfiguration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
  };

  User? currentUser;
  List<Channel> channels = [];
  Channel? activeChannel;
  WebSocketChannel? _channel;
  Timer? _textPingTimer;
  Timer? _textReconnectTimer;
  int _textReconnectAttempt = 0;
  WebSocketChannel? _notificationChannel;
  Timer? _notificationPingTimer;
  Timer? _notificationReconnectTimer;
  int _notificationReconnectAttempt = 0;
  final Set<int> _channelsWithUnreadMessages = <int>{};
  final Set<int> _channelsWithMentions = <int>{};
  List<Message> messages = [];
  List<Message> pinnedMessages = [];
  bool pinnedMessagesLoading = false;
  String? pinnedMessagesError;
  List<Message> messageSearchResults = [];
  bool messageSearchLoading = false;
  String? messageSearchError;

  List<VoiceChannel> voiceChannels = [];
  VoiceChannel? activeVoiceChannel;
  final Map<int, VoiceParticipant> voiceParticipants = {};
  List<User> adminUsers = [];
  List<User> mentionableUsers = [];
  User? selectedAdminUser;
  UserChannelPermissions? selectedUserChannelPermissions;
  bool adminUsersLoading = false;
  bool adminPermissionsLoading = false;
  String? adminPermissionsError;
  bool attachmentUploadInProgress = false;
  String? attachmentUploadError;
  WebSocketChannel? _voiceSignalChannel;
  Timer? _voicePingTimer;
  MediaStream? _localStream;
  MediaStream? _localScreenStream;
  RTCVideoRenderer? _localScreenRenderer;
  final Map<int, RTCPeerConnection> _peerConnections = {};
  final Map<int, MediaStream> _remoteStreams = {};
  final Map<int, MediaStream> _remoteScreenStreams = {};
  final Map<int, RTCVideoRenderer> _remoteAudioRenderers = {};
  final Map<int, RTCVideoRenderer> _remoteScreenRenderers = {};
  final Map<int, RTCRtpSender> _screenShareSenders = {};
  final Set<int> _screenSharingUserIds = <int>{};
  final Map<int, double> _voiceParticipantVolumes = {};
  final media_kit.Player _musicPlayer = media_kit.Player();
  StreamSubscription<bool>? _musicPlayerCompletionSubscription;
  int? _activeMusicTrackId;
  bool _suppressMusicCompletionSignals = false;
  final Map<int, List<RTCIceCandidate>> _queuedRemoteIceCandidates = {};
  final Set<int> _remoteDescriptionReadyUsers = <int>{};
  Future<void> _voiceSignalProcessingQueue = Future.value();
  Future<void>? _leaveVoiceChannelTask;
  bool isSelfMuted = false;
  bool _voiceConnecting = false;
  bool _voiceJoinInProgress = false;
  bool _screenShareStarting = false;
  bool _voiceShouldReconnect = false;
  Timer? _voiceReconnectTimer;
  VoiceChannel? _voiceReconnectChannel;
  int _voiceReconnectAttempt = 0;
  String? voiceError;
  String? screenShareError;
  Timer? _voiceDiagnosticsTimer;
  bool _voiceDiagnosticsInFlight = false;
  final Map<int, DateTime> _pendingVoicePings = {};
  final Map<int, RTCPeerConnectionState> _peerConnectionStates = {};
  final Map<int, Timer> _peerDisconnectTimers = {};
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

  AppState() {
    unawaited(_applyMusicPlaybackVolume(_defaultMusicBotVolume));
    _musicPlayerCompletionSubscription =
        _musicPlayer.stream.completed.listen((completed) {
      if (completed) {
        _handleMusicTrackCompleted();
      }
    });
  }

  bool get _isWindowsDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  // Interaction state
  Message? replyingTo;
  Message? editingMessage;
  int? highlightedMessageId;
  Timer? _highlightTimer;
  int _nextLocalMessageId = -1;

  // Scrolling
  final ItemScrollController itemScrollController = ItemScrollController();
  final ItemPositionsListener itemPositionsListener = ItemPositionsListener.create();

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
  RTCVideoRenderer? get localScreenRenderer => _localScreenRenderer;
  Map<int, RTCVideoRenderer> get remoteScreenRenderers =>
      Map<int, RTCVideoRenderer>.unmodifiable(_remoteScreenRenderers);
  Set<int> get screenSharingUserIds =>
      Set<int>.unmodifiable(_screenSharingUserIds);
  bool get isScreenSharing => _localScreenStream != null;
  bool get isScreenShareStarting => _screenShareStarting;
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
  bool get isAdmin => currentUser?.role.toLowerCase() == "admin";
  bool get canDeleteAnyMessage => isAdmin;
  bool get canModerateChannels {
    final role = currentUser?.role.toLowerCase();
    return role == "admin" || role == "moderator";
  }
  bool get canCreateChannels => canModerateChannels;
  bool hasChannelActivity(int channelId) =>
      _channelsWithUnreadMessages.contains(channelId);
  bool hasChannelMention(int channelId) =>
      _channelsWithMentions.contains(channelId);

  String resolveMediaUrl(String rawPathOrUrl) {
    final value = rawPathOrUrl.trim();
    if (value.isEmpty) {
      return value;
    }
    return Uri.parse(baseUrl).resolve(value).toString();
  }

  List<User> findMentionCandidates(String query, {int limit = 8}) {
    final normalized = query.trim().toLowerCase();
    final selfId = currentUser?.id;

    final users = mentionableUsers.where((user) => user.id != selfId).toList();
    if (normalized.isEmpty) {
      return users.take(limit).toList();
    }

    users.sort((a, b) {
      final aName = a.username.toLowerCase();
      final bName = b.username.toLowerCase();
      final aStarts = aName.startsWith(normalized);
      final bStarts = bName.startsWith(normalized);
      if (aStarts != bStarts) {
        return aStarts ? -1 : 1;
      }
      final aContains = aName.contains(normalized);
      final bContains = bName.contains(normalized);
      if (aContains != bContains) {
        return aContains ? -1 : 1;
      }
      return aName.compareTo(bName);
    });
    return users.take(limit).toList();
  }

  bool canDeleteTextChannel(Channel _) {
    return canModerateChannels;
  }

  bool canDeleteVoiceChannel(VoiceChannel _) {
    return canModerateChannels;
  }

  bool _isMusicBotParticipantId(int userId) => userId == _musicBotUserId;

  double _defaultVolumeForParticipant(int userId) {
    return _isMusicBotParticipantId(userId)
        ? _defaultMusicBotVolume
        : _defaultVoiceParticipantVolume;
  }

  double voiceParticipantVolumeFor(int userId) {
    return (_voiceParticipantVolumes[userId] ??
            _defaultVolumeForParticipant(userId))
        .clamp(0.0, 5.0)
        .toDouble();
  }

  bool _storeVoiceParticipantVolume(int userId, double volume) {
    final normalized = volume.clamp(0.0, 5.0).toDouble();
    final previous = voiceParticipantVolumeFor(userId);
    if ((previous - normalized).abs() < 0.001) {
      return false;
    }

    final defaultVolume = _defaultVolumeForParticipant(userId);
    if ((normalized - defaultVolume).abs() < 0.001) {
      _voiceParticipantVolumes.remove(userId);
    } else {
      _voiceParticipantVolumes[userId] = normalized;
    }
    return true;
  }

  void setVoiceParticipantVolume(int userId, double volume) {
    final normalized = volume.clamp(0.0, 5.0).toDouble();
    if (!_storeVoiceParticipantVolume(userId, normalized)) {
      return;
    }

    if (_isMusicBotParticipantId(userId)) {
      unawaited(_applyMusicPlaybackVolume(normalized));
    } else {
      final renderer = _remoteAudioRenderers[userId];
      if (renderer != null) {
        unawaited(_applyRemoteRendererVolume(renderer, normalized));
      }
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
        _disconnectNotificationSocket();
        currentUser = User.fromJson(jsonDecode(response.body));
        _channelsWithUnreadMessages.clear();
        _channelsWithMentions.clear();
        if (!isAdmin) {
          _clearAdminPermissionState(notify: false);
        }
        await fetchMentionableUsers(notify: false);
        await fetchChannels();
        await fetchMissedChannelNotifications(notify: false);
        await fetchVoiceChannels();
        await refreshAudioInputDevices(notify: false);
        _connectNotificationSocket();
        notifyListeners();
        return null;
      }

      final data = jsonDecode(response.body);
      return data['detail'] ?? "Login failed";
    } catch (_) {
      return "Connection error";
    }
  }

  Future<void> fetchMentionableUsers({bool notify = true}) async {
    if (currentUser == null) {
      mentionableUsers = [];
      if (notify) {
        notifyListeners();
      }
      return;
    }

    try {
      final response = await http.get(Uri.parse("$baseUrl/users/"));
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        mentionableUsers = data.map((item) => User.fromJson(item)).toList();
        mentionableUsers.sort(
          (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
        );
      }
    } catch (_) {
      // Mention lookup is optional; ignore failures and keep old list.
    }

    if (notify) {
      notifyListeners();
    }
  }

  void _clearAdminPermissionState({bool notify = true}) {
    adminUsers = [];
    selectedAdminUser = null;
    selectedUserChannelPermissions = null;
    adminUsersLoading = false;
    adminPermissionsLoading = false;
    adminPermissionsError = null;
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> fetchAdminUsers({bool autoSelectFirst = true}) async {
    final userId = currentUser?.id;
    if (userId == null || !isAdmin) {
      _clearAdminPermissionState();
      return;
    }

    adminUsersLoading = true;
    adminPermissionsError = null;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse("$baseUrl/admin/users/?actor_user_id=$userId"),
      );
      if (response.statusCode != 200) {
        adminPermissionsError = "Unable to load users (${response.statusCode})";
        return;
      }

      final List data = jsonDecode(response.body);
      adminUsers = data.map((item) => User.fromJson(item)).toList();
      adminUsers.sort(
        (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
      );

      final selectedId = selectedAdminUser?.id;
      if (selectedId != null) {
        final matched = adminUsers.where((user) => user.id == selectedId);
        selectedAdminUser = matched.isNotEmpty ? matched.first : null;
      }

      if (autoSelectFirst) {
        final nextUserId =
            selectedAdminUser?.id ?? (adminUsers.isNotEmpty ? adminUsers.first.id : null);
        if (nextUserId != null) {
          await fetchAdminPermissionsForUser(nextUserId);
        } else {
          selectedUserChannelPermissions = null;
        }
      }
    } catch (_) {
      adminPermissionsError = "Unable to load users";
    } finally {
      adminUsersLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchAdminPermissionsForUser(int targetUserId) async {
    final userId = currentUser?.id;
    if (userId == null || !isAdmin) {
      return;
    }

    adminPermissionsLoading = true;
    adminPermissionsError = null;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse(
          "$baseUrl/admin/users/$targetUserId/permissions?actor_user_id=$userId",
        ),
      );
      if (response.statusCode != 200) {
        adminPermissionsError =
            "Unable to load permissions (${response.statusCode})";
        return;
      }

      final payload = jsonDecode(response.body);
      selectedUserChannelPermissions =
          UserChannelPermissions.fromJson(payload);

      final matched = adminUsers.where((user) => user.id == targetUserId);
      if (matched.isNotEmpty) {
        selectedAdminUser = matched.first;
      } else {
        selectedAdminUser = User(
          id: selectedUserChannelPermissions!.userId,
          username: selectedUserChannelPermissions!.username,
          role: selectedUserChannelPermissions!.role,
        );
      }
    } catch (_) {
      adminPermissionsError = "Unable to load permissions";
    } finally {
      adminPermissionsLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateUserRoleAsAdmin(int targetUserId, String role) async {
    final userId = currentUser?.id;
    if (userId == null || !isAdmin) {
      return false;
    }

    try {
      final response = await http.patch(
        Uri.parse("$baseUrl/users/$targetUserId/role?actor_user_id=$userId"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"role": role}),
      );
      if (response.statusCode != 200) {
        return false;
      }

      final updatedUser = User.fromJson(jsonDecode(response.body));
      final index = adminUsers.indexWhere((user) => user.id == targetUserId);
      if (index != -1) {
        adminUsers[index] = updatedUser;
      }
      if (selectedAdminUser?.id == targetUserId) {
        selectedAdminUser = updatedUser;
      }
      if (selectedUserChannelPermissions?.userId == targetUserId) {
        final current = selectedUserChannelPermissions!;
        selectedUserChannelPermissions = UserChannelPermissions(
          userId: current.userId,
          username: current.username,
          role: updatedUser.role,
          textChannelPermissions: current.textChannelPermissions,
          voiceChannelPermissions: current.voiceChannelPermissions,
        );
      }
      if (currentUser?.id == targetUserId) {
        currentUser = updatedUser;
        if (!isAdmin) {
          _clearAdminPermissionState(notify: false);
        }
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateSelectedUserTextChannelPermission(
    int channelId,
    bool canView,
  ) async {
    return _updateSelectedUserPermissions(
      textUpdates: {channelId: canView},
    );
  }

  Future<bool> updateSelectedUserVoiceChannelPermission(
    int channelId,
    bool canView,
  ) async {
    return _updateSelectedUserPermissions(
      voiceUpdates: {channelId: canView},
    );
  }

  Future<bool> _updateSelectedUserPermissions({
    Map<int, bool>? textUpdates,
    Map<int, bool>? voiceUpdates,
  }) async {
    final userId = currentUser?.id;
    final selected = selectedUserChannelPermissions;
    if (userId == null || !isAdmin || selected == null) {
      return false;
    }

    try {
      // Use string keys in the payload to keep JSON encoding predictable.
      final textPayload = <String, bool>{
        for (final entry in (textUpdates ?? const <int, bool>{}).entries)
          entry.key.toString(): entry.value,
      };
      final voicePayload = <String, bool>{
        for (final entry in (voiceUpdates ?? const <int, bool>{}).entries)
          entry.key.toString(): entry.value,
      };

      final response = await http.patch(
        Uri.parse(
          "$baseUrl/admin/users/${selected.userId}/permissions?actor_user_id=$userId",
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "text_channel_permissions": textPayload,
          "voice_channel_permissions": voicePayload,
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          "Failed to update user permissions (${response.statusCode}): ${response.body}",
        );
        return false;
      }

      final responseBody = response.body.trim();
      if (responseBody.isNotEmpty) {
        try {
          selectedUserChannelPermissions =
              UserChannelPermissions.fromJson(jsonDecode(responseBody));
        } catch (_) {
          await fetchAdminPermissionsForUser(selected.userId);
        }
      } else {
        await fetchAdminPermissionsForUser(selected.userId);
      }

      if (currentUser?.id == selected.userId) {
        try {
          await fetchChannels();
          await fetchVoiceChannels();
        } catch (_) {
          // Permission update already succeeded; keep this non-fatal.
        }
      }
      notifyListeners();
      return true;
    } catch (error) {
      debugPrint("Error while updating user permissions: $error");
      return false;
    }
  }

  Future<ChannelPermissions?> fetchTextChannelPermissionsAsAdmin(
    int channelId,
  ) async {
    final userId = currentUser?.id;
    if (userId == null || !isAdmin) {
      return null;
    }

    try {
      final response = await http.get(
        Uri.parse(
          "$baseUrl/admin/channels/$channelId/permissions?actor_user_id=$userId",
        ),
      );
      if (response.statusCode != 200) {
        return null;
      }
      return ChannelPermissions.fromJson(jsonDecode(response.body));
    } catch (_) {
      return null;
    }
  }

  Future<ChannelPermissions?> fetchVoiceChannelPermissionsAsAdmin(
    int channelId,
  ) async {
    final userId = currentUser?.id;
    if (userId == null || !isAdmin) {
      return null;
    }

    try {
      final response = await http.get(
        Uri.parse(
          "$baseUrl/admin/voice-channels/$channelId/permissions?actor_user_id=$userId",
        ),
      );
      if (response.statusCode != 200) {
        return null;
      }
      return ChannelPermissions.fromJson(jsonDecode(response.body));
    } catch (_) {
      return null;
    }
  }

  Future<ChannelPermissions?> updateTextChannelUserVisibilityAsAdmin({
    required int channelId,
    required int targetUserId,
    required bool canView,
  }) async {
    final userId = currentUser?.id;
    if (userId == null || !isAdmin) {
      return null;
    }

    try {
      final response = await http.patch(
        Uri.parse(
          "$baseUrl/admin/channels/$channelId/permissions?actor_user_id=$userId",
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_permissions": {
            targetUserId.toString(): canView,
          },
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      return ChannelPermissions.fromJson(jsonDecode(response.body));
    } catch (_) {
      return null;
    }
  }

  Future<ChannelPermissions?> updateVoiceChannelUserVisibilityAsAdmin({
    required int channelId,
    required int targetUserId,
    required bool canView,
  }) async {
    final userId = currentUser?.id;
    if (userId == null || !isAdmin) {
      return null;
    }

    try {
      final response = await http.patch(
        Uri.parse(
          "$baseUrl/admin/voice-channels/$channelId/permissions?actor_user_id=$userId",
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_permissions": {
            targetUserId.toString(): canView,
          },
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      return ChannelPermissions.fromJson(jsonDecode(response.body));
    } catch (_) {
      return null;
    }
  }

  Future<bool> createChannel(
    String name,
    String? description, {
    bool adminOnly = false,
  }) async {
    final userId = currentUser?.id;
    if (userId == null || !canCreateChannels) {
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/channels/?actor_user_id=$userId"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "name": name,
          "description": description,
          "admin_only": adminOnly,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await fetchChannels();
        return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> createVoiceChannel(
    String name,
    String? description, {
    bool adminOnly = false,
  }) async {
    final userId = currentUser?.id;
    if (userId == null || !canCreateChannels) {
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/voice-channels/?actor_user_id=$userId"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "name": name,
          "description": description,
          "admin_only": adminOnly,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await fetchVoiceChannels();
        return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> fetchChannels() async {
    final userId = currentUser?.id;
    if (userId == null) {
      return;
    }

    final response = await http.get(
      Uri.parse("$baseUrl/channels/?actor_user_id=$userId"),
    );
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      channels = data.map((c) => Channel.fromJson(c)).toList();
      _pruneChannelNotifications(channels.map((channel) => channel.id).toSet());

      if (activeChannel != null) {
        final stillExists = channels.any((c) => c.id == activeChannel!.id);
        if (!stillExists) {
          _disconnectTextSocket();
          activeChannel = null;
          messages = [];
          pinnedMessages = [];
          clearMessageSearch(notify: false);
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
        _disconnectTextSocket();
        activeChannel = null;
        messages = [];
        pinnedMessages = [];
        clearMessageSearch(notify: false);
      }
      _clearChannelNotification(channelId, notify: false);

      await fetchChannels();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> fetchVoiceChannels() async {
    final userId = currentUser?.id;
    if (userId == null) {
      return;
    }

    final response = await http.get(
      Uri.parse("$baseUrl/voice-channels/?actor_user_id=$userId"),
    );
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

  void clearMessageSearch({bool notify = true}) {
    messageSearchResults = [];
    messageSearchLoading = false;
    messageSearchError = null;
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> searchMessages(String query, {int limit = 50}) async {
    final channelId = activeChannel?.id;
    final userId = currentUser?.id;
    if (channelId == null || userId == null) {
      return;
    }

    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      clearMessageSearch();
      return;
    }

    messageSearchLoading = true;
    messageSearchError = null;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse("$baseUrl/channels/$channelId/search/messages").replace(
          queryParameters: {
            "actor_user_id": "$userId",
            "query": normalizedQuery,
            "limit": "${limit.clamp(1, 100)}",
          },
        ),
      );
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        messageSearchResults = data.map((m) => Message.fromJson(m)).toList();
      } else {
        messageSearchResults = [];
        messageSearchError =
            "Unable to search messages (${response.statusCode})";
      }
    } catch (_) {
      messageSearchResults = [];
      messageSearchError = "Unable to search messages";
    } finally {
      messageSearchLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchPinnedMessages() async {
    final channelId = activeChannel?.id;
    final userId = currentUser?.id;
    if (channelId == null || userId == null) {
      pinnedMessages = [];
      pinnedMessagesLoading = false;
      pinnedMessagesError = null;
      notifyListeners();
      return;
    }

    pinnedMessagesLoading = true;
    pinnedMessagesError = null;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse("$baseUrl/channels/$channelId/pins").replace(
          queryParameters: {
            "actor_user_id": "$userId",
          },
        ),
      );
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        pinnedMessages = data.map((m) => Message.fromJson(m)).toList();
      } else {
        pinnedMessages = [];
        pinnedMessagesError =
            "Unable to load pinned messages (${response.statusCode})";
      }
    } catch (_) {
      pinnedMessages = [];
      pinnedMessagesError = "Unable to load pinned messages";
    } finally {
      pinnedMessagesLoading = false;
      notifyListeners();
    }
  }

  Future<bool> pinMessage(int messageId) async {
    final channelId = activeChannel?.id;
    final userId = currentUser?.id;
    if (channelId == null || userId == null || !canModerateChannels) {
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/channels/$channelId/pins/$messageId").replace(
          queryParameters: {
            "actor_user_id": "$userId",
          },
        ),
      );
      if (response.statusCode != 200) {
        return false;
      }

      final payload = Message.fromJson(jsonDecode(response.body));
      _applyPinStateFromMessage(payload);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unpinMessage(int messageId) async {
    final channelId = activeChannel?.id;
    final userId = currentUser?.id;
    if (channelId == null || userId == null || !canModerateChannels) {
      return false;
    }

    try {
      final response = await http.delete(
        Uri.parse("$baseUrl/channels/$channelId/pins/$messageId").replace(
          queryParameters: {
            "actor_user_id": "$userId",
          },
        ),
      );
      if (response.statusCode != 200) {
        return false;
      }

      _applyPinStateById(
        messageId: messageId,
        isPinned: false,
        pinnedAt: null,
        pinnedByUserId: null,
        pinnedByUsername: null,
      );
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendAttachmentMessage({
    required Uint8List bytes,
    required String filename,
    String? content,
    int? parentId,
  }) async {
    final channelId = activeChannel?.id;
    final userId = currentUser?.id;
    if (channelId == null || userId == null || bytes.isEmpty) {
      return false;
    }

    attachmentUploadInProgress = true;
    attachmentUploadError = null;
    notifyListeners();

    try {
      final uri = Uri.parse("$baseUrl/channels/$channelId/attachments").replace(
        queryParameters: {
          "actor_user_id": "$userId",
        },
      );
      final request = http.MultipartRequest("POST", uri);
      request.fields["content"] = (content ?? "").trim();
      if (parentId != null) {
        request.fields["parent_id"] = "$parentId";
      }
      request.files.add(
        http.MultipartFile.fromBytes(
          "file",
          bytes,
          filename: filename,
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String detail = "Unable to upload attachment (${response.statusCode})";
        try {
          final payload = jsonDecode(response.body);
          final serverDetail = payload["detail"]?.toString().trim();
          if (serverDetail != null && serverDetail.isNotEmpty) {
            detail = serverDetail;
          }
        } catch (_) {
          // Ignore non-JSON errors.
        }
        attachmentUploadError = detail;
        return false;
      }

      final responseBody = response.body.trim();
      if (responseBody.isNotEmpty) {
        try {
          final uploadedMessage = Message.fromJson(jsonDecode(responseBody));
          final existingIndex =
              messages.indexWhere((message) => message.id == uploadedMessage.id);
          if (existingIndex == -1) {
            messages.add(uploadedMessage);
            if (uploadedMessage.isPinned) {
              _applyPinStateFromMessage(uploadedMessage);
            }
          } else {
            messages[existingIndex] = uploadedMessage;
          }
        } catch (_) {
          // Socket push will still update message list.
        }
      }

      replyingTo = null;
      attachmentUploadError = null;
      if (activeChannel?.id == channelId) {
        try {
          await fetchMessages(channelId);
        } catch (_) {
          // The socket push and local append have already updated the channel.
        }
      }
      return true;
    } catch (_) {
      attachmentUploadError = "Unable to upload attachment";
      return false;
    } finally {
      attachmentUploadInProgress = false;
      notifyListeners();
      _scrollToBottom();
    }
  }

  Future<void> fetchMessages(int channelId) async {
    final userId = currentUser?.id;
    if (userId == null) {
      return;
    }

    final response = await http.get(
      Uri.parse(
        "$baseUrl/channels/$channelId/messages/?actor_user_id=$userId",
      ),
    );
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      final fetchedMessages = data.map((m) => Message.fromJson(m)).toList();
      messages = fetchedMessages;
      if (activeChannel?.id == channelId) {
        _clearChannelNotification(channelId, notify: false);
        final latestMessageId =
            fetchedMessages.isNotEmpty ? fetchedMessages.last.id : null;
        unawaited(
          markChannelRead(channelId, messageId: latestMessageId),
        );
      }
      notifyListeners();
      _scrollToBottom();
    }
  }

  Future<void> fetchMissedChannelNotifications({bool notify = true}) async {
    final userId = currentUser?.id;
    if (userId == null) {
      return;
    }

    try {
      final response = await http.get(
        Uri.parse(
          "$baseUrl/notifications/channel-unread?actor_user_id=$userId",
        ),
      );
      if (response.statusCode != 200) {
        return;
      }

      final List data = jsonDecode(response.body);
      var changed = false;
      for (final rawItem in data) {
        if (rawItem is! Map) {
          continue;
        }
        final item = Map<String, dynamic>.from(rawItem);
        final channelId = _tryParsePayloadInt(item['channel_id']);
        if (channelId == null || activeChannel?.id == channelId) {
          continue;
        }

        changed = _markChannelNotification(
              channelId,
              mentioned: item['mentioned'] == true,
              notify: false,
            ) ||
            changed;
      }

      if (changed && notify) {
        notifyListeners();
      }
    } catch (_) {
      // Missed notifications are a catch-up path; live sockets still handle new ones.
    }
  }

  Future<void> markChannelRead(int channelId, {int? messageId}) async {
    final userId = currentUser?.id;
    if (userId == null) {
      return;
    }

    try {
      final body = <String, dynamic>{};
      if (messageId != null) {
        body['message_id'] = messageId;
      }
      await http.post(
        Uri.parse("$baseUrl/channels/$channelId/read-state").replace(
          queryParameters: {"actor_user_id": "$userId"},
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );
    } catch (_) {
      // Read-state sync can be retried by the next fetch or socket reconnect.
    }
  }

  Duration _reconnectDelay({
    required int attempt,
    required int minSeconds,
    required int maxSeconds,
  }) {
    final boundedExponent = attempt.clamp(0, 6) as int;
    final rawSeconds = 1 << boundedExponent;
    final boundedSeconds = rawSeconds < minSeconds
        ? minSeconds
        : (rawSeconds > maxSeconds ? maxSeconds : rawSeconds);
    return Duration(seconds: boundedSeconds);
  }

  void _disconnectTextSocket() {
    _textReconnectTimer?.cancel();
    _textReconnectTimer = null;
    _textReconnectAttempt = 0;
    _stopTextPing();

    final channel = _channel;
    _channel = null;
    if (channel != null) {
      unawaited(channel.sink.close());
    }
  }

  void _connectTextSocket(Channel channel) {
    final userId = currentUser?.id;
    if (userId == null) {
      return;
    }

    final socket = createWsChannel(
      Uri.parse("$wsUrl/${channel.id}/$userId"),
    );
    _channel = socket;
    _startTextPing();

    socket.stream.listen(
      _handleTextSocketData,
      onDone: () => _handleTextSocketClosed(socket),
      onError: (error) => _handleTextSocketClosed(socket, error: error),
      cancelOnError: true,
    );

    unawaited(
      socket.ready.then((_) {
        if (!identical(_channel, socket)) {
          return;
        }
        _textReconnectAttempt = 0;
      }).catchError((_) {
        // Ignore ready failures; stream callbacks handle retries.
      }),
    );
  }

  void _handleTextSocketClosed(
    WebSocketChannel closedChannel, {
    Object? error,
  }) {
    if (!identical(_channel, closedChannel)) {
      return;
    }

    if (error != null) {
      debugPrint("text websocket closed with error: $error");
    }

    _channel = null;
    _stopTextPing();

    if (activeChannel == null || currentUser == null) {
      return;
    }

    _scheduleTextReconnect();
  }

  void _scheduleTextReconnect() {
    if (_textReconnectTimer != null) {
      return;
    }

    final delay = _reconnectDelay(
      attempt: _textReconnectAttempt,
      minSeconds: 1,
      maxSeconds: 20,
    );
    _textReconnectTimer = Timer(delay, () {
      _textReconnectTimer = null;
      final channel = activeChannel;
      if (channel == null || currentUser == null) {
        return;
      }

      _textReconnectAttempt += 1;
      _connectTextSocket(channel);
    });
  }

  void _startTextPing() {
    _textPingTimer?.cancel();
    _sendTextPing();
    _textPingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_channel == null) {
        _stopTextPing();
        return;
      }
      _sendTextPing();
    });
  }

  void _sendTextPing() {
    final channel = _channel;
    if (channel == null) {
      return;
    }

    try {
      channel.sink.add(jsonEncode({"type": "ping"}));
    } catch (_) {
      // Stream callbacks will schedule a reconnect when close/error fires.
    }
  }

  void _stopTextPing() {
    _textPingTimer?.cancel();
    _textPingTimer = null;
  }

  bool _pruneChannelNotifications(Set<int> visibleChannelIds) {
    final unreadCount = _channelsWithUnreadMessages.length;
    final mentionCount = _channelsWithMentions.length;
    _channelsWithUnreadMessages
        .removeWhere((channelId) => !visibleChannelIds.contains(channelId));
    _channelsWithMentions
        .removeWhere((channelId) => !visibleChannelIds.contains(channelId));
    return unreadCount != _channelsWithUnreadMessages.length ||
        mentionCount != _channelsWithMentions.length;
  }

  void _clearChannelNotification(int channelId, {bool notify = true}) {
    final removedUnread = _channelsWithUnreadMessages.remove(channelId);
    final removedMention = _channelsWithMentions.remove(channelId);
    final changed = removedUnread || removedMention;
    if (changed && notify) {
      notifyListeners();
    }
  }

  bool _markChannelNotification(
    int channelId, {
    required bool mentioned,
    bool notify = true,
  }) {
    var changed = false;
    if (mentioned) {
      changed = _channelsWithMentions.add(channelId) || changed;
      changed = _channelsWithUnreadMessages.remove(channelId) || changed;
    } else if (!_channelsWithMentions.contains(channelId)) {
      changed = _channelsWithUnreadMessages.add(channelId) || changed;
    }

    if (changed && notify) {
      notifyListeners();
    }
    return changed;
  }

  void _disconnectNotificationSocket() {
    _notificationReconnectTimer?.cancel();
    _notificationReconnectTimer = null;
    _notificationReconnectAttempt = 0;
    _stopNotificationPing();

    final channel = _notificationChannel;
    _notificationChannel = null;
    if (channel != null) {
      unawaited(channel.sink.close());
    }
  }

  void _connectNotificationSocket() {
    final userId = currentUser?.id;
    if (userId == null) {
      return;
    }

    final socket = createWsChannel(
      Uri.parse("$wsUrl/notifications/$userId"),
    );
    _notificationChannel = socket;
    _startNotificationPing();

    socket.stream.listen(
      _handleNotificationSocketData,
      onDone: () => _handleNotificationSocketClosed(socket),
      onError: (error) => _handleNotificationSocketClosed(socket, error: error),
      cancelOnError: true,
    );

    unawaited(
      socket.ready.then((_) {
        if (!identical(_notificationChannel, socket)) {
          return;
        }
        _notificationReconnectAttempt = 0;
        unawaited(fetchMissedChannelNotifications());
      }).catchError((_) {
        // Stream callbacks handle reconnects.
      }),
    );
  }

  void _handleNotificationSocketClosed(
    WebSocketChannel closedChannel, {
    Object? error,
  }) {
    if (!identical(_notificationChannel, closedChannel)) {
      return;
    }

    if (error != null) {
      debugPrint("notification websocket closed with error: $error");
    }

    _notificationChannel = null;
    _stopNotificationPing();

    if (currentUser == null) {
      return;
    }

    _scheduleNotificationReconnect();
  }

  void _scheduleNotificationReconnect() {
    if (_notificationReconnectTimer != null) {
      return;
    }

    final delay = _reconnectDelay(
      attempt: _notificationReconnectAttempt,
      minSeconds: 1,
      maxSeconds: 20,
    );
    _notificationReconnectTimer = Timer(delay, () {
      _notificationReconnectTimer = null;
      if (currentUser == null) {
        return;
      }

      _notificationReconnectAttempt += 1;
      _connectNotificationSocket();
    });
  }

  void _startNotificationPing() {
    _notificationPingTimer?.cancel();
    _sendNotificationPing();
    _notificationPingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_notificationChannel == null) {
        _stopNotificationPing();
        return;
      }
      _sendNotificationPing();
    });
  }

  void _sendNotificationPing() {
    final channel = _notificationChannel;
    if (channel == null) {
      return;
    }

    try {
      channel.sink.add(jsonEncode({"type": "ping"}));
    } catch (_) {
      _scheduleNotificationReconnect();
    }
  }

  void _stopNotificationPing() {
    _notificationPingTimer?.cancel();
    _notificationPingTimer = null;
  }

  void _handleNotificationSocketData(dynamic data) {
    try {
      final payload = Map<String, dynamic>.from(jsonDecode(data));
      final type = payload['type']?.toString();
      if (type == 'pong') {
        return;
      }
      if (type != 'channel_message') {
        return;
      }

      final userId = currentUser?.id;
      final channelId = _tryParsePayloadInt(payload['channel_id']);
      if (userId == null || channelId == null) {
        return;
      }

      final authorUserId = _tryParsePayloadInt(payload['author_user_id']);
      if (authorUserId == userId) {
        return;
      }

      if (activeChannel?.id == channelId) {
        _clearChannelNotification(channelId);
        return;
      }

      final mentionedUserIds =
          _parseMentionUserIds(payload['mentioned_user_ids']);
      final mentioned =
          payload['mentioned'] == true || mentionedUserIds.contains(userId);
      _markChannelNotification(channelId, mentioned: mentioned);
    } catch (_) {
      // Ignore malformed notification payloads to keep the stream alive.
    }
  }

  void _handleTextSocketData(dynamic data) {
    try {
      final payload = Map<String, dynamic>.from(jsonDecode(data));
      final type = payload['type'] ?? 'new_message';

      if (type == 'pong') {
        return;
      }

      if (type == 'new_message') {
        final newMessage = Message.fromJson(payload);
        final existingIndex =
            messages.indexWhere((message) => message.id == newMessage.id);
        if (existingIndex == -1) {
          messages.add(newMessage);
        } else {
          messages[existingIndex] = newMessage;
        }
        if (newMessage.isPinned) {
          _applyPinStateFromMessage(newMessage);
        }
        final channelId = activeChannel?.id;
        if (channelId != null) {
          _clearChannelNotification(channelId, notify: false);
          unawaited(markChannelRead(channelId, messageId: newMessage.id));
        }
        _scrollToBottom();
        // Multiple delayed scroll attempts to handle different image loading speeds
        if (newMessage.attachmentUrl != null) {
          for (final delayMs in [300, 800, 1500, 3000]) {
            Future.delayed(Duration(milliseconds: delayMs), () {
              if (activeChannel?.id != null) {
                _scrollToBottom();
              }
            });
          }
        }
      } else if (type == 'music_bot_notice') {
        final content = (payload['content'] ?? '').toString().trim();
        if (content.isNotEmpty) {
          _appendLocalSystemMessage(content);
          _scrollToBottom();
        }
      } else if (type == 'edit_message') {
        final id = payload['id'];
        final content = payload['content']?.toString() ?? '';
        final mentionedUserIds =
            _parseMentionUserIds(payload['mentioned_user_ids']);
        final mentionedUsernames =
            _parseMentionUsernames(payload['mentioned_usernames']);
        final index = messages.indexWhere((m) => m.id == id);
        if (index != -1) {
          messages[index] = messages[index].copyWith(
            content: content,
            mentionedUserIds: mentionedUserIds,
            mentionedUsernames: mentionedUsernames,
          );
        }
        final searchIndex = messageSearchResults.indexWhere((m) => m.id == id);
        if (searchIndex != -1) {
          messageSearchResults[searchIndex] =
              messageSearchResults[searchIndex].copyWith(
            content: content,
            mentionedUserIds: mentionedUserIds,
            mentionedUsernames: mentionedUsernames,
          );
        }
        final pinnedIndex = pinnedMessages.indexWhere((m) => m.id == id);
        if (pinnedIndex != -1) {
          pinnedMessages[pinnedIndex] =
              pinnedMessages[pinnedIndex].copyWith(
            content: content,
            mentionedUserIds: mentionedUserIds,
            mentionedUsernames: mentionedUsernames,
          );
        }
      } else if (type == 'delete_message') {
        final id = payload['id'];
        messages.removeWhere((m) => m.id == id);
        messageSearchResults.removeWhere((m) => m.id == id);
        pinnedMessages.removeWhere((m) => m.id == id);
      } else if (type == 'pin_message') {
        final id = payload['id'];
        if (id is int) {
          _applyPinStateById(
            messageId: id,
            isPinned: true,
            pinnedAt: payload['pinned_at']?.toString(),
            pinnedByUserId:
                payload['pinned_by_user_id'] is int ? payload['pinned_by_user_id'] : null,
            pinnedByUsername: payload['pinned_by_username']?.toString(),
          );
        }
      } else if (type == 'unpin_message') {
        final id = payload['id'];
        if (id is int) {
          _applyPinStateById(
            messageId: id,
            isPinned: false,
            pinnedAt: null,
            pinnedByUserId: null,
            pinnedByUsername: null,
          );
        }
      }

      notifyListeners();
    } catch (_) {
      // Ignore malformed payloads to keep the stream alive.
    }
  }

  void selectChannel(Channel channel) {
    activeChannel = channel;
    _clearChannelNotification(channel.id, notify: false);
    messages = [];
    pinnedMessages = [];
    pinnedMessagesError = null;
    pinnedMessagesLoading = false;
    replyingTo = null;
    editingMessage = null;
    clearMessageSearch(notify: false);

    _disconnectTextSocket();
    unawaited(fetchMessages(channel.id));
    unawaited(fetchPinnedMessages());
    _connectTextSocket(channel);

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
    await leaveVoiceChannel(notify: false, disableAutoReconnect: false);

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
      _voiceShouldReconnect = true;
      _voiceReconnectAttempt = 0;
      _voiceReconnectChannel = channel;
      _voiceReconnectTimer?.cancel();
      _voiceReconnectTimer = null;
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
      await leaveVoiceChannel(
        notify: false,
        clearError: false,
        disableAutoReconnect: false,
      );
      notifyListeners();
      return false;
    } finally {
      _voiceJoinInProgress = false;
    }
  }

  void _handleVoiceSocketClosed({Object? error}) {
    final reconnectChannel = activeVoiceChannel;
    if (reconnectChannel == null) {
      return;
    }

    voiceError = error == null
        ? "Voice channel disconnected"
        : "Voice connection error: $error";

    unawaited(_recoverVoiceFromDisconnect(reconnectChannel));
  }

  Future<void> _recoverVoiceFromDisconnect(VoiceChannel reconnectChannel) async {
    await leaveVoiceChannel(
      notify: true,
      clearError: false,
      disableAutoReconnect: false,
    );
    if (!_voiceShouldReconnect || currentUser == null) {
      return;
    }

    _voiceReconnectChannel = reconnectChannel;
    _scheduleVoiceReconnect();
  }

  void _scheduleVoiceReconnect() {
    if (_voiceReconnectTimer != null || !_voiceShouldReconnect) {
      return;
    }

    final delay = _reconnectDelay(
      attempt: _voiceReconnectAttempt,
      minSeconds: 2,
      maxSeconds: 20,
    );
    _voiceReconnectTimer = Timer(delay, () {
      _voiceReconnectTimer = null;
      unawaited(_attemptVoiceReconnect());
    });
  }

  Future<void> _attemptVoiceReconnect() async {
    if (!_voiceShouldReconnect || currentUser == null) {
      return;
    }

    final pendingChannel = _voiceReconnectChannel;
    if (pendingChannel == null) {
      return;
    }

    VoiceChannel? targetChannel;
    for (final channel in voiceChannels) {
      if (channel.id == pendingChannel.id) {
        targetChannel = channel;
        break;
      }
    }

    if (targetChannel == null) {
      await fetchVoiceChannels();
      for (final channel in voiceChannels) {
        if (channel.id == pendingChannel.id) {
          targetChannel = channel;
          break;
        }
      }
    }

    if (targetChannel == null) {
      _voiceShouldReconnect = false;
      _voiceReconnectChannel = null;
      _voiceReconnectAttempt = 0;
      voiceError = "Voice channel is no longer available.";
      notifyListeners();
      return;
    }

    _voiceReconnectAttempt += 1;
    final joined = await joinVoiceChannel(targetChannel, forceRejoin: true);
    if (joined) {
      _voiceReconnectAttempt = 0;
      _voiceReconnectChannel = targetChannel;
      return;
    }

    if (_voiceShouldReconnect) {
      _scheduleVoiceReconnect();
    }
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
        _screenSharingUserIds
          ..clear()
          ..addAll(
            participants
                .where((participant) => participant.isScreenSharing)
                .map((participant) => participant.userId),
          );
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
        _setScreenShareStateForUser(
          participant.userId,
          participant.isScreenSharing,
          notify: false,
        );

        if (participant.userId != currentUser?.id && !participant.isBot) {
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
          _screenSharingUserIds.remove(userId);
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

      if (type == 'screen_share_state') {
        final userId = payload['user_id'];
        if (userId is int) {
          final isScreenSharing = payload['is_screen_sharing'] == true;
          _setScreenShareStateForUser(
            userId,
            isScreenSharing,
            notify: false,
          );
          if (!isScreenSharing && userId != currentUser?.id) {
            await _clearRemoteScreenShare(userId, disposeStream: true);
          }
          notifyListeners();
        }
        return;
      }

      if (type == 'music_play') {
        await _handleMusicPlaySignal(payload);
        return;
      }

      if (type == 'music_stop') {
        await _stopMusicPlayback();
        return;
      }

      if (type == 'music_volume') {
        await _handleMusicVolumeSignal(payload);
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
    } catch (error, stackTrace) {
      debugPrint('voice signal handler failed: $error');
      debugPrint('voice signal payload: $data');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _handleMusicPlaySignal(Map<String, dynamic> payload) async {
    final streamUrl = payload['stream_url'];
    if (streamUrl == null) {
      await _stopMusicPlayback();
      return;
    }

    if (streamUrl is! String || streamUrl.isEmpty) {
      voiceError = "Music bot sent an invalid stream URL.";
      notifyListeners();
      return;
    }
    final trackId = _tryParseMusicTrackId(payload['track_id']);
    final playbackVolume = voiceParticipantVolumeFor(_musicBotUserId);

    _suppressMusicCompletionSignals = true;
    try {
      await _applyMusicPlaybackVolume(playbackVolume);
      await _musicPlayer.stop();
      await _musicPlayer.open(
        media_kit.Media(streamUrl),
        play: true,
      );
      await _applyMusicPlaybackVolume(playbackVolume);
      _activeMusicTrackId = trackId;
      voiceError = null;
      notifyListeners();
    } catch (error) {
      debugPrint(
        'music playback failed (media_kit): streamUrl=$streamUrl error=$error',
      );
      _activeMusicTrackId = null;
      voiceError = "Unable to start music playback: $error";
      notifyListeners();
    } finally {
      _suppressMusicCompletionSignals = false;
    }
  }

  Future<void> _handleMusicVolumeSignal(Map<String, dynamic> payload) async {
    final targetUserId = _tryParsePayloadInt(payload['target_user_id']);
    if (targetUserId == null || targetUserId != currentUser?.id) {
      return;
    }

    final userId = payload['user_id'];
    final normalizedVolume = _tryParseMusicVolume(payload['volume']);
    if (userId is! int || normalizedVolume == null) {
      return;
    }

    setVoiceParticipantVolume(
      userId,
      normalizedVolume,
    );
  }

  int? _tryParseMusicTrackId(dynamic rawTrackId) {
    return _tryParsePayloadInt(rawTrackId);
  }

  int? _tryParsePayloadInt(dynamic rawValue) {
    if (rawValue is int) {
      return rawValue;
    }
    if (rawValue is num) {
      return rawValue.round();
    }
    if (rawValue is String) {
      return int.tryParse(rawValue.trim());
    }
    return null;
  }

  double? _tryParseMusicVolume(dynamic rawVolume) {
    if (rawVolume is num) {
      return rawVolume.toDouble().clamp(0.0, 5.0).toDouble();
    }
    if (rawVolume is String) {
      final parsed = double.tryParse(rawVolume.trim());
      if (parsed == null) {
        return null;
      }
      return parsed.clamp(0.0, 5.0).toDouble();
    }
    return null;
  }

  void _handleMusicTrackCompleted() {
    if (_suppressMusicCompletionSignals) {
      return;
    }

    final trackId = _activeMusicTrackId;
    if (trackId == null) {
      return;
    }

    _activeMusicTrackId = null;
    _sendVoiceSignal({
      'type': 'music_track_ended',
      'track_id': trackId,
    });
  }

  Future<void> _stopMusicPlayback({
    bool notify = true,
    bool clearError = true,
  }) async {
    _activeMusicTrackId = null;
    _suppressMusicCompletionSignals = true;
    try {
      await _musicPlayer.stop();
      if (clearError) {
        voiceError = null;
      }
    } catch (error) {
      debugPrint('music stop failed: $error');
      if (clearError) {
        voiceError = "Unable to stop music playback: $error";
      }
    } finally {
      _suppressMusicCompletionSignals = false;
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> _applyMusicPlaybackVolume(double volume) async {
    final normalized = volume.clamp(0.0, 5.0).toDouble();
    try {
      await _musicPlayer.setVolume(normalized * 100.0);
    } catch (_) {
      // Ignore volume errors on platforms/backends that don't expose gain control.
    }
  }

  bool _looksLikeManifestStreamUrl(String url) {
    final normalized = url.trim().toLowerCase();
    return normalized.contains('.m3u8') || normalized.contains('.mpd');
  }

  String? _resolveMusicStreamMimeType(String streamUrl, bool isManifest) {
    if (!isManifest) {
      return null;
    }

    final normalized = streamUrl.toLowerCase();
    if (normalized.contains('.mpd')) {
      return 'application/dash+xml';
    }
    return 'application/vnd.apple.mpegurl';
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
    await _addLocalScreenTrackToPeer(remoteUserId, peerConnection);

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
      final trackKind = event.track.kind;
      if (trackKind != 'audio' && trackKind != 'video') {
        return;
      }

      final remoteStream = event.streams.isNotEmpty
          ? event.streams.first
          : (trackKind == 'video'
              ? _remoteScreenStreams[remoteUserId]
              : _remoteStreams[remoteUserId]);
      if (remoteStream == null) {
        return;
      }

      if (trackKind == 'video') {
        _remoteScreenStreams[remoteUserId] = remoteStream;
        _setScreenShareStateForUser(remoteUserId, true, notify: false);
        unawaited(_attachRemoteScreenRenderer(remoteUserId, remoteStream));
      } else {
        _remoteStreams[remoteUserId] = remoteStream;
        unawaited(_attachRemoteAudioRenderer(remoteUserId, remoteStream));
      }
      notifyListeners();
    };

    peerConnection.onRemoveTrack = (stream, track) {
      if (track.kind == 'video') {
        unawaited(_clearRemoteScreenShare(
          remoteUserId,
          disposeStream: true,
          clearSharingState: false,
        ));
      }
    };

    peerConnection.onConnectionState = (state) {
      _peerConnectionStates[remoteUserId] = state;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _schedulePeerDisconnectClose(remoteUserId);
      } else {
        _cancelPeerDisconnectTimer(remoteUserId);
      }

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        unawaited(_closePeerConnection(remoteUserId).then((_) {
          notifyListeners();
        }));
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
      'offerToReceiveVideo': true,
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
      'offerToReceiveVideo': true,
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

  Future<bool> toggleScreenShare({DesktopCapturerSource? source}) async {
    if (isScreenSharing) {
      await stopScreenShare();
      return true;
    }
    return startScreenShare(source: source);
  }

  Future<bool> startScreenShare({DesktopCapturerSource? source}) async {
    if (currentUser == null ||
        activeVoiceChannel == null ||
        _voiceSignalChannel == null) {
      screenShareError = "Join a voice channel before sharing your screen.";
      notifyListeners();
      return false;
    }

    if (_screenShareStarting) {
      return false;
    }

    if (_localScreenStream != null) {
      return true;
    }

    if (WebRTC.platformIsDesktop && source == null) {
      screenShareError = "Choose a screen or window before sharing.";
      notifyListeners();
      return false;
    }

    _screenShareStarting = true;
    screenShareError = null;
    notifyListeners();

    MediaStream? screenStream;
    RTCVideoRenderer? renderer;
    try {
      screenStream = await navigator.mediaDevices.getDisplayMedia(
        _screenShareConstraints(source),
      );

      final videoTracks = screenStream.getVideoTracks();
      if (videoTracks.isEmpty) {
        throw StateError("No screen video track was returned.");
      }

      final videoTrack = videoTracks.first;
      videoTrack.onEnded = () {
        unawaited(stopScreenShare());
      };

      renderer = RTCVideoRenderer();
      await renderer.initialize();
      renderer.srcObject = screenStream;
      try {
        renderer.muted = true;
      } catch (_) {
        // Some platforms do not expose mute on local preview renderers.
      }

      _localScreenStream = screenStream;
      _localScreenRenderer = renderer;
      _setScreenShareStateForUser(
        currentUser!.id,
        true,
        notify: false,
      );
      _sendVoiceSignal({
        'type': 'screen_share_state',
        'is_screen_sharing': true,
      });

      var failedUpdates = 0;
      for (final entry in _peerConnections.entries.toList()) {
        final remoteUserId = entry.key;
        if (_isMusicBotParticipantId(remoteUserId)) {
          continue;
        }

        try {
          await _addLocalScreenTrackToPeer(remoteUserId, entry.value);
          await _createOfferForUser(remoteUserId);
        } catch (error, stackTrace) {
          failedUpdates += 1;
          debugPrint(
            'screen share renegotiation failed for user $remoteUserId: $error',
          );
          debugPrintStack(stackTrace: stackTrace);
        }
      }

      if (failedUpdates > 0) {
        screenShareError =
            "Screen sharing started, but $failedUpdates viewer connection(s) could not be updated.";
      }

      return true;
    } catch (error, stackTrace) {
      debugPrint('startScreenShare failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      screenShareError = _screenShareStartError(error);
      if (renderer != null) {
        try {
          renderer.srcObject = null;
          await renderer.dispose();
        } catch (_) {
          // Ignore renderer cleanup failures after a failed capture.
        }
      }
      if (screenStream != null) {
        for (final track in screenStream.getTracks()) {
          track.onEnded = null;
        }
        await _disposeStreamSafely(screenStream);
      }
      _localScreenRenderer = null;
      _localScreenStream = null;
      _screenShareSenders.clear();
      final selfId = currentUser?.id;
      if (selfId != null) {
        _setScreenShareStateForUser(selfId, false, notify: false);
      }
      return false;
    } finally {
      _screenShareStarting = false;
      notifyListeners();
    }
  }

  Map<String, dynamic> _screenShareConstraints(
    DesktopCapturerSource? source,
  ) {
    if (source == null) {
      return {
        'video': true,
        'audio': false,
      };
    }

    return {
      'video': {
        'deviceId': {'exact': source.id},
        'mandatory': {'frameRate': 30.0},
      },
      'audio': false,
    };
  }

  String _screenShareStartError(Object error) {
    final message = error.toString();
    if (message.contains('source not found')) {
      return "The selected screen or window is no longer available. Choose another source and try again.";
    }
    if (message.contains('Permission') || message.contains('permission')) {
      return "Screen sharing permission was denied.";
    }
    return "Unable to start screen sharing: $message";
  }

  Future<void> stopScreenShare({
    bool notify = true,
    bool broadcast = true,
    bool renegotiate = true,
  }) async {
    if (_localScreenStream == null &&
        _localScreenRenderer == null &&
        _screenShareSenders.isEmpty &&
        !_screenShareStarting) {
      return;
    }

    _screenShareStarting = false;
    screenShareError = null;
    final senderEntries = _screenShareSenders.entries.toList();
    _screenShareSenders.clear();

    if (renegotiate) {
      for (final entry in senderEntries) {
        final peerConnection = _peerConnections[entry.key];
        if (peerConnection == null) {
          continue;
        }

        try {
          await peerConnection.removeTrack(entry.value);
        } catch (_) {
          // The peer may already be closing; teardown continues below.
        }

        try {
          await entry.value.dispose();
        } catch (_) {
          // Sender disposal is best-effort after removeTrack.
        }
      }
    }

    await _disposeLocalScreenCapture();

    final selfId = currentUser?.id;
    if (selfId != null) {
      _setScreenShareStateForUser(selfId, false, notify: false);
    }

    if (broadcast) {
      _sendVoiceSignal({
        'type': 'screen_share_state',
        'is_screen_sharing': false,
      });
    }

    if (renegotiate) {
      for (final remoteUserId in senderEntries.map((entry) => entry.key).toSet()) {
        if (!_peerConnections.containsKey(remoteUserId)) {
          continue;
        }

        try {
          await _createOfferForUser(remoteUserId);
        } catch (error, stackTrace) {
          debugPrint(
            'screen share stop renegotiation failed for user $remoteUserId: $error',
          );
          debugPrintStack(stackTrace: stackTrace);
        }
      }
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> _addLocalScreenTrackToPeer(
    int remoteUserId,
    RTCPeerConnection peerConnection,
  ) async {
    if (_isMusicBotParticipantId(remoteUserId) ||
        _screenShareSenders.containsKey(remoteUserId)) {
      return;
    }

    final screenStream = _localScreenStream;
    if (screenStream == null) {
      return;
    }

    final videoTracks = screenStream.getVideoTracks();
    if (videoTracks.isEmpty) {
      return;
    }

    final sender = await peerConnection.addTrack(videoTracks.first, screenStream);
    _screenShareSenders[remoteUserId] = sender;
  }

  void _setScreenShareStateForUser(
    int userId,
    bool isScreenSharing, {
    bool notify = true,
  }) {
    if (isScreenSharing) {
      _screenSharingUserIds.add(userId);
    } else {
      _screenSharingUserIds.remove(userId);
    }

    final participant = voiceParticipants[userId];
    if (participant != null &&
        participant.isScreenSharing != isScreenSharing) {
      voiceParticipants[userId] = participant.copyWith(
        isScreenSharing: isScreenSharing,
      );
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> _disposeLocalScreenCapture() async {
    final renderer = _localScreenRenderer;
    final screenStream = _localScreenStream;
    _localScreenRenderer = null;
    _localScreenStream = null;

    if (screenStream != null) {
      for (final track in screenStream.getTracks()) {
        track.onEnded = null;
      }
    }

    if (renderer != null) {
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

    if (screenStream != null) {
      await _disposeStreamSafely(screenStream);
    }
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

  Future<void> leaveVoiceChannel({
    bool notify = true,
    bool clearError = true,
    bool disableAutoReconnect = true,
  }) async {
    if (disableAutoReconnect) {
      _voiceShouldReconnect = false;
      _voiceReconnectChannel = null;
      _voiceReconnectAttempt = 0;
      _voiceReconnectTimer?.cancel();
      _voiceReconnectTimer = null;
    }

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
    screenShareError = null;
    _voiceConnectedAt = null;
    _queuedRemoteIceCandidates.clear();
    _remoteDescriptionReadyUsers.clear();
    _voiceSignalProcessingQueue = Future.value();
    _cancelAllPeerDisconnectTimers();
    await stopScreenShare(
      notify: false,
      broadcast: false,
      renegotiate: false,
    );
    if (_inputTestUsesVoiceStream) {
      await stopInputTest(notify: false);
    }
    _resetVoiceDiagnostics();
    await _stopMicProbe();
    await _stopMusicPlayback(notify: false, clearError: false);

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
    for (final userId in _remoteScreenRenderers.keys.toList()) {
      await _disposeRemoteScreenRenderer(userId);
    }

    final remoteStreamsToDispose = <MediaStream>{
      ..._remoteStreams.values,
      ..._remoteScreenStreams.values,
    };
    for (final stream in remoteStreamsToDispose) {
      await _disposeStreamSafely(stream);
    }
    _remoteStreams.clear();
    _remoteScreenStreams.clear();

    final localStream = _localStream;
    _localStream = null;
    if (localStream != null) {
      await _disposeStreamSafely(localStream);
    }

    voiceParticipants.clear();
    _voiceParticipantVolumes.clear();
    _screenSharingUserIds.clear();
    _screenShareSenders.clear();
    _peerConnectionStates.clear();

    if (notify) {
      notifyListeners();
    }
  }

  void _schedulePeerDisconnectClose(int remoteUserId) {
    if (_peerDisconnectTimers.containsKey(remoteUserId)) {
      return;
    }

    _peerDisconnectTimers[remoteUserId] = Timer(const Duration(seconds: 8), () {
      _peerDisconnectTimers.remove(remoteUserId);
      if (_peerConnectionStates[remoteUserId] !=
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        return;
      }

      unawaited(_closePeerConnection(remoteUserId).then((_) {
        notifyListeners();
      }));
    });
  }

  void _cancelPeerDisconnectTimer(int remoteUserId) {
    _peerDisconnectTimers.remove(remoteUserId)?.cancel();
  }

  void _cancelAllPeerDisconnectTimers() {
    for (final timer in _peerDisconnectTimers.values) {
      timer.cancel();
    }
    _peerDisconnectTimers.clear();
  }

  Future<void> _closePeerConnection(int remoteUserId) async {
    _cancelPeerDisconnectTimer(remoteUserId);
    _screenShareSenders.remove(remoteUserId);
    final peerConnection = _peerConnections.remove(remoteUserId);
    if (peerConnection != null) {
      peerConnection.onIceCandidate = null;
      peerConnection.onTrack = null;
      peerConnection.onRemoveTrack = null;
      peerConnection.onConnectionState = null;
      await _closePeerConnectionSafely(peerConnection);
    }

    _remoteDescriptionReadyUsers.remove(remoteUserId);
    _queuedRemoteIceCandidates.remove(remoteUserId);
    _peerConnectionStates.remove(remoteUserId);
    await _disposeRemoteAudioRenderer(remoteUserId);
    await _disposeRemoteScreenRenderer(remoteUserId);
    _screenSharingUserIds.remove(remoteUserId);

    final streamsToDispose = <MediaStream>{};
    final remoteStream = _remoteStreams.remove(remoteUserId);
    if (remoteStream != null) {
      streamsToDispose.add(remoteStream);
    }
    final remoteScreenStream = _remoteScreenStreams.remove(remoteUserId);
    if (remoteScreenStream != null) {
      streamsToDispose.add(remoteScreenStream);
    }

    for (final stream in streamsToDispose) {
      await _disposeStreamSafely(stream);
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

  Future<void> _attachRemoteScreenRenderer(
    int remoteUserId,
    MediaStream remoteStream,
  ) async {
    var renderer = _remoteScreenRenderers[remoteUserId];
    var shouldNotify = false;

    if (renderer == null) {
      renderer = RTCVideoRenderer();
      await renderer.initialize();
      _remoteScreenRenderers[remoteUserId] = renderer;
      shouldNotify = true;
    }

    final currentStream = renderer.srcObject;
    if (currentStream == null || currentStream.id != remoteStream.id) {
      renderer.srcObject = remoteStream;
      try {
        renderer.muted = true;
      } catch (_) {
        // Some platforms throw if mute toggling is unsupported.
      }
      shouldNotify = true;
    }

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
    final normalized = volume.clamp(0.0, 5.0).toDouble();
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

  Future<void> _clearRemoteScreenShare(
    int remoteUserId, {
    bool disposeStream = false,
    bool notify = false,
    bool clearSharingState = true,
  }) async {
    if (clearSharingState) {
      _setScreenShareStateForUser(remoteUserId, false, notify: false);
    }
    await _disposeRemoteScreenRenderer(remoteUserId);

    final screenStream = _remoteScreenStreams.remove(remoteUserId);
    if (disposeStream && screenStream != null) {
      final audioStream = _remoteStreams[remoteUserId];
      if (audioStream == null || audioStream.id != screenStream.id) {
        await _disposeStreamSafely(screenStream);
      }
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> _disposeRemoteScreenRenderer(int remoteUserId) async {
    final renderer = _remoteScreenRenderers.remove(remoteUserId);
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
    if (index != -1) {
      itemScrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.1,
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (messages.isNotEmpty && itemScrollController.isAttached) {
        itemScrollController.scrollTo(
          index: messages.length - 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _appendLocalSystemMessage(String content) {
    messages.add(
      Message(
        id: _nextLocalMessageId--,
        userId: 0,
        username: "Music Bot",
        content: content,
        timestamp: DateTime.now().toUtc().toIso8601String(),
      ),
    );
    notifyListeners();
  }

  void _applyPinStateFromMessage(Message source) {
    _applyPinStateById(
      messageId: source.id,
      isPinned: source.isPinned,
      pinnedAt: source.pinnedAt,
      pinnedByUserId: source.pinnedByUserId,
      pinnedByUsername: source.pinnedByUsername,
    );
  }

  void _applyPinStateById({
    required int messageId,
    required bool isPinned,
    required String? pinnedAt,
    required int? pinnedByUserId,
    required String? pinnedByUsername,
  }) {
    final messageIndex = messages.indexWhere((message) => message.id == messageId);
    if (messageIndex != -1) {
      final existing = messages[messageIndex];
      messages[messageIndex] = existing.copyWith(
        isPinned: isPinned,
        pinnedAt: pinnedAt,
        pinnedByUserId: pinnedByUserId,
        pinnedByUsername: pinnedByUsername,
      );
    }

    final searchIndex = messageSearchResults
        .indexWhere((message) => message.id == messageId);
    if (searchIndex != -1) {
      final existing = messageSearchResults[searchIndex];
      messageSearchResults[searchIndex] = existing.copyWith(
        isPinned: isPinned,
        pinnedAt: pinnedAt,
        pinnedByUserId: pinnedByUserId,
        pinnedByUsername: pinnedByUsername,
      );
    }

    if (!isPinned) {
      pinnedMessages.removeWhere((message) => message.id == messageId);
      return;
    }

    final messageToPin = messageIndex != -1
        ? messages[messageIndex]
        : (searchIndex != -1 ? messageSearchResults[searchIndex] : null);
    if (messageToPin == null) {
      return;
    }

    final pinnedIndex =
        pinnedMessages.indexWhere((message) => message.id == messageId);
    if (pinnedIndex == -1) {
      pinnedMessages.add(messageToPin);
    } else {
      pinnedMessages[pinnedIndex] = messageToPin;
    }

    DateTime parseSortDate(Message message) {
      final pinnedDate = message.pinnedAt != null
          ? DateTime.tryParse(message.pinnedAt!)
          : null;
      if (pinnedDate != null) {
        return pinnedDate;
      }
      return DateTime.tryParse(message.timestamp) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    pinnedMessages.sort((a, b) => parseSortDate(b).compareTo(parseSortDate(a)));
  }

  List<int> _parseMentionUserIds(dynamic rawValue) {
    if (rawValue is! List) {
      return const <int>[];
    }
    return rawValue
        .map((value) {
          if (value is int) {
            return value;
          }
          return int.tryParse(value.toString());
        })
        .whereType<int>()
        .toList(growable: false);
  }

  List<String> _parseMentionUsernames(dynamic rawValue) {
    if (rawValue is! List) {
      return const <String>[];
    }
    return rawValue
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
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
      try {
        _channel!.sink.add(jsonEncode(messageData));
      } catch (_) {
        _scheduleTextReconnect();
      }
      editingMessage = null;
    } else {
      final messageData = {
        "type": "new_message",
        "content": content,
        "parent_id": replyingTo?.id,
      };
      try {
        _channel!.sink.add(jsonEncode(messageData));
      } catch (_) {
        _scheduleTextReconnect();
      }
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
      try {
        _channel!.sink.add(jsonEncode(messageData));
      } catch (_) {
        _scheduleTextReconnect();
      }
    }
  }

  @override
  void dispose() {
    _disconnectTextSocket();
    _disconnectNotificationSocket();
    _voiceShouldReconnect = false;
    _voiceReconnectChannel = null;
    _voiceReconnectAttempt = 0;
    _voiceReconnectTimer?.cancel();
    _voiceReconnectTimer = null;
    _voiceSignalChannel?.sink.close();
    unawaited(_musicPlayerCompletionSubscription?.cancel() ?? Future.value());
    _musicPlayerCompletionSubscription = null;
    _activeMusicTrackId = null;
    _suppressMusicCompletionSignals = true;
    _voicePingTimer?.cancel();
    _voicePingTimer = null;
    _textPingTimer?.cancel();
    _textPingTimer = null;
    _textReconnectTimer?.cancel();
    _textReconnectTimer = null;
    _voiceDiagnosticsTimer?.cancel();
    _voiceDiagnosticsTimer = null;
    _inputTestTimer?.cancel();
    _inputTestTimer = null;
    _cancelAllPeerDisconnectTimers();
    unawaited(_stopMicProbe());
    unawaited(_musicPlayer.dispose());
    unawaited(stopInputTest(notify: false));

    for (final peerConnection in _peerConnections.values) {
      peerConnection.onIceCandidate = null;
      peerConnection.onTrack = null;
      peerConnection.onRemoveTrack = null;
      peerConnection.onConnectionState = null;
      unawaited(_closePeerConnectionSafely(peerConnection));
    }

    for (final stream in <MediaStream>{
      ..._remoteStreams.values,
      ..._remoteScreenStreams.values,
    }) {
      unawaited(_disposeStreamSafely(stream));
    }
    for (final userId in _remoteAudioRenderers.keys.toList()) {
      unawaited(_disposeRemoteAudioRenderer(userId));
    }
    for (final userId in _remoteScreenRenderers.keys.toList()) {
      unawaited(_disposeRemoteScreenRenderer(userId));
    }

    final localStream = _localStream;
    if (localStream != null) {
      unawaited(_disposeStreamSafely(localStream));
    }
    final localScreenStream = _localScreenStream;
    if (localScreenStream != null) {
      for (final track in localScreenStream.getTracks()) {
        track.onEnded = null;
      }
      unawaited(_disposeStreamSafely(localScreenStream));
    }
    final localScreenRenderer = _localScreenRenderer;
    if (localScreenRenderer != null) {
      try {
        localScreenRenderer.srcObject = null;
      } catch (_) {
        // Ignore renderer detachment failures during app disposal.
      }
      unawaited(localScreenRenderer.dispose());
    }

    _peerConnections.clear();
    _peerConnectionStates.clear();
    _remoteStreams.clear();
    _remoteScreenStreams.clear();
    _remoteAudioRenderers.clear();
    _remoteScreenRenderers.clear();
    _screenShareSenders.clear();
    _screenSharingUserIds.clear();
    _queuedRemoteIceCandidates.clear();
    _remoteDescriptionReadyUsers.clear();
    _voiceSignalProcessingQueue = Future.value();
    _pendingVoicePings.clear();
    _localStream = null;
    _localScreenStream = null;
    _localScreenRenderer = null;
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
