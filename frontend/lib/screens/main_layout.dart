import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models/chat_models.dart';
import '../providers/app_state.dart';
import '../widgets/message_input.dart';
import '../widgets/message_item.dart';
import '../widgets/sidebar.dart';

class MainLayout extends StatelessWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context) {
    final activeChannelName =
        context.select<AppState, String>((s) => s.activeChannel?.name ?? "");
    final activeChannelId =
        context.select<AppState, int?>((s) => s.activeChannel?.id);
    final messageCount = context.select<AppState, int>((s) => s.messages.length);

    return Scaffold(
      body: Row(
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
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "# $activeChannelName",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: "Pinned messages",
                        onPressed: activeChannelId == null
                            ? null
                            : () {
                                showDialog<void>(
                                  context: context,
                                  builder: (_) => const _PinnedMessagesDialog(),
                                );
                              },
                        icon: const Icon(Icons.push_pin_outlined),
                      ),
                      IconButton(
                        tooltip: "Search messages",
                        onPressed: activeChannelId == null
                            ? null
                            : () {
                                showDialog<void>(
                                  context: context,
                                  builder: (_) => const _MessageSearchDialog(),
                                );
                              },
                        icon: const Icon(Icons.search),
                      ),
                    ],
                  ),
                ),
                const _ScreenShareStage(),
                Expanded(
                  child: ScrollablePositionedList.builder(
                    itemScrollController:
                        context.read<AppState>().itemScrollController,
                    itemPositionsListener:
                        context.read<AppState>().itemPositionsListener,
                    padding: const EdgeInsets.all(16),
                    itemCount: messageCount,
                    itemBuilder: (context, index) {
                      final messages = context.read<AppState>().messages;
                      if (index < 0 || index >= messages.length) {
                        return const SizedBox.shrink();
                      }
                      return MessageItem(message: messages[index]);
                    },
                  ),
                ),
                const _TypingIndicator(),
                const MessageInput(),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

class _ScreenShareStage extends StatelessWidget {
  const _ScreenShareStage();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final currentUserId = state.currentUser?.id;
    final tiles = <_ScreenShareTileData>[];

    if (state.isScreenSharing &&
        state.localScreenRenderer != null &&
        currentUserId != null) {
      tiles.add(
        _ScreenShareTileData(
          userId: currentUserId,
          label: "${state.currentUser?.username ?? 'You'} (You)",
          renderer: state.localScreenRenderer,
          isLocal: true,
        ),
      );
    }

    final remoteUserIds = state.screenSharingUserIds
        .where((userId) => userId != currentUserId)
        .toList()
      ..sort((a, b) {
        final aName = state.voiceParticipants[a]?.username ?? "";
        final bName = state.voiceParticipants[b]?.username ?? "";
        return aName.toLowerCase().compareTo(bName.toLowerCase());
      });

    for (final userId in remoteUserIds) {
      final participant = state.voiceParticipants[userId];
      tiles.add(
        _ScreenShareTileData(
          userId: userId,
          label: participant?.username ?? "User #$userId",
          renderer: state.remoteScreenRenderers[userId],
          isLocal: false,
        ),
      );
    }

    if (tiles.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 280,
      color: const Color(0xFF202225),
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tileWidth = tiles.length == 1
              ? constraints.maxWidth
              : (constraints.maxWidth * 0.72)
                  .clamp(300.0, 560.0)
                  .toDouble();
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tiles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              return SizedBox(
                width: tileWidth,
                child: _ScreenShareTile(data: tiles[index]),
              );
            },
          );
        },
      ),
    );
  }
}

class _ScreenShareTileData {
  const _ScreenShareTileData({
    required this.userId,
    required this.label,
    required this.renderer,
    required this.isLocal,
  });

  final int userId;
  final String label;
  final RTCVideoRenderer? renderer;
  final bool isLocal;
}

class _ScreenShareTile extends StatelessWidget {
  const _ScreenShareTile({required this.data});

  final _ScreenShareTileData data;

  @override
  Widget build(BuildContext context) {
    final renderer = data.renderer;

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (renderer != null)
              RTCVideoView(
                renderer,
                mirror: false,
                objectFit:
                    RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
              )
            else
              const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            Positioned(
              left: 10,
              bottom: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.62),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.screen_share,
                        size: 14,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Text(
                          data.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: "Full screen",
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withOpacity(0.62),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: renderer == null
                        ? null
                        : () => _openScreenShareFullscreen(context, data),
                    icon: const Icon(Icons.fullscreen),
                  ),
                  if (data.isLocal) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: "Stop sharing",
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withOpacity(0.62),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () =>
                          context.read<AppState>().stopScreenShare(),
                      icon: const Icon(Icons.stop_screen_share),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _openScreenShareFullscreen(
  BuildContext context,
  _ScreenShareTileData data,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _ScreenShareFullscreenPage(
        userId: data.userId,
        initialLabel: data.label,
        isLocal: data.isLocal,
      ),
    ),
  );
}

class _ScreenShareFullscreenPage extends StatefulWidget {
  const _ScreenShareFullscreenPage({
    required this.userId,
    required this.initialLabel,
    required this.isLocal,
  });

  final int userId;
  final String initialLabel;
  final bool isLocal;

  @override
  State<_ScreenShareFullscreenPage> createState() =>
      _ScreenShareFullscreenPageState();
}

