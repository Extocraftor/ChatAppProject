import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../screens/settings_screen.dart';
import '../models/chat_models.dart';
import '../providers/app_state.dart';
import '../screens/admin_permissions_screen.dart';
import '../screens/voice_diagnostics_screen.dart';
import 'screen_share_source_dialog.dart';

List<Widget> _spacedActions(List<Widget> actions) {
  if (actions.length <= 1) {
    return actions;
  }

  return [
    for (var index = 0; index < actions.length; index++) ...[
      if (index > 0) const SizedBox(width: 8),
      actions[index],
    ],
  ];
}

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.select<AppState, bool>((s) => s.isAdmin);
    final canCreateChannels =
        context.select<AppState, bool>((s) => s.canCreateChannels);
    final currentUsername =
        context.select<AppState, String>((s) => s.currentUser?.username ?? "");
    final channels = context.select<AppState, List<Channel>>((s) => s.channels);
    final voiceChannels =
        context.select<AppState, List<VoiceChannel>>((s) => s.voiceChannels);
    final activeVoiceChannelId =
        context.select<AppState, int?>((s) => s.activeVoiceChannel?.id);

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
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    "Harmony",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20, color: Colors.grey),
                  onPressed: () async {
                    final state = context.read<AppState>();
                    await state.fetchChannels();
                    await state.fetchVoiceChannels();
                  },
                  tooltip: "Refresh channels",
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                if (isAdmin)
                  Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.admin_panel_settings_outlined,
                        color: Colors.amberAccent,
                      ),
                      title: const Text("Admin Permissions"),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AdminPermissionsScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                if (isAdmin)
                  const Divider(height: 1, color: Color(0xFF202225)),
                _SectionHeader(
                  title: "TEXT CHANNELS",
                  icon: Icons.tag,
                  onAdd: () => _showCreateChannelDialog(
                    context,
                    context.read<AppState>(),
                    isVoice: false,
                  ),
                  canAdd: canCreateChannels,
                ),
                ...channels.map((channel) => _TextChannelTile(channel: channel)),
                const SizedBox(height: 10),
                _SectionHeader(
                  title: "VOICE CHANNELS",
                  icon: Icons.volume_up,
                  onAdd: () => _showCreateChannelDialog(
                    context,
                    context.read<AppState>(),
                    isVoice: true,
                  ),
                  canAdd: canCreateChannels,
                ),
                ...voiceChannels.map((channel) => _VoiceChannelTile(channel: channel)),
              ],
            ),
          ),
          if (activeVoiceChannelId != null) const _VoiceStatusPanel(),
          Container(
            padding: const EdgeInsets.all(8),
            color: const Color(0xFF292B2F),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF5865F2),
                  backgroundImage: context.select<AppState, String?>(
                              (s) => s.currentUser?.profilePictureUrl) !=
                          null
                      ? NetworkImage(context.read<AppState>().resolveMediaUrl(
                          context.read<AppState>().currentUser!.profilePictureUrl!))
                      : null,
                  child: context.select<AppState, String?>(
                              (s) => s.currentUser?.profilePictureUrl) ==
                          null
                      ? const Icon(Icons.person, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    currentUsername,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings, color: Colors.grey),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateChannelDialog(
    BuildContext context,
    AppState state, {
    required bool isVoice,
  }) {
    final controller = TextEditingController();
    bool adminOnly = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2F3136),
          title: Text(isVoice ? "Create Voice Channel" : "Create Text Channel"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: "Channel Name",
                  hintText: isVoice ? "e.g. Lounge" : "e.g. general",
                ),
              ),
              if (state.isAdmin) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: adminOnly,
                  onChanged: (value) {
                    setDialogState(() {
                      adminOnly = value ?? false;
                    });
                  },
                  title: const Text("Admins only"),
                  subtitle:
                      const Text("Hide this channel from non-admin users"),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text("Cancel", style: TextStyle(color: Colors.white)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (controller.text.trim().isEmpty) {
                  return;
                }

                final success = isVoice
                    ? await state.createVoiceChannel(
                        controller.text.trim(),
                        null,
                        adminOnly: adminOnly,
                      )
                    : await state.createChannel(
                        controller.text.trim(),
                        null,
                        adminOnly: adminOnly,
                      );

                if (success && context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text("Create"),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.onAdd,
    this.canAdd = true,
  });

  final String title;
  final IconData icon;
  final VoidCallback onAdd;
  final bool canAdd;

  @override
  Widget build(BuildContext context) {
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
          if (canAdd)
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
}

