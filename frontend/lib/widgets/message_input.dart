import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class MessageInput extends StatefulWidget {
  const MessageInput({super.key});

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final TextEditingController _controller = TextEditingController();

  void _submit() {
    if (_controller.text.isNotEmpty) {
      context.read<AppState>().sendMessage(_controller.text);
      _controller.clear();
    }
  }

  @override
  void didUpdateWidget(covariant MessageInput oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final activeChannel = state.activeChannel;
    final replyingTo = state.replyingTo;
    final editingMessage = state.editingMessage;

    // Sync controller with editing message
    if (editingMessage != null && _controller.text != editingMessage.content && _controller.text.isEmpty) {
        _controller.text = editingMessage.content;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyingTo != null || editingMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 0),
              decoration: const BoxDecoration(
                color: Color(0xFF2F3136),
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  Icon(
                    replyingTo != null ? Icons.reply : Icons.edit,
                    size: 16,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      replyingTo != null
                          ? "Replying to ${replyingTo.username}"
                          : "Editing message",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                    onPressed: () {
                      state.setReplyingTo(null);
                      state.setEditingMessage(null);
                      _controller.clear();
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          TextField(
            controller: _controller,
            onSubmitted: (_) => _submit(),
            autofocus: true,
            decoration: InputDecoration(
              hintText: editingMessage != null ? "Edit message" : "Message #${activeChannel?.name ?? ''}",
              filled: true,
              fillColor: const Color(0xFF40444B),
              border: OutlineInputBorder(
                borderRadius: (replyingTo != null || editingMessage != null)
                    ? const BorderRadius.vertical(bottom: Radius.circular(8))
                    : BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: Icon(editingMessage != null ? Icons.check : Icons.send),
                onPressed: _submit,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
