import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_models.dart';
import '../providers/app_state.dart';
import '../screens/voice_diagnostics_screen.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  int? _expandedParticipantId;

  String _pingText(int? pingMs) {
    if (pingMs == null) {
      return "-- ms";
    }
    return "$pingMs ms";
  }

  Color _pingColor(int? pingMs) {
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

  Color _micLevelColor(AppState state, double micLevel) {
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

  void _showCreateChannelDialog(
    BuildContext context,
    AppState state, {
    required bool isVoice,
  }) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2F3136),
        title: Text(isVoice ? "Create Voice Channel" : "Create Text Channel"),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: "Channel Name",
            hintText: isVoice ? "e.g. Lounge" : "e.g. general",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) {
                return;
              }

              final success = isVoice
                  ? await state.createVoiceChannel(controller.text.trim(), null)
                  : await state.createChannel(controller.text.trim(), null);

              if (success && context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  Future<void> _handleVoiceChannelTap(
    BuildContext context,
    AppState state,
    VoiceChannel channel,
  ) async {
    if (state.isVoiceConnecting) {
      return;
    }

    final isActive = state.activeVoiceChannel?.id == channel.id;
    if (isActive) {
      await state.leaveVoiceChannel();
      if (mounted) {
        setState(() {
          _expandedParticipantId = null;
        });
      }
      return;
    }

    final joined = await state.joinVoiceChannel(channel);
    if (joined && mounted) {
      setState(() {
        _expandedParticipantId = null;
      });
    }
    if (!joined && state.voiceError != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.voiceError!)),
      );
    }
  }

  Widget _sectionHeader({
    required String title,
    required IconData icon,
    required VoidCallback onAdd,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                fontSize: 12,
                letterSpacing: 0.6,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 16, color: Colors.grey),
            onPressed: onAdd,
            tooltip: "Create",
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteTextChannelDialog(
    BuildContext context,
    AppState state,
    Channel channel,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2F3136),
        title: const Text("Delete Text Channel"),
        content: Text(
          "Delete #${channel.name}? This will permanently remove all messages in this channel.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    final success = await state.deleteChannel(channel.id);
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unable to delete text channel")),
      );
    }
  }

  Future<void> _showDeleteVoiceChannelDialog(
    BuildContext context,
    AppState state,
    VoiceChannel channel,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2F3136),
        title: const Text("Delete Voice Channel"),
        content: Text(
          "Delete ${channel.name}? This disconnects everyone currently in the channel.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    final success = await state.deleteVoiceChannel(channel.id);
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unable to delete voice channel")),
      );
    }
  }

  Widget _voiceParticipantTile(
    BuildContext context,
    AppState state,
    VoiceParticipant participant,
  ) {
    final volume = state.voiceParticipantVolumeFor(participant.userId);
    final sliderVolume = min(volume, 2.0);
    final isCurrentUser = participant.userId == state.currentUser?.id;
    final userLabel = isCurrentUser
        ? "${participant.username} (You)"
        : participant.username;
    final isExpanded = _expandedParticipantId == participant.userId;

    return Container(
      margin: const EdgeInsets.fromLTRB(40, 0, 12, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF36393F),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              setState(() {
                _expandedParticipantId =
                    isExpanded ? null : participant.userId;
              });
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
              child: Row(
                children: [
                  Icon(
                    participant.isMuted ? Icons.mic_off : Icons.mic,
                    size: 14,
                    color: participant.isMuted
                        ? Colors.redAccent
                        : Colors.greenAccent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      userLabel,
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isExpanded)
                    Text(
                      "${min(500, (volume * 100).round())}%",
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  const SizedBox(width: 4),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.tune,
                    size: 14,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          ExcludeSemantics(
            child: AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                  ),
                  child: Slider(
                    value: sliderVolume,
                    min: 0,
                    max: 2,
                    divisions: 40,
                    onChanged: (next) =>
                        state.setVoiceParticipantVolume(participant.userId, next),
                  ),
                ),
              ),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 150),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: TextFormField(
                key: ValueKey(volume),
                initialValue: "${(volume * 100).round()}",
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  suffixText: "%",
                  filled: true,
                  fillColor: const Color(0xFF2F3136),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                    borderSide: BorderSide.none,
                  ),
                ),
                onFieldSubmitted: (text) {
                  final parsed = double.tryParse(text);
                  if (parsed != null) {
                    state.setVoiceParticipantVolume(
                        participant.userId, (parsed / 100).clamp(0.0, 5.0));
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final micLevel = state.voiceMicLevel.clamp(0.0, 1.0).toDouble();

    return Container(
      width: 270,
      color: const Color(0xFF2F3136),
      child: Column(
        children: [
          Container(
            height: 50,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF202225))),
            ),
            child: const Text(
              "Exto Chat",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _sectionHeader(
                  title: "TEXT CHANNELS",
                  icon: Icons.tag,
                  onAdd: () =>
                      _showCreateChannelDialog(context, state, isVoice: false),
                ),
                ...state.channels.map((channel) {
                  final isActive = state.activeChannel?.id == channel.id;
                  final canDeleteChannel = state.canDeleteTextChannel(channel);
                  return Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      dense: true,
                      leading: const Text("#",
                          style: TextStyle(fontSize: 20, color: Colors.grey)),
                      title: Text(
                        channel.name,
                        style: TextStyle(
                            color: isActive ? Colors.white : Colors.grey),
                      ),
                      onTap: () => state.selectChannel(channel),
                      selected: isActive,
                      selectedTileColor: const Color(0xFF40444B),
                      trailing: canDeleteChannel
                          ? IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: Colors.redAccent,
                              ),
                              tooltip: "Delete channel",
                              onPressed: () => _showDeleteTextChannelDialog(
                                context,
                                state,
                                channel,
                              ),
                            )
                          : null,
                    ),
                  );
                }),
                const SizedBox(height: 10),
                _sectionHeader(
                  title: "VOICE CHANNELS",
                  icon: Icons.volume_up,
                  onAdd: () =>
                      _showCreateChannelDialog(context, state, isVoice: true),
                ),
                ...state.voiceChannels.map((channel) {
                  final isActive = state.activeVoiceChannel?.id == channel.id;
                  final canDeleteChannel = state.canDeleteVoiceChannel(channel);
                  final participants =
                      isActive ? state.voiceParticipants.values.toList() : <VoiceParticipant>[];
                  if (isActive) {
                    final currentUserId = state.currentUser?.id;
                    participants.sort((a, b) {
                      final aIsCurrent = a.userId == currentUserId;
                      final bIsCurrent = b.userId == currentUserId;
                      if (aIsCurrent != bIsCurrent) {
                        return aIsCurrent ? -1 : 1;
                      }
                      return a.username.toLowerCase().compareTo(
                            b.username.toLowerCase(),
                          );
                    });
                  }

                  Widget? trailing;
                  if (isActive) {
                    trailing = SizedBox(
                      width: canDeleteChannel ? 56 : 28,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (canDeleteChannel)
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                                size: 18,
                              ),
                              tooltip: "Delete channel",
                              onPressed: () => _showDeleteVoiceChannelDialog(
                                context,
                                state,
                                channel,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          IconButton(
                            icon: const Icon(
                              Icons.call_end,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            tooltip: "Leave voice channel",
                            onPressed: () => state.leaveVoiceChannel(),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    );
                  } else if (canDeleteChannel) {
                    trailing = IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                        size: 18,
                      ),
                      tooltip: "Delete channel",
                      onPressed: () =>
                          _showDeleteVoiceChannelDialog(context, state, channel),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            isActive ? Icons.volume_up : Icons.volume_mute,
                            size: 20,
                            color: isActive ? Colors.white : Colors.grey,
                          ),
                          title: Text(
                            channel.name,
                            style: TextStyle(
                                color: isActive ? Colors.white : Colors.grey),
                          ),
                          subtitle: isActive
                              ? Text("${participants.length} connected")
                              : null,
                          trailing: trailing,
                          selected: isActive,
                          selectedTileColor: const Color(0xFF40444B),
                          onTap: () =>
                              _handleVoiceChannelTap(context, state, channel),
                        ),
                      ),
                      if (isActive && participants.isNotEmpty)
                        ...participants
                            .map((participant) =>
                                _voiceParticipantTile(context, state, participant)),
                    ],
                  );
                }),
              ],
            ),
          ),
          if (state.activeVoiceChannel != null)
            Container(
              color: const Color(0xFF202225),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.graphic_eq,
                          size: 16, color: Colors.greenAccent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "Connected: ${state.activeVoiceChannel!.name}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _pingColor(state.voicePingMs)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _pingText(state.voicePingMs),
                          style: TextStyle(
                            color: _pingColor(state.voicePingMs),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Signal: ${state.voiceSignalStatusLabel}",
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  ExcludeSemantics(
                    child: _AnimatedMicInputLevel(
                      targetLevel: micLevel,
                      color: _micLevelColor(state, micLevel),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: state.toggleMute,
                          icon: Icon(
                            state.isSelfMuted ? Icons.mic_off : Icons.mic,
                            size: 16,
                          ),
                          label: Text(state.isSelfMuted ? "Unmute" : "Mute"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF4F545C)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(
                          Icons.analytics_outlined,
                          color: Colors.lightBlueAccent,
                        ),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const VoiceDiagnosticsScreen(),
                            ),
                          );
                        },
                        tooltip: "Voice diagnostics",
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon:
                            const Icon(Icons.call_end, color: Colors.redAccent),
                        onPressed: () => state.leaveVoiceChannel(),
                        tooltip: "Leave voice channel",
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(8),
            color: const Color(0xFF292B2F),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFF5865F2),
                  child: Icon(Icons.person, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.currentUser!.username,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.settings, color: Colors.grey),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedMicInputLevel extends StatelessWidget {
  const _AnimatedMicInputLevel({
    required this.targetLevel,
    required this.color,
  });

  final double targetLevel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(end: targetLevel),
      builder: (context, animatedLevel, child) {
        final level = animatedLevel.clamp(0.0, 1.0).toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: level,
                backgroundColor: const Color(0xFF2F3136),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Mic input ${(level * 100).round()}%",
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        );
      },
    );
  }
}