class _TextChannelTile extends StatelessWidget {
  const _TextChannelTile({required this.channel});
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final isActive = context.select<AppState, bool>(
        (s) => s.activeChannel?.id == channel.id);
    final hasMention = context.select<AppState, bool>(
        (s) => s.hasChannelMention(channel.id));
    final hasActivity = context.select<AppState, bool>(
        (s) => s.hasChannelActivity(channel.id));
    final canDeleteChannel = context.select<AppState, bool>(
        (s) => s.canDeleteTextChannel(channel));
    final isAdmin = context.select<AppState, bool>((s) => s.isAdmin);
    final isMuted = context.select<AppState, bool>((s) => s.isChannelMuted(channel.id));
    final channelColor =
        isActive || hasMention || hasActivity ? Colors.white : Colors.grey;
    final symbolColor = isActive
        ? Colors.white
        : hasMention
            ? Colors.redAccent
            : hasActivity
                ? Colors.lightBlueAccent
                : Colors.grey;
    final notificationBadge = hasMention
        ? const Tooltip(
            message: "Mention",
            child: Icon(
              Icons.alternate_email,
              size: 17,
              color: Colors.redAccent,
            ),
          )
        : hasActivity
            ? const Tooltip(
                message: "Unread message",
                child: SizedBox(
                  width: 17,
                  height: 17,
                  child: Center(
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: Colors.lightBlueAccent,
                        shape: CircleBorder(),
                      ),
                      child: SizedBox(width: 8, height: 8),
                    ),
                  ),
                ),
              )
            : null;

    final trailingActions = <Widget>[
      IconButton(
        icon: Icon(
          isMuted ? Icons.notifications_off : Icons.notifications,
          size: 18,
          color: isMuted ? Colors.redAccent : Colors.grey,
        ),
        tooltip: isMuted ? "Unmute notifications" : "Mute notifications",
        onPressed: () =>
            context.read<AppState>().toggleChannelNotifications(channel.id),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
      if (notificationBadge != null) notificationBadge,
      if (isAdmin)
        IconButton(
          icon: const Icon(
            Icons.tune,
            size: 18,
            color: Colors.lightBlueAccent,
          ),
          tooltip: "Channel settings",
          onPressed: () => _showTextChannelSettingsDialog(
            context,
            context.read<AppState>(),
            channel,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      if (canDeleteChannel)
        IconButton(
          icon: const Icon(
            Icons.delete_outline,
            size: 18,
            color: Colors.redAccent,
          ),
          tooltip: "Delete channel",
          onPressed: () => _showDeleteTextChannelDialog(
            context,
            context.read<AppState>(),
            channel,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
    ];

    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        dense: true,
        leading: Text(
          "#",
          style: TextStyle(fontSize: 20, color: symbolColor),
        ),
        title: Text(
          channel.name,
          style: TextStyle(color: channelColor),
        ),
        onTap: () => context.read<AppState>().selectChannel(channel),
        selected: isActive,
        selectedTileColor: const Color(0xFF40444B),
        trailing: trailingActions.isEmpty
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: _spacedActions(trailingActions),
              ),
      ),
    );
  }

  Future<void> _showTextChannelSettingsDialog(
    BuildContext context,
    AppState state,
    Channel channel,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ChannelSettingsDialog(
        channelId: channel.id,
        channelName: channel.name,
        isVoiceChannel: false,
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

    await state.deleteChannel(channel.id);
  }
}

class _VoiceChannelTile extends StatelessWidget {
  const _VoiceChannelTile({required this.channel});
  final VoiceChannel channel;

  @override
  Widget build(BuildContext context) {
    final isActive = context.select<AppState, bool>(
        (s) => s.activeVoiceChannel?.id == channel.id);
    final canDeleteChannel = context.select<AppState, bool>(
        (s) => s.canDeleteVoiceChannel(channel));
    final isAdmin = context.select<AppState, bool>((s) => s.isAdmin);
    final isConnecting = context.select<AppState, bool>((s) => s.isVoiceConnecting);

    List<VoiceParticipant> participants = channel.participants;
    if (isActive) {
      // Use live participants if active
      participants = context.select<AppState, List<VoiceParticipant>>(
          (s) => s.voiceParticipants.values.toList());
    }

    final currentUserId =
        context.select<AppState, int?>((s) => s.currentUser?.id);
    
    // Create a copy to sort
    final sortedParticipants = List<VoiceParticipant>.from(participants);
    sortedParticipants.sort((a, b) {
      final aIsCurrent = a.userId == currentUserId;
      final bIsCurrent = b.userId == currentUserId;
      if (aIsCurrent != bIsCurrent) {
        return aIsCurrent ? -1 : 1;
      }
      if (a.isBot != b.isBot) {
        return a.isBot ? 1 : -1;
      }
      return a.username.toLowerCase().compareTo(
            b.username.toLowerCase(),
          );
    });

    Widget? trailing;
    if (isActive) {
      final activeActions = <Widget>[
        if (isAdmin)
          IconButton(
            icon: const Icon(
              Icons.tune,
              color: Colors.lightBlueAccent,
              size: 18,
            ),
            tooltip: "Channel settings",
            onPressed: () => _showVoiceChannelSettingsDialog(
              context,
              context.read<AppState>(),
              channel,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
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
              context.read<AppState>(),
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
          onPressed: () => context.read<AppState>().leaveVoiceChannel(),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ];
      trailing = SizedBox(
        width: (28.0 * activeActions.length) +
            (8.0 * (activeActions.length - 1)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: _spacedActions(activeActions),
        ),
      );
    } else if (canDeleteChannel || isAdmin) {
      final inactiveActions = <Widget>[
        if (isAdmin)
          IconButton(
            icon: const Icon(
              Icons.tune,
              color: Colors.lightBlueAccent,
              size: 18,
            ),
            tooltip: "Channel settings",
            onPressed: () => _showVoiceChannelSettingsDialog(
              context,
              context.read<AppState>(),
              channel,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
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
              context.read<AppState>(),
              channel,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
      ];
      trailing = SizedBox(
        width: (28.0 * inactiveActions.length) +
            (8.0 * (inactiveActions.length - 1)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: _spacedActions(inactiveActions),
        ),
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
            subtitle: sortedParticipants.isNotEmpty
                ? Text("${sortedParticipants.length} connected")
                : null,
            trailing: trailing,
            selected: isActive,
            selectedTileColor: const Color(0xFF40444B),
            onTap: isConnecting ? null : () => _handleVoiceChannelTap(context, channel, isActive),
          ),
        ),
        if (sortedParticipants.isNotEmpty)
          ...sortedParticipants.map((participant) => _VoiceParticipantTile(participant: participant)),
      ],
    );
  }

  Future<void> _handleVoiceChannelTap(
    BuildContext context,
    VoiceChannel channel,
    bool isActive,
  ) async {
    final state = context.read<AppState>();
    if (isActive) {
      await state.leaveVoiceChannel();
      return;
    }

    final joined = await state.joinVoiceChannel(channel);
    if (!joined && state.voiceError != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.voiceError!)),
      );
    }
  }

  Future<void> _showVoiceChannelSettingsDialog(
    BuildContext context,
    AppState state,
    VoiceChannel channel,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ChannelSettingsDialog(
        channelId: channel.id,
        channelName: channel.name,
        isVoiceChannel: true,
      ),
    );
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

    await state.deleteVoiceChannel(channel.id);
  }
}

