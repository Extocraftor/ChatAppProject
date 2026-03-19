import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
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
                      boxShadow: [
                        BoxShadow(color: Colors.black26, blurRadius: 4)
                      ],
                    ),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "# ${state.activeChannel?.name ?? ''}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
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
                  if (state.activeVoiceChannel != null &&
                      state.remoteAudioRenderers.isNotEmpty)
                    SizedBox(
                      width: 1,
                      height: 1,
                      child: Opacity(
                        opacity: 0,
                        child: Stack(
                          fit: StackFit.expand,
                          children: state.remoteAudioRenderers.entries
                              .map(
                                (entry) => RTCVideoView(
                                  entry.value,
                                  key: ValueKey('remote-audio-${entry.key}'),
                                  objectFit: RTCVideoViewObjectFit
                                      .RTCVideoViewObjectFitContain,
                                  mirror: false,
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
