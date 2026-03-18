import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../widgets/message_input.dart';
import '../widgets/message_item.dart';
import '../widgets/sidebar.dart';

class MainLayout extends StatelessWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      body: SelectionArea(
        child: Row(
          children: [
            const Sidebar(),
            Expanded(
              child: Column(
                children: [
                  Container(
                    height: 50,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: const BoxDecoration(
                      color: Color(0xFF36393F),
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                    ),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "# ${state.activeChannel?.name ?? ''}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (state.activeVoiceChannel != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      color: const Color(0xFF2F3136),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: state.voiceParticipants.values.map((participant) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF40444B),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  participant.isMuted ? Icons.mic_off : Icons.mic,
                                  size: 14,
                                  color: participant.isMuted ? Colors.redAccent : Colors.greenAccent,
                                ),
                                const SizedBox(width: 6),
                                Text(participant.username),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
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
                  const MessageInput(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