class _VoiceParticipantTile extends StatefulWidget {
  const _VoiceParticipantTile({required this.participant});
  final VoiceParticipant participant;

  @override
  State<_VoiceParticipantTile> createState() => _VoiceParticipantTileState();
}

class _VoiceParticipantTileState extends State<_VoiceParticipantTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final volume = context.select<AppState, double>(
        (s) => s.voiceParticipantVolumeFor(widget.participant.userId));
    final sliderVolume = min(volume, 2.0);
    final isCurrentUser = context.select<AppState, bool>(
        (s) => s.currentUser?.id == widget.participant.userId);
    
    final isMusicBot = widget.participant.isBot;
    final userLabel = isMusicBot
        ? widget.participant.username
        : isCurrentUser
            ? "${widget.participant.username} (You)"
            : widget.participant.username;

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
                _isExpanded = !_isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
              child: Row(
                children: [
                  if (!isMusicBot)
                    Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.only(right: 6),
                      child: CircleAvatar(
                        radius: 10,
                        backgroundColor: const Color(0xFF5865F2),
                        backgroundImage: widget.participant.profilePictureUrl != null
                            ? NetworkImage(state.resolveMediaUrl(widget.participant.profilePictureUrl!))
                            : null,
                        child: widget.participant.profilePictureUrl == null
                            ? const Icon(Icons.person, size: 12, color: Colors.white)
                            : null,
                      ),
                    ),
                  Icon(
                    isMusicBot
                        ? Icons.music_note
                        : widget.participant.isMuted
                            ? Icons.mic_off
                            : Icons.mic,
                    size: 14,
                    color: isMusicBot
                        ? Colors.lightBlueAccent
                        : widget.participant.isMuted
                            ? Colors.redAccent
                            : Colors.greenAccent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      userLabel,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white70),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.participant.isScreenSharing) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.screen_share,
                      size: 14,
                      color: Colors.lightBlueAccent,
                    ),
                  ],
                  if (_isExpanded) ...[
                    SizedBox(
                      width: widget.participant.isScreenSharing ? 8 : 4,
                    ),
                    Text(
                      "${min(500, (volume * 100).round())}%",
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                  const SizedBox(width: 6),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.tune,
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
                    onChanged: (next) => state.setVoiceParticipantVolume(
                        widget.participant.userId, next),
                  ),
                ),
              ),
              crossFadeState: _isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 150),
            ),
          ),
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: TextFormField(
                key: ValueKey(volume),
                initialValue: "${(volume * 100).round()}",
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  suffixText: "%",
                  filled: true,
                  fillColor: Color(0xFF2F3136),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                    borderSide: BorderSide.none,
                  ),
                ),
                onFieldSubmitted: (text) {
                  final parsed = double.tryParse(text);
                  if (parsed != null) {
                    state.setVoiceParticipantVolume(
                        widget.participant.userId, (parsed / 100).clamp(0.0, 5.0));
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _VoiceStatusPanel extends StatelessWidget {
  const _VoiceStatusPanel();

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

  Color _micLevelColor(
      bool hasTrack, bool isEnabled, bool isMuted, double micLevel) {
    if (!hasTrack || !isEnabled) {
      return Colors.grey;
    }
    if (isMuted) {
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

  Future<void> _handleScreenSharePressed(
    BuildContext context,
    bool isScreenSharing,
  ) async {
    final state = context.read<AppState>();
    if (isScreenSharing) {
      await state.stopScreenShare();
      return;
    }

    DesktopCapturerSource? source;
    if (WebRTC.platformIsDesktop) {
      source = await showDialog<DesktopCapturerSource>(
        context: context,
        builder: (_) => const ScreenShareSourceDialog(),
      );
      if (!context.mounted || source == null) {
        return;
      }
    }

    final success = await context.read<AppState>().startScreenShare(
          source: source,
        );
    if (!success && context.mounted) {
      final error = context.read<AppState>().screenShareError;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final channelName = context
        .select<AppState, String>((s) => s.activeVoiceChannel?.name ?? "");
    final pingMs = context.select<AppState, int?>((s) => s.voicePingMs);
    final signalStatus =
        context.select<AppState, String>((s) => s.voiceSignalStatusLabel);
    final micLevel = context.select<AppState, double>((s) => s.voiceMicLevel);
    final isSelfMuted = context.select<AppState, bool>((s) => s.isSelfMuted);
    final hasTrack =
        context.select<AppState, bool>((s) => s.hasLocalAudioTrack);
    final isTrackEnabled =
        context.select<AppState, bool>((s) => s.isLocalMicTrackEnabled);
    final isScreenSharing =
        context.select<AppState, bool>((s) => s.isScreenSharing);
    final isScreenShareStarting =
        context.select<AppState, bool>((s) => s.isScreenShareStarting);
    final screenShareError =
        context.select<AppState, String?>((s) => s.screenShareError);

    return Container(
      color: const Color(0xFF202225),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.graphic_eq, size: 16, color: Colors.greenAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "Connected: $channelName",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _pingColor(pingMs).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _pingText(pingMs),
                  style: TextStyle(
                    color: _pingColor(pingMs),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "Signal: $signalStatus",
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          ExcludeSemantics(
            child: _AnimatedMicInputLevel(
              targetLevel: micLevel.clamp(0.0, 1.0).toDouble(),
              color: _micLevelColor(
                  hasTrack, isTrackEnabled, isSelfMuted, micLevel),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.toggleMute,
                  icon: Icon(
                    isSelfMuted ? Icons.mic_off : Icons.mic,
                    size: 16,
                  ),
                  label: Text(isSelfMuted ? "Unmute" : "Mute"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF4F545C)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _VoicePanelIconAction(
                tooltip:
                    isScreenSharing ? "Stop screen share" : "Share screen",
                onPressed: isScreenShareStarting
                    ? null
                    : () => _handleScreenSharePressed(
                          context,
                          isScreenSharing,
                        ),
                foregroundColor:
                    isScreenSharing ? Colors.redAccent : Colors.white,
                child: isScreenShareStarting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white54),
                        ),
                      )
                    : Icon(
                        isScreenSharing
                            ? Icons.stop_screen_share
                            : Icons.screen_share,
                        size: 18,
                      ),
              ),
              const SizedBox(width: 6),
              _VoicePanelIconAction(
                tooltip: "Voice diagnostics",
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const VoiceDiagnosticsScreen(),
                    ),
                  );
                },
                foregroundColor: Colors.lightBlueAccent,
                child: const Icon(Icons.analytics_outlined, size: 18),
              ),
              const SizedBox(width: 6),
              _VoicePanelIconAction(
                tooltip: "Leave voice channel",
                onPressed: () => state.leaveVoiceChannel(),
                foregroundColor: Colors.redAccent,
                child: const Icon(Icons.call_end, size: 18),
              ),
            ],
          ),
          if (screenShareError != null) ...[
            const SizedBox(height: 6),
            Text(
              screenShareError,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.redAccent),
            ),
          ],
        ],
      ),
    );
  }
}

