import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

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
            alignment: Alignment.centerLeft,
            child: const Text("Channels", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
