import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../widgets/sidebar.dart';
import '../widgets/message_item.dart';
import '../widgets/message_input.dart';

class MainLayout extends StatelessWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      body: Row(
        children: [
          // Sidebar: Channel List
          const Sidebar(),
          // Main Chat Area
          Expanded(
            child: Column(
              children: [
                // Chat Header
                Container(
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(
                    color: Color(0xFF36393F),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text("# ${state.activeChannel?.name ?? ''}", style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                // Messages List
                Expanded(
                  child: ListView.builder(
                    controller: state.scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: state.messages.length,
                    itemBuilder: (context, index) {
                      return MessageItem(message: state.messages[index]);
                    },
                  ),
                ),
                // Input Bar
                const MessageInput(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
