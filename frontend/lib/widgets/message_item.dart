import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
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

  void _showDeleteDialog(BuildContext context, AppState state) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2F3136),
        title: const Text("Delete Message"),
        content: const Text(
            "Are you sure you want to delete this message? This cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () {
              state.deleteMessage(widget.message.id);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePin(BuildContext context, AppState state) async {
    final message = widget.message;
    final success = message.isPinned
        ? await state.unpinMessage(message.id)
        : await state.pinMessage(message.id);
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.isPinned
                ? "Unable to unpin message"
                : "Unable to pin message",
          ),
        ),
      );
    }
  }

  TextSpan _buildMessageContentSpan(Message message) {
    const defaultStyle = TextStyle(color: Color(0xFFDCDDDE));
    final content = message.content;
    if (content.isEmpty) {
      return const TextSpan(text: '', style: defaultStyle);
    }

    final mentionPattern = RegExp(r'@([A-Za-z0-9_.-]+)');
    final mentionNames = message.mentionedUsernames
        .map((name) => name.toLowerCase())
        .toSet();
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in mentionPattern.allMatches(content)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(
            text: content.substring(cursor, match.start),
            style: defaultStyle,
          ),
        );
      }

      final mentionToken = (match.group(1) ?? '').toLowerCase();
      final isMention = mentionNames.isEmpty || mentionNames.contains(mentionToken);
      spans.add(
        TextSpan(
          text: content.substring(match.start, match.end),
          style: isMention
              ? const TextStyle(
                  color: Colors.lightBlueAccent,
                  fontWeight: FontWeight.w700,
                )
              : defaultStyle,
        ),
      );
      cursor = match.end;
    }

    if (cursor < content.length) {
      spans.add(
        TextSpan(
          text: content.substring(cursor),
          style: defaultStyle,
        ),
      );
    }

    return TextSpan(style: defaultStyle, children: spans);
  }

  bool _isImageAttachment(Message message) {
    final contentType = (message.attachmentContentType ?? '').toLowerCase();
    if (contentType.startsWith('image/')) {
      return true;
    }

    final name = (message.attachmentName ?? '').toLowerCase();
    return name.endsWith('.png') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.gif') ||
        name.endsWith('.webp') ||
        name.endsWith('.bmp');
  }

  String _formatAttachmentSize(int? sizeBytes) {
    if (sizeBytes == null || sizeBytes <= 0) {
      return '';
    }
    if (sizeBytes < 1024) {
      return '$sizeBytes B';
    }
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _openAttachmentUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid attachment URL')),
      );
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open attachment')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isHighlighted = state.highlightedMessageId == widget.message.id;
    final isOwnMessage = state.currentUser?.id == widget.message.userId;
    final canDeleteMessage = isOwnMessage || state.canDeleteAnyMessage;
    final canPinMessage = state.canModerateChannels;
    final attachmentPath = widget.message.attachmentUrl;
    final attachmentUrl = (attachmentPath == null || attachmentPath.isEmpty)
        ? null
        : state.resolveMediaUrl(attachmentPath);
    final hasImageAttachment =
        attachmentUrl != null && _isImageAttachment(widget.message);
    final hasTextContent = widget.message.content.trim().isNotEmpty;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: isHighlighted
            ? Colors.yellow.withValues(alpha: 0.1)
            : (_isHovered
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.transparent),
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
                      onTap: () =>
                          state.highlightMessage(widget.message.parentId!),
                      child: Row(
                        children: [
                          const Icon(Icons.reply, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            widget.message.parentUsername ?? "Unknown",
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.message.parentContent ?? "",
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic),
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
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                              if (widget.message.isPinned) ...[
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.push_pin,
                                  size: 14,
                                  color: Colors.amberAccent,
                                ),
                              ],
                              const SizedBox(width: 8),
                              Text(
                                _formatTimestamp(widget.message.timestamp),
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                          if (hasTextContent)
                            SelectableText.rich(
                              _buildMessageContentSpan(widget.message),
                            ),
                          if (attachmentUrl != null) ...[
                            if (hasTextContent) const SizedBox(height: 8),
                            if (hasImageAttachment)
                              InkWell(
                                onTap: () =>
                                    _openAttachmentUrl(context, attachmentUrl),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    attachmentUrl,
                                    fit: BoxFit.cover,
                                    width: 320,
                                    height: 220,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 320,
                                      height: 80,
                                      color: const Color(0xFF2F3136),
                                      alignment: Alignment.center,
                                      child: const Text(
                                        "Unable to load image",
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            else
                              InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () =>
                                    _openAttachmentUrl(context, attachmentUrl),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2F3136),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFF202225),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.attach_file,
                                        size: 16,
                                        color: Colors.lightBlueAccent,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          widget.message.attachmentName ??
                                              "Attachment",
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (_formatAttachmentSize(
                                              widget.message.attachmentSize)
                                          .isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          _formatAttachmentSize(
                                              widget.message.attachmentSize),
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.open_in_new,
                                        size: 15,
                                        color: Colors.grey,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
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
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 4)
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.reply,
                            size: 18, color: Colors.grey),
                        onPressed: () => state.setReplyingTo(widget.message),
                        tooltip: "Reply",
                        constraints: const BoxConstraints(),
                      ),
                      if (isOwnMessage) ...[
                        IconButton(
                          icon: const Icon(Icons.edit,
                              size: 18, color: Colors.grey),
                          onPressed: () =>
                              state.setEditingMessage(widget.message),
                          tooltip: "Edit",
                          constraints: const BoxConstraints(),
                        ),
                      ],
                      if (canDeleteMessage)
                        IconButton(
                          icon: const Icon(Icons.delete,
                              size: 18, color: Colors.redAccent),
                          onPressed: () => _showDeleteDialog(context, state),
                          tooltip: "Delete",
                          constraints: const BoxConstraints(),
                        ),
                      if (canPinMessage)
                        IconButton(
                          icon: Icon(
                            widget.message.isPinned
                                ? Icons.push_pin
                                : Icons.push_pin_outlined,
                            size: 18,
                            color: widget.message.isPinned
                                ? Colors.amberAccent
                                : Colors.grey,
                          ),
                          onPressed: () => _togglePin(context, state),
                          tooltip:
                              widget.message.isPinned ? "Unpin" : "Pin",
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
