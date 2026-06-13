import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as media_kit;
import 'package:media_kit_video/media_kit_video.dart';
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

  String _mentionTokenWithoutTrailingPunctuation(String token) {
    const trailingChars = '.,!?;:)]}';
    var end = token.length;
    while (end > 0 && trailingChars.contains(token[end - 1])) {
      end -= 1;
    }
    return token.substring(0, end);
  }

  bool _isMentionBoundary(String character) {
    return !RegExp(r'[A-Za-z0-9_]').hasMatch(character);
  }

  TextSpan _buildMessageContentSpan(
    Message message,
    Set<String> knownUsernames,
  ) {
    const defaultStyle = TextStyle(color: Color(0xFFDCDDDE));
    final content = message.content;
    if (content.isEmpty) {
      return const TextSpan(text: '', style: defaultStyle);
    }

    final mentionPattern = RegExp(r'@([A-Za-z0-9_.-]+)');
    final mentionNames = message.mentionedUsernames
        .map((name) => name.toLowerCase())
        .toSet();
    if (mentionNames.isEmpty) {
      mentionNames.addAll(knownUsernames);
    }
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in mentionPattern.allMatches(content)) {
      if (match.start > 0 && !_isMentionBoundary(content[match.start - 1])) {
        continue;
      }

      if (match.start > cursor) {
        spans.add(
          TextSpan(
            text: content.substring(cursor, match.start),
            style: defaultStyle,
          ),
        );
      }

      final rawMentionToken = match.group(1) ?? '';
      final mentionToken = _mentionTokenWithoutTrailingPunctuation(
        rawMentionToken,
      );
      final mentionTextEnd = match.start + 1 + mentionToken.length;
      final isMention =
          mentionToken.isNotEmpty && mentionNames.contains(mentionToken.toLowerCase());

      if (isMention) {
        spans.add(
          TextSpan(
            text: content.substring(match.start, mentionTextEnd),
            style: const TextStyle(
              color: Colors.lightBlueAccent,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
        if (mentionTextEnd < match.end) {
          spans.add(
            TextSpan(
              text: content.substring(mentionTextEnd, match.end),
              style: defaultStyle,
            ),
          );
        }
      } else {
        spans.add(
          TextSpan(
            text: content.substring(match.start, match.end),
            style: defaultStyle,
          ),
        );
      }
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

  bool _isVideoAttachment(Message message) {
    final contentType = (message.attachmentContentType ?? '').toLowerCase();
    if (contentType.startsWith('video/')) {
      return true;
    }

    final name = (message.attachmentName ?? '').toLowerCase();
    return name.endsWith('.mp4') ||
        name.endsWith('.m4v') ||
        name.endsWith('.mov') ||
        name.endsWith('.webm') ||
        name.endsWith('.mkv') ||
        name.endsWith('.avi') ||
        name.endsWith('.wmv') ||
        name.endsWith('.mpeg') ||
        name.endsWith('.mpg') ||
        name.endsWith('.3gp');
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

  void _showAttachmentPreview({
    required BuildContext context,
    required String url,
    required bool isVideo,
  }) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.86),
      builder: (dialogContext) {
        return _AttachmentPreviewDialog(
          url: url,
          title: widget.message.attachmentName ?? 'Attachment',
          isVideo: isVideo,
          onOpenExternal: () => _openAttachmentUrl(dialogContext, url),
        );
      },
    );
  }

  Widget _buildImageAttachment(BuildContext context, String attachmentUrl) {
    return _AttachmentFrame(
      maxWidth: 320,
      maxHeight: 220,
      onOpenPreview: () => _showAttachmentPreview(
        context: context,
        url: attachmentUrl,
        isVideo: false,
      ),
      child: Image.network(
        attachmentUrl,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const _AttachmentError(
          icon: Icons.broken_image,
          text: 'Unable to load image',
        ),
      ),
    );
  }

  Widget _buildVideoAttachment(BuildContext context, String attachmentUrl) {
    return _AttachmentFrame(
      maxWidth: 380,
      maxHeight: 240,
      onOpenPreview: () => _showAttachmentPreview(
        context: context,
        url: attachmentUrl,
        isVideo: true,
      ),
      child: const AspectRatio(
        aspectRatio: 16 / 9,
        child: SizedBox.expand(),
      ),
      foreground: _AttachmentVideoPlayer(
        url: attachmentUrl,
        autoplay: false,
      ),
    );
  }

  Widget _buildFileAttachment(BuildContext context, String attachmentUrl) {
    final attachmentSize = _formatAttachmentSize(widget.message.attachmentSize);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openAttachmentUrl(context, attachmentUrl),
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
                widget.message.attachmentName ?? "Attachment",
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (attachmentSize.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                attachmentSize,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final isHighlighted = context.select<AppState, bool>(
        (s) => s.highlightedMessageId == widget.message.id);
    final currentUserId =
        context.select<AppState, int?>((s) => s.currentUser?.id);
    final isAdmin = context.select<AppState, bool>((s) => s.isAdmin);
    final canModerateChannels =
        context.select<AppState, bool>((s) => s.canModerateChannels);
    final mentionableUsers =
        context.select<AppState, List<User>>((s) => s.mentionableUsers);
    final knownUsernames = mentionableUsers
        .map((user) => user.username.trim().toLowerCase())
        .where((username) => username.isNotEmpty)
        .toSet();

    final isOwnMessage = currentUserId == widget.message.userId;
    final canDeleteAnyMessage = isAdmin;
    final canDeleteMessage = isOwnMessage || canDeleteAnyMessage;
    final canPinMessage = canModerateChannels;

    final attachmentPath = widget.message.attachmentUrl;
    final attachmentUrl = (attachmentPath == null || attachmentPath.isEmpty)
        ? null
        : context.read<AppState>().resolveMediaUrl(attachmentPath);
    final hasImageAttachment =
        attachmentUrl != null && _isImageAttachment(widget.message);
    final hasVideoAttachment =
        attachmentUrl != null && _isVideoAttachment(widget.message);
    final hasTextContent = widget.message.content.trim().isNotEmpty;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: isHighlighted
            ? Colors.yellow.withOpacity(0.1)
            : (_isHovered
                ? Colors.white.withOpacity(0.05)
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
                      onTap: () => context
                          .read<AppState>()
                          .highlightMessage(widget.message.parentId!),
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
                    ClipOval(
                      child: Container(
                        width: 36,
                        height: 36,
                        color: const Color(0xFF4F545C),
                        child: widget.message.authorProfilePictureUrl != null
                            ? Image.network(
                                context.read<AppState>().resolveMediaUrl(
                                    widget.message.authorProfilePictureUrl!),
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return const Center(
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white24,
                                      ),
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(Icons.person,
                                      size: 20, color: Colors.white);
                                },
                              )
                            : const Icon(Icons.person,
                                size: 20, color: Colors.white),
                      ),
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
                              _buildMessageContentSpan(
                                widget.message,
                                knownUsernames,
                              ),
                            ),
                          if (attachmentUrl != null) ...[
                            if (hasTextContent) const SizedBox(height: 8),
                            if (hasImageAttachment)
                              _buildImageAttachment(context, attachmentUrl)
                            else if (hasVideoAttachment)
                              _buildVideoAttachment(context, attachmentUrl)
                            else
                              _buildFileAttachment(context, attachmentUrl),
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
                        onPressed: () => context
                            .read<AppState>()
                            .setReplyingTo(widget.message),
                        tooltip: "Reply",
                        constraints: const BoxConstraints(),
                      ),
                      if (isOwnMessage) ...[
                        IconButton(
                          icon: const Icon(Icons.edit,
                              size: 18, color: Colors.grey),
                          onPressed: () => context
                              .read<AppState>()
                              .setEditingMessage(widget.message),
                          tooltip: "Edit",
                          constraints: const BoxConstraints(),
                        ),
                      ],
                      if (canDeleteMessage)
                        IconButton(
                          icon: const Icon(Icons.delete,
                              size: 18, color: Colors.redAccent),
                          onPressed: () => _showDeleteDialog(
                              context, context.read<AppState>()),
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
                          onPressed: () =>
                              _togglePin(context, context.read<AppState>()),
                          tooltip: widget.message.isPinned ? "Unpin" : "Pin",
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

class _AttachmentFrame extends StatelessWidget {
  final Widget child;
  final Widget? foreground;
  final double maxWidth;
  final double maxHeight;
  final VoidCallback onOpenPreview;

  const _AttachmentFrame({
    required this.child,
    required this.maxWidth,
    required this.maxHeight,
    required this.onOpenPreview,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: const Color(0xFF202225),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            child,
            if (foreground != null) Positioned.fill(child: foreground!),
          ],
        ),
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpenPreview,
          child: content,
        ),
      ),
    );
  }
}

class _AttachmentPreviewDialog extends StatelessWidget {
  final String url;
  final String title;
  final bool isVideo;
  final VoidCallback onOpenExternal;

  const _AttachmentPreviewDialog({
    required this.url,
    required this.title,
    required this.isVideo,
    required this.onOpenExternal,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: screenSize.width * 0.92,
        height: screenSize.height * 0.9,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF111214),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2F3136)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.open_in_new),
                      tooltip: 'Open link',
                      onPressed: onOpenExternal,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFF2F3136)),
              Expanded(
                child: isVideo
                    ? _AttachmentVideoPlayer(
                        url: url,
                        autoplay: true,
                      )
                    : InteractiveViewer(
                        minScale: 0.75,
                        maxScale: 5,
                        child: Center(
                          child: Image.network(
                            url,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const _AttachmentError(
                              icon: Icons.broken_image,
                              text: 'Unable to load image',
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentVideoPlayer extends StatefulWidget {
  final String url;
  final bool autoplay;

  const _AttachmentVideoPlayer({
    required this.url,
    required this.autoplay,
  });

  @override
  State<_AttachmentVideoPlayer> createState() => _AttachmentVideoPlayerState();
}

class _AttachmentVideoPlayerState extends State<_AttachmentVideoPlayer> {
  late final media_kit.Player _player;
  late final VideoController _controller;
  StreamSubscription<String>? _errorSubscription;
  bool _opening = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player = media_kit.Player();
    _controller = VideoController(_player);
    _errorSubscription = _player.stream.error.listen((error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _opening = false;
      });
    });
    _open();
  }

  @override
  void didUpdateWidget(covariant _AttachmentVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.autoplay != widget.autoplay) {
      _open();
    }
  }

  Future<void> _open() async {
    setState(() {
      _opening = true;
      _error = null;
    });

    try {
      await _player.open(
        media_kit.Media(widget.url),
        play: widget.autoplay,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _opening = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _opening = false;
      });
    }
  }

  @override
  void dispose() {
    unawaited(_errorSubscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Video(
          controller: _controller,
          fit: BoxFit.contain,
        ),
        if (_opening && _error == null)
          const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        if (_error != null)
          _AttachmentError(
            icon: Icons.videocam_off,
            text: 'Unable to play video',
            detail: _error,
          ),
      ],
    );
  }
}

class _AttachmentError extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? detail;

  const _AttachmentError({
    required this.icon,
    required this.text,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      height: 96,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF2F3136),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.grey, size: 22),
          const SizedBox(height: 6),
          Text(
            text,
            style: const TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          if (detail != null && detail!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              detail!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
