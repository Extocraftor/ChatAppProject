import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  void _showCreateChannelDialog(BuildContext context, AppState state) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2F3136),
        title: const Text("Create Channel"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: "Channel Name",
            hintText: "e.g. general",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final success = await state.createChannel(controller.text, null);
                if (success) {
                  Navigator.pop(context);
                }
              }
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Container(
      width: 240,
      color: const Color(0xFF2F3136),
      child: Column(
        children: [
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF202225))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Channels", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                IconButton(
                  icon: const Icon(Icons.add, size: 20, color: Colors.grey),
                  onPressed: () => _showCreateChannelDialog(context, state),
                  tooltip: "Create Channel",
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: state.channels.length,
              itemBuilder: (context, index) {
                final channel = state.channels[index];
                final isActive = state.activeChannel?.id == channel.id;
                return ListTile(
                  leading: const Text("#", style: TextStyle(fontSize: 20, color: Colors.grey)),
                  title: Text(channel.name, style: TextStyle(color: isActive ? Colors.white : Colors.grey)),
                  onTap: () => state.selectChannel(channel),
                  selected: isActive,
                  selectedTileColor: const Color(0xFF40444B),
                );
              },
            ),
          ),
          // Bottom User Info
          Container(
            padding: const EdgeInsets.all(8),
            color: const Color(0xFF292B2F),
            child: Row(
              children: [
                const CircleAvatar(backgroundColor: Color(0xFF5865F2), child: Icon(Icons.person, color: Colors.white)),
                const SizedBox(width: 8),
                Text(state.currentUser!.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                const Icon(Icons.settings, color: Colors.grey),
              ],
            ),
          )
        ],
      ),
    );
  }
}
