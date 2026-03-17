import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/chat_models.dart';
import '../providers/app_state.dart';

class MessageItem extends StatefulWidget {
  final Message message;

  const MessageItem({super.key, required this.message});

  @override
  State<MessageItem> createState() => _MessageItemState();
}

class _MessageItemState extends State<MessageItem> {
  bool _isHovered = false;

  String _formatTimestamp(String timestampStr) {
    try {
      final dateTime = DateTime.parse(timestampStr).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final dateToCheck = DateTime(dateTime.year, dateTime.month, dateTime.day);

      String datePart;
      if (dateToCheck == today) {
        datePart = "Today";
      } else if (dateToCheck == yesterday) {
        datePart = "Yesterday";
      } else {
        datePart = DateFormat('MM/dd/yyyy').format(dateTime);
      }

      final timePart = DateFormat('HH:mm').format(dateTime);
      return "$datePart at $timePart";
    } catch (e) {
      return timestampStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isHighlighted = state.highlightedMessageId == widget.message.id;
    final isOwnMessage = state.currentUser?.id == widget.message.userId;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: isHighlighted ? Colors.yellow.withOpacity(0.1) : (_isHovered ? Colors.white.withOpacity(0.05) : Colors.transparent),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.message.parentId != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 36, bottom: 4),
                    child: InkWell(
                      onTap: () => state.highlightMessage(widget.message.parentId!),
                      child: Row(
                        children: [
                          const Icon(Icons.reply, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            widget.message.parentUsername ?? "Unknown",
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.message.parentContent ?? "",
                              style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(
                      radius: 18,
                      backgroundColor: Color(0xFF4F545C),
                      child: Icon(Icons.person, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                widget.message.username,
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatTimestamp(widget.message.timestamp),
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                          Text(widget.message.content, style: const TextStyle(color: Color(0xFFDCDDDE))),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (_isHovered)
              Positioned(
                right: 0,
                top: -10,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2F3136),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.reply, size: 18, color: Colors.grey),
                        onPressed: () => state.setReplyingTo(widget.message),
                        tooltip: "Reply",
                        constraints: const BoxConstraints(),
                      ),
                      if (isOwnMessage)
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18, color: Colors.grey),
                          onPressed: () => state.setEditingMessage(widget.message),
                          tooltip: "Edit",
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
