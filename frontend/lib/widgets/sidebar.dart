import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_models.dart';
import '../providers/app_state.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

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
    final isActive = state.activeVoiceChannel?.id == channel.id;
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

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
                  onAdd: () => _showCreateChannelDialog(context, state, isVoice: false),
                ),
                ...state.channels.map((channel) {
                  final isActive = state.activeChannel?.id == channel.id;
                  return ListTile(
                    dense: true,
                    leading: const Text("#", style: TextStyle(fontSize: 20, color: Colors.grey)),
                    title: Text(
                      channel.name,
                      style: TextStyle(color: isActive ? Colors.white : Colors.grey),
                    ),
                    onTap: () => state.selectChannel(channel),
                    selected: isActive,
                    selectedTileColor: const Color(0xFF40444B),
                  );
                }),
                const SizedBox(height: 10),
                _sectionHeader(
                  title: "VOICE CHANNELS",
                  icon: Icons.volume_up,
                  onAdd: () => _showCreateChannelDialog(context, state, isVoice: true),
                ),
                ...state.voiceChannels.map((channel) {
                  final isActive = state.activeVoiceChannel?.id == channel.id;
                  final participants = isActive ? state.voiceParticipants.length : 0;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isActive ? Icons.volume_up : Icons.volume_mute,
                      size: 20,
                      color: isActive ? Colors.white : Colors.grey,
                    ),
                    title: Text(
                      channel.name,
                      style: TextStyle(color: isActive ? Colors.white : Colors.grey),
                    ),
                    subtitle: isActive ? Text("$participants connected") : null,
                    trailing: isActive
                        ? const Icon(Icons.call_end, color: Colors.redAccent, size: 18)
                        : null,
                    selected: isActive,
                    selectedTileColor: const Color(0xFF40444B),
                    onTap: () => _handleVoiceChannelTap(context, state, channel),
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
                      const Icon(Icons.graphic_eq, size: 16, color: Colors.greenAccent),
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
                    ],
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
                        icon: const Icon(Icons.call_end, color: Colors.redAccent),
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