class _ScreenShareFullscreenPageState
    extends State<_ScreenShareFullscreenPage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final renderer =
        widget.isLocal ? state.localScreenRenderer : state.remoteScreenRenderers[widget.userId];
    final label = widget.isLocal
        ? "${state.currentUser?.username ?? 'You'} (You)"
        : state.voiceParticipants[widget.userId]?.username ??
            widget.initialLabel;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (renderer != null)
            RTCVideoView(
              renderer,
              mirror: false,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
            )
          else
            const Center(
              child: Text(
                "Screen share ended",
                style: TextStyle(color: Colors.white70),
              ),
            ),
          Positioned(
            left: 12,
            top: 12,
            right: 12,
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    tooltip: "Close",
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withOpacity(0.62),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.fullscreen_exit),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.62),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.isLocal) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: "Stop sharing",
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withOpacity(0.62),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () =>
                          context.read<AppState>().stopScreenShare(),
                      icon: const Icon(Icons.stop_screen_share),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageSearchDialog extends StatefulWidget {
  const _MessageSearchDialog();

  @override
  State<_MessageSearchDialog> createState() => _MessageSearchDialogState();
}

class _MessageSearchDialogState extends State<_MessageSearchDialog> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
  }

  void _onQueryChanged() {
    _debounceTimer?.cancel();
    final query = _controller.text.trim();
    if (query.isEmpty) {
      context.read<AppState>().clearMessageSearch();
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) {
        return;
      }
      context.read<AppState>().searchMessages(query);
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final query = _controller.text.trim();

    return AlertDialog(
      backgroundColor: const Color(0xFF2F3136),
      title: const Text("Search Messages"),
      content: SizedBox(
        width: 520,
        height: 440,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (value) => state.searchMessages(value.trim()),
              decoration: const InputDecoration(
                hintText: "Search in current channel",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Builder(
                builder: (_) {
                  if (query.isEmpty) {
                    return const Center(
                      child: Text(
                        "Type to search messages in this channel.",
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }
                  if (state.messageSearchLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (state.messageSearchError != null) {
                    return Center(
                      child: Text(
                        state.messageSearchError!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    );
                  }
                  if (state.messageSearchResults.isEmpty) {
                    return const Center(
                      child: Text(
                        "No matching messages found.",
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: state.messageSearchResults.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final message = state.messageSearchResults[index];
                      final subtitle = _searchSubtitle(message);
                      return ListTile(
                        dense: true,
                        leading: message.isPinned
                            ? const Icon(
                                Icons.push_pin,
                                color: Colors.amberAccent,
                                size: 18,
                              )
                            : const Icon(Icons.chat_bubble_outline, size: 18),
                        title: Text(
                          message.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          state.highlightMessage(message.id);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Close"),
        ),
      ],
    );
  }

  String _searchSubtitle(Message message) {
    final timestamp = _formatTimestamp(message.timestamp);
    return "${message.username}  |  $timestamp";
  }
}

class _PinnedMessagesDialog extends StatefulWidget {
  const _PinnedMessagesDialog();

  @override
  State<_PinnedMessagesDialog> createState() => _PinnedMessagesDialogState();
}

class _PinnedMessagesDialogState extends State<_PinnedMessagesDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<AppState>().fetchPinnedMessages();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return AlertDialog(
      backgroundColor: const Color(0xFF2F3136),
      title: const Text("Pinned Messages"),
      content: SizedBox(
        width: 520,
        height: 440,
        child: Builder(
          builder: (_) {
            if (state.pinnedMessagesLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.pinnedMessagesError != null) {
              return Center(
                child: Text(
                  state.pinnedMessagesError!,
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              );
            }
            if (state.pinnedMessages.isEmpty) {
              return const Center(
                child: Text(
                  "No pinned messages in this channel.",
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }

            return ListView.separated(
              itemCount: state.pinnedMessages.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final message = state.pinnedMessages[index];
                final subtitle = _pinnedSubtitle(message);
                return ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.push_pin,
                    color: Colors.amberAccent,
                    size: 18,
                  ),
                  title: Text(
                    message.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: state.canModerateChannels
                      ? IconButton(
                          tooltip: "Unpin",
                          onPressed: () async {
                            final success = await state.unpinMessage(message.id);
                            if (!success && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Unable to unpin message"),
                                ),
                              );
                            }
                          },
                          icon: const Icon(
                            Icons.push_pin,
                            color: Colors.redAccent,
                          ),
                        )
                      : null,
                  onTap: () {
                    state.highlightMessage(message.id);
                    Navigator.of(context).pop();
                  },
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => state.fetchPinnedMessages(),
          child: const Text("Refresh"),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Close"),
        ),
      ],
    );
  }

  String _pinnedSubtitle(Message message) {
    final pinnedBy = message.pinnedByUsername;
    final pinnedAt = message.pinnedAt ?? message.timestamp;
    final pinnedAtText = _formatTimestamp(pinnedAt);
    if (pinnedBy == null || pinnedBy.isEmpty) {
      return "${message.username}  |  Pinned at $pinnedAtText";
    }
    return "${message.username}  |  Pinned by $pinnedBy at $pinnedAtText";
  }
}

String _formatTimestamp(String timestampText) {
  try {
    final dateTime = DateTime.parse(timestampText).toLocal();
    return DateFormat('MM/dd/yyyy HH:mm').format(dateTime);
  } catch (_) {
    return timestampText;
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final typingUsers = state.typingUsers.values.toList();
    
    if (typingUsers.isEmpty) return const SizedBox.shrink();

    String text;
    if (typingUsers.length == 1) {
      text = "${typingUsers[0]} is typing...";
    } else if (typingUsers.length == 2) {
      text = "${typingUsers[0]} and ${typingUsers[1]} are typing...";
    } else {
      text = "Several people are typing...";
    }

    return Padding(
      padding: const EdgeInsets.only(left: 16.0, bottom: 4.0, right: 16.0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}
