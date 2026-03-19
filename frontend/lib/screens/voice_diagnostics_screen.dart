import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../models/chat_models.dart';
import '../providers/app_state.dart';

class VoiceDiagnosticsScreen extends StatelessWidget {
  const VoiceDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final participants = state.voiceParticipants.values.toList()
      ..sort(
        (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
      );
    final ping = state.voicePingMs;
    final micLevel = state.voiceMicLevel.clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Voice Diagnostics"),
        actions: [
          IconButton(
            tooltip: "Send ping now",
            onPressed: state.activeVoiceChannel == null
                ? null
                : state.sendVoicePingNow,
            icon: const Icon(Icons.network_ping),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _MetricCard(
            title: "Connection",
            children: [
              _MetricRow(
                label: "Channel",
                value: state.activeVoiceChannel?.name ?? "Not connected",
              ),
              _MetricRow(label: "Signal", value: state.voiceSignalStatusLabel),
              _MetricRow(
                label: "Connected for",
                value: _formatConnectionDuration(state.voiceConnectedAt),
              ),
              _MetricRow(
                label: "Participants",
                value: "${state.voiceParticipants.length}",
              ),
              _MetricRow(
                label: "Peer connections",
                value: "${state.activePeerConnectionCount}",
              ),
              _MetricRow(
                label: "Remote streams",
                value: "${state.remoteStreamCount}",
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MetricCard(
            title: "Ping",
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _pingColor(ping).withOpacity(0.2),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                ping == null ? "-- ms" : "$ping ms",
                style: TextStyle(
                  color: _pingColor(ping),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            children: [
              _MetricRow(
                label: "Last pong",
                value: _formatLastPong(state.lastVoicePongAt),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MetricCard(
            title: "Microphone",
            children: [
              _MetricRow(
                label: "Audio track",
                value: state.hasLocalAudioTrack ? "Present" : "Missing",
              ),
              _MetricRow(
                label: "Track status",
                value: state.isLocalMicTrackEnabled ? "Enabled" : "Disabled",
              ),
              _MetricRow(
                label: "Mute status",
                value: state.isSelfMuted ? "Muted" : "Unmuted",
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 12,
                  value: micLevel,
                  backgroundColor: const Color(0xFF2F3136),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _micColor(state, micLevel),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text("Input level ${(micLevel * 100).round()}%"),
            ],
          ),
          const SizedBox(height: 12),
          _MetricCard(
            title: "Network",
            children: [
              _MetricRow(
                label: "Outbound bitrate",
                value:
                    "${state.voiceOutboundBitrateKbps.toStringAsFixed(1)} kbps",
              ),
              _MetricRow(
                label: "Outbound packets",
                value:
                    "${state.voiceOutboundPacketsPerSecond.toStringAsFixed(1)} pkt/s",
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MetricCard(
            title: "Peer Health",
            children: [
              if (participants.isEmpty)
                const Text(
                  "No active voice participants.",
                  style: TextStyle(color: Colors.grey),
                )
              else
                ...participants.map(
                  (participant) => _ParticipantStateRow(
                    participant: participant,
                    isCurrentUser: participant.userId == state.currentUser?.id,
                    connectionState:
                        state.peerConnectionStates[participant.userId],
                  ),
                ),
            ],
          ),
          if (state.voiceError != null) ...[
            const SizedBox(height: 12),
            _MetricCard(
              title: "Last Error",
              children: [
                Text(
                  state.voiceError!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static Color _pingColor(int? pingMs) {
    if (pingMs == null) {
      return Colors.grey;
    }
    if (pingMs <= 90) {
      return Colors.greenAccent;
    }
    if (pingMs <= 180) {
      return Colors.amberAccent;
    }
    return Colors.redAccent;
  }

  static Color _micColor(AppState state, double micLevel) {
    if (!state.hasLocalAudioTrack || !state.isLocalMicTrackEnabled) {
      return Colors.grey;
    }
    if (state.isSelfMuted) {
      return Colors.redAccent;
    }
    if (micLevel > 0.7) {
      return Colors.greenAccent;
    }
    if (micLevel > 0.35) {
      return Colors.lightGreenAccent;
    }
    return Colors.blueAccent;
  }

  static String _formatConnectionDuration(DateTime? connectedAt) {
    if (connectedAt == null) {
      return "--";
    }

    final elapsed = DateTime.now().difference(connectedAt);
    if (elapsed.inSeconds < 60) {
      return "${elapsed.inSeconds}s";
    }
    if (elapsed.inMinutes < 60) {
      return "${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s";
    }
    return "${elapsed.inHours}h ${elapsed.inMinutes % 60}m";
  }

  static String _formatLastPong(DateTime? lastPongAt) {
    if (lastPongAt == null) {
      return "Waiting";
    }

    final elapsed = DateTime.now().difference(lastPongAt);
    if (elapsed.inSeconds < 1) {
      return "Just now";
    }
    if (elapsed.inSeconds < 60) {
      return "${elapsed.inSeconds}s ago";
    }
    if (elapsed.inMinutes < 60) {
      return "${elapsed.inMinutes}m ago";
    }
    return "${elapsed.inHours}h ago";
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2F3136),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF202225)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                    color: Colors.grey,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ParticipantStateRow extends StatelessWidget {
  const _ParticipantStateRow({
    required this.participant,
    required this.isCurrentUser,
    required this.connectionState,
  });

  final VoiceParticipant participant;
  final bool isCurrentUser;
  final RTCPeerConnectionState? connectionState;

  @override
  Widget build(BuildContext context) {
    final stateLabel = isCurrentUser
        ? "local"
        : _peerStateLabel(connectionState ??
            RTCPeerConnectionState.RTCPeerConnectionStateNew);
    final stateColor =
        isCurrentUser ? Colors.blueAccent : _peerStateColor(connectionState);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            participant.isMuted ? Icons.mic_off : Icons.mic,
            size: 15,
            color: participant.isMuted ? Colors.redAccent : Colors.greenAccent,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              participant.username,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: stateColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              stateLabel,
              style: TextStyle(
                color: stateColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _peerStateLabel(RTCPeerConnectionState state) {
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return "connected";
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        return "connecting";
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        return "disconnected";
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        return "failed";
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        return "closed";
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
        return "new";
      default:
        return "unknown";
    }
  }

  static Color _peerStateColor(RTCPeerConnectionState? state) {
    if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      return Colors.greenAccent;
    }
    if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnecting) {
      return Colors.amberAccent;
    }
    if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
        state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
        state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
      return Colors.redAccent;
    }
    return Colors.grey;
  }
}
