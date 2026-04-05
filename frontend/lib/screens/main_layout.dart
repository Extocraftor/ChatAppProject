import 'dart:async';

import 'package:flutter/material.dart';
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
                const MessageInput(),
              ],
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