class _VoicePanelIconAction extends StatelessWidget {
  const _VoicePanelIconAction({
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.foregroundColor = Colors.white,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Tooltip(
        message: tooltip,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(36),
            foregroundColor: foregroundColor,
            disabledForegroundColor: Colors.white38,
            side: const BorderSide(color: Color(0xFF4F545C)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ChannelSettingsDialog extends StatefulWidget {
  const _ChannelSettingsDialog({
    required this.channelId,
    required this.channelName,
    required this.isVoiceChannel,
  });

  final int channelId;
  final String channelName;
  final bool isVoiceChannel;

  @override
  State<_ChannelSettingsDialog> createState() => _ChannelSettingsDialogState();
}

class _ChannelSettingsDialogState extends State<_ChannelSettingsDialog> {
  ChannelPermissions? _permissions;
  bool _isLoading = true;
  String? _error;
  final Set<int> _updatingUserIds = <int>{};

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final state = context.read<AppState>();
    final permissions = widget.isVoiceChannel
        ? await state.fetchVoiceChannelPermissionsAsAdmin(widget.channelId)
        : await state.fetchTextChannelPermissionsAsAdmin(widget.channelId);

    if (!mounted) {
      return;
    }

    setState(() {
      _permissions = permissions;
      _isLoading = false;
      if (permissions == null) {
        _error = "Unable to load channel settings.";
      }
    });
  }

  Future<void> _updateUserVisibility(
    ChannelUserVisibility user,
    bool canView,
  ) async {
    if (_updatingUserIds.contains(user.userId)) {
      return;
    }

    setState(() {
      _updatingUserIds.add(user.userId);
      _error = null;
    });

    final state = context.read<AppState>();
    final permissions = widget.isVoiceChannel
        ? await state.updateVoiceChannelUserVisibilityAsAdmin(
            channelId: widget.channelId,
            targetUserId: user.userId,
            canView: canView,
          )
        : await state.updateTextChannelUserVisibilityAsAdmin(
            channelId: widget.channelId,
            targetUserId: user.userId,
            canView: canView,
          );

    if (!mounted) {
      return;
    }

    setState(() {
      _updatingUserIds.remove(user.userId);
      if (permissions != null) {
        _permissions = permissions;
      } else {
        _error = "Unable to update channel settings.";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final users = _permissions?.users ?? const <ChannelUserVisibility>[];
    final channelPrefix = widget.isVoiceChannel ? "" : "#";

    return AlertDialog(
      backgroundColor: const Color(0xFF2F3136),
      title: Text("Settings: $channelPrefix${widget.channelName}"),
      content: SizedBox(
        width: 420,
        height: 420,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _permissions == null
                ? Center(
                    child: Text(_error ?? "Unable to load channel settings."),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Control which users can view this channel. Admins are always allowed.",
                        style: TextStyle(color: Colors.grey),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Expanded(
                        child: users.isEmpty
                            ? const Center(child: Text("No users found."))
                            : ListView.separated(
                                itemCount: users.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final user = users[index];
                                  final role = user.role.toLowerCase();
                                  final isAdminUser = role == "admin";
                                  final isUpdating =
                                      _updatingUserIds.contains(user.userId);
                                  return SwitchListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      user.username,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      isAdminUser
                                          ? "${user.role} (always visible)"
                                          : user.role,
                                    ),
                                    value: isAdminUser ? true : user.canView,
                                    onChanged: (isAdminUser || isUpdating)
                                        ? null
                                        : (value) =>
                                            _updateUserVisibility(user, value),
                                    secondary: isUpdating
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : null,
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : _loadPermissions,
          child: const Text("Refresh"),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Close"),
        ),
      ],
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
