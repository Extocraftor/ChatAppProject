import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../models/chat_models.dart';
import '../providers/app_state.dart';

class MessageInput extends StatefulWidget {
  const MessageInput({super.key});

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  static const int _maxAttachmentBytes = 10 * 1024 * 1024;

  final TextEditingController _controller = TextEditingController();
  final TextEditingController _emojiSearchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final FocusNode _emojiSearchFocusNode = FocusNode();
  final LayerLink _emojiPickerLayerLink = LayerLink();
  PlatformFile? _selectedAttachment;
  bool _showEmojiPicker = false;
  OverlayEntry? _emojiOverlayEntry;

  static const List<_EmojiOption> _emojiPalette = [
    _EmojiOption('\u{1F600}', ['grinning', 'happy', 'smile']),
    _EmojiOption('\u{1F603}', ['smiley', 'happy', 'smile']),
    _EmojiOption('\u{1F604}', ['smile', 'grin', 'happy']),
    _EmojiOption('\u{1F601}', ['beaming', 'happy', 'teeth']),
    _EmojiOption('\u{1F606}', ['laughing', 'happy']),
    _EmojiOption('\u{1F605}', ['sweat', 'relief']),
    _EmojiOption('\u{1F602}', ['joy', 'laugh', 'tears']),
    _EmojiOption('\u{1F923}', ['rofl', 'laugh', 'rolling']),
    _EmojiOption('\u{1F642}', ['slight', 'smile']),
    _EmojiOption('\u{1F643}', ['upside', 'silly']),
    _EmojiOption('\u{1F609}', ['wink', 'playful']),
    _EmojiOption('\u{1F60A}', ['blush', 'smile']),
    _EmojiOption('\u{1F607}', ['angel', 'halo']),
    _EmojiOption('\u{1F970}', ['hearts', 'love']),
    _EmojiOption('\u{1F60D}', ['heart', 'eyes', 'love']),
    _EmojiOption('\u{1F618}', ['kiss', 'love']),
    _EmojiOption('\u{1F60E}', ['sunglasses', 'cool']),
    _EmojiOption('\u{1F914}', ['thinking', 'hmm']),
    _EmojiOption('\u{1FAE1}', ['salute', 'respect']),
    _EmojiOption('\u{1F917}', ['hug', 'support']),
    _EmojiOption('\u{1F92D}', ['hand', 'mouth', 'gasp']),
    _EmojiOption('\u{1F62E}', ['surprised', 'wow']),
    _EmojiOption('\u{1F62F}', ['hushed', 'shock']),
    _EmojiOption('\u{1F62C}', ['grimace']),
    _EmojiOption('\u{1F644}', ['eye', 'roll']),
    _EmojiOption('\u{1F62E}\u{200D}\u{1F4A8}', ['gasp', 'exhale']),
    _EmojiOption('\u{1F62A}', ['sleepy']),
    _EmojiOption('\u{1F634}', ['sleep']),
    _EmojiOption('\u{1F60C}', ['relieved']),
    _EmojiOption('\u{1F610}', ['neutral', 'meh']),
    _EmojiOption('\u{1F611}', ['expressionless']),
    _EmojiOption('\u{1F636}', ['mouthless']),
    _EmojiOption('\u{1FAE0}', ['melting', 'awkward']),
    _EmojiOption('\u{1F972}', ['happy', 'tears']),
    _EmojiOption('\u{1F979}', ['face', 'holding', 'back']),
    _EmojiOption('\u{1F622}', ['cry', 'sad']),
    _EmojiOption('\u{1F62D}', ['sob', 'cry']),
    _EmojiOption('\u{1F614}', ['pensive', 'sad']),
    _EmojiOption('\u{1F61E}', ['disappointed']),
    _EmojiOption('\u{1F613}', ['sweat', 'nervous']),
    _EmojiOption('\u{1F612}', ['unamused']),
    _EmojiOption('\u{1F928}', ['raised', 'eyebrow']),
    _EmojiOption('\u{1F92F}', ['mind', 'blown']),
    _EmojiOption('\u{1F621}', ['angry']),
    _EmojiOption('\u{1F620}', ['mad']),
    _EmojiOption('\u{1F92C}', ['swearing', 'angry']),
    _EmojiOption('\u{1F480}', ['skull', 'dead']),
    _EmojiOption('\u{1F916}', ['robot', 'bot']),
    _EmojiOption('\u{1F47B}', ['ghost']),
    _EmojiOption('\u{1F525}', ['fire', 'lit']),
    _EmojiOption('\u{2728}', ['sparkles']),
    _EmojiOption('\u{1F31F}', ['glowing', 'star']),
    _EmojiOption('\u{2B50}', ['star']),
    _EmojiOption('\u{1F389}', ['party', 'celebration']),
    _EmojiOption('\u{1F973}', ['party', 'celebrate']),
    _EmojiOption('\u{1F44F}', ['clap', 'applause']),
    _EmojiOption('\u{1F64C}', ['raise', 'hands']),
    _EmojiOption('\u{1F64F}', ['pray', 'please', 'thanks']),
    _EmojiOption('\u{1F44D}', ['thumbs', 'up', 'like']),
    _EmojiOption('\u{1F44E}', ['thumbs', 'down', 'dislike']),
    _EmojiOption('\u{1F44C}', ['ok', 'hand']),
    _EmojiOption('\u{270C}\u{FE0F}', ['victory', 'peace']),
    _EmojiOption('\u{1F91D}', ['handshake', 'deal']),
    _EmojiOption('\u{1F4AA}', ['strong', 'muscle']),
    _EmojiOption('\u{1F3AF}', ['bullseye', 'target']),
    _EmojiOption('\u{1F4AF}', ['hundred', 'perfect']),
    _EmojiOption('\u{2705}', ['check', 'done']),
    _EmojiOption('\u{274C}', ['cross', 'x', 'wrong']),
    _EmojiOption('\u{26A1}', ['lightning', 'fast']),
    _EmojiOption('\u{1F6A8}', ['siren', 'alert']),
    _EmojiOption('\u{1F680}', ['rocket']),
    _EmojiOption('\u{1F6A7}', ['construction', 'work']),
    _EmojiOption('\u{2764}\u{FE0F}', ['heart', 'love', 'red']),
    _EmojiOption('\u{1F9E1}', ['heart', 'orange']),
    _EmojiOption('\u{1F49B}', ['heart', 'yellow']),
    _EmojiOption('\u{1F49A}', ['heart', 'green']),
    _EmojiOption('\u{1F499}', ['heart', 'blue']),
    _EmojiOption('\u{1F49C}', ['heart', 'purple']),
    _EmojiOption('\u{1F90E}', ['heart', 'brown']),
    _EmojiOption('\u{1F5A4}', ['heart', 'black']),
    _EmojiOption('\u{1F90D}', ['heart', 'white']),
    _EmojiOption('\u{1F494}', ['broken', 'heart']),
    _EmojiOption('\u{1F496}', ['sparkling', 'heart']),
    _EmojiOption('\u{1F497}', ['growing', 'heart']),
    _EmojiOption('\u{1F48C}', ['love', 'letter']),
    _EmojiOption('\u{1F4A5}', ['boom', 'impact']),
    _EmojiOption('\u{1F4A1}', ['idea', 'lightbulb']),
    _EmojiOption('\u{1F4AC}', ['speech', 'bubble']),
    _EmojiOption('\u{1F4A4}', ['zzz', 'sleep']),
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onComposerChanged);
    _emojiSearchController.addListener(_onEmojiSearchChanged);
  }

  void _onComposerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _onEmojiSearchChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    _emojiOverlayEntry?.markNeedsBuild();
  }

  List<_EmojiOption> get _filteredEmojis {
    final query = _emojiSearchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _emojiPalette;
    }
    return _emojiPalette
        .where((emoji) => emoji.matches(query))
        .toList(growable: false);
  }

  Future<void> _submit() async {
    final state = context.read<AppState>();
    final content = _controller.text;
    final hasText = content.trim().isNotEmpty;
    final editingMessage = state.editingMessage;

    if (state.attachmentUploadInProgress) {
      return;
    }

    if (editingMessage != null) {
      if (_selectedAttachment != null) {
        _showInlineError("Remove the attachment before editing this message");
        return;
      }
      if (hasText) {
        state.sendMessage(content);
        _controller.clear();
      }
      if (_showEmojiPicker) {
        _closeEmojiPicker(requestKeyboard: true);
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
      return;
    }

    final selectedAttachment = _selectedAttachment;
    if (selectedAttachment != null) {
      final Uint8List? attachmentBytes = selectedAttachment.bytes;
      if (attachmentBytes == null || attachmentBytes.isEmpty) {
        _showInlineError("Unable to read attachment data");
        return;
      }

      final uploaded = await state.sendAttachmentMessage(
        bytes: attachmentBytes,
        filename: selectedAttachment.name,
        content: content,
        parentId: state.replyingTo?.id,
      );
      if (!uploaded) {
        _showInlineError(state.attachmentUploadError ?? "Unable to upload attachment");
        return;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _selectedAttachment = null;
      });
      _controller.clear();
      state.setReplyingTo(null);
    } else if (hasText) {
      state.sendMessage(content);
      _controller.clear();
    } else {
      return;
    }

    if (_showEmojiPicker) {
      _closeEmojiPicker(requestKeyboard: true);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  Future<void> _pickAttachment() async {
    final state = context.read<AppState>();
    if (state.editingMessage != null) {
      _showInlineError("Attachments are disabled while editing a message");
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
      );
      if (!mounted || result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        _showInlineError("Unable to read selected file");
        return;
      }
      if (bytes.length > _maxAttachmentBytes) {
        _showInlineError("Attachment exceeds 10 MB limit");
        return;
      }

      setState(() {
        _selectedAttachment = file;
      });
      if (_showEmojiPicker) {
        _closeEmojiPicker(requestKeyboard: true);
      }
    } catch (_) {
      _showInlineError("Unable to pick attachment");
    }
  }

  void _showInlineError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  _MentionQuery? _activeMentionQuery() {
    final text = _controller.text;
    if (text.isEmpty) {
      return null;
    }

    final selection = _controller.selection;
    final cursor = selection.baseOffset < 0 ? text.length : selection.baseOffset;
    if (cursor > text.length) {
      return null;
    }

    final prefix = text.substring(0, cursor);
    final atIndex = prefix.lastIndexOf('@');
    if (atIndex == -1) {
      return null;
    }

    if (atIndex > 0 && !_isMentionBoundary(prefix[atIndex - 1])) {
      return null;
    }

    final query = prefix.substring(atIndex + 1);
    if (query.contains(RegExp(r'\s'))) {
      return null;
    }

    return _MentionQuery(start: atIndex, end: cursor, query: query);
  }

  bool _isMentionBoundary(String character) {
    return !RegExp(r'[A-Za-z0-9_]').hasMatch(character);
  }

  void _insertMention(String username) {
    final mentionQuery = _activeMentionQuery();
    if (mentionQuery == null) {
      return;
    }

    final text = _controller.text;
    final replacement = "@$username ";
    final updatedText = text.replaceRange(
      mentionQuery.start,
      mentionQuery.end,
      replacement,
    );
    final newCursor = mentionQuery.start + replacement.length;
    _controller.value = TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(offset: newCursor),
      composing: TextRange.empty,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  String _formatByteCount(int bytes) {
    if (bytes < 1024) {
      return "$bytes B";
    }
    if (bytes < 1024 * 1024) {
      return "${(bytes / 1024).toStringAsFixed(1)} KB";
    }
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }

  void _toggleEmojiPicker() {
    if (_showEmojiPicker) {
      _closeEmojiPicker(requestKeyboard: true);
      return;
    }

    setState(() {
      _showEmojiPicker = true;
    });
    _insertEmojiOverlay();

    _focusNode.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _emojiSearchFocusNode.requestFocus();
      }
    });
  }

  void _closeEmojiPicker({required bool requestKeyboard}) {
    if (!_showEmojiPicker && _emojiOverlayEntry == null) {
      return;
    }

    setState(() {
      _showEmojiPicker = false;
    });
    _removeEmojiOverlay();
    _emojiSearchController.clear();
    _emojiSearchFocusNode.unfocus();

    if (requestKeyboard) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  void _insertEmoji(String emoji) {
    final value = _controller.value;
    final text = value.text;
    final selection = value.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final lowerBound = start < end ? start : end;
    final upperBound = start > end ? start : end;
    final updatedText = text.replaceRange(lowerBound, upperBound, emoji);
    final newCursorPosition = lowerBound + emoji.length;

    _controller.value = TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(offset: newCursorPosition),
      composing: TextRange.empty,
    );
  }

  BorderRadius _inputBorderRadius({required bool hasContextBanner}) {
    if (hasContextBanner) {
      return const BorderRadius.vertical(bottom: Radius.circular(8));
    }
    return BorderRadius.circular(8);
  }

  int _emojiColumnCount(double availableWidth) {
    if (availableWidth < 340) {
      return 7;
    }
    if (availableWidth < 480) {
      return 8;
    }
    if (availableWidth < 720) {
      return 10;
    }
    return 12;
  }

  void _insertEmojiOverlay() {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      return;
    }

    _removeEmojiOverlay();
    _emojiOverlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final filteredEmojis = _filteredEmojis;
        final mediaSize = MediaQuery.sizeOf(overlayContext);
        final pickerHeight = (mediaSize.height * 0.45)
            .clamp(180.0, 320.0)
            .toDouble();
        final pickerWidth = (mediaSize.width * 0.5)
            .clamp(180.0, 420.0)
            .toDouble();
        final emojiColumns = _emojiColumnCount(pickerWidth);

        return Positioned.fill(
          child: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => _closeEmojiPicker(requestKeyboard: false),
                child: const SizedBox.expand(),
              ),
              CompositedTransformFollower(
                link: _emojiPickerLayerLink,
                showWhenUnlinked: false,
                targetAnchor: Alignment.topRight,
                followerAnchor: Alignment.bottomRight,
                offset: const Offset(0, -8),
                child: Material(
                  color: Colors.transparent,
                  child: SizedBox(
                    width: pickerWidth,
                    height: pickerHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2F3136),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF202225),
                          width: 1,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                            child: TextField(
                              controller: _emojiSearchController,
                              focusNode: _emojiSearchFocusNode,
                              textInputAction: TextInputAction.search,
                              style: const TextStyle(fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'Search emojis',
                                isDense: true,
                                filled: true,
                                fillColor: const Color(0xFF202225),
                                prefixIcon: const Icon(Icons.search, size: 18),
                                suffixIcon: _emojiSearchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.close, size: 18),
                                        onPressed: _emojiSearchController.clear,
                                      )
                                    : null,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(0xFF202225),
                          ),
                          Expanded(
                            child: filteredEmojis.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No emoji found',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  )
                                : GridView.builder(
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      8,
                                      8,
                                      10,
                                    ),
                                    itemCount: filteredEmojis.length,
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: emojiColumns,
                                      mainAxisSpacing: 2,
                                      crossAxisSpacing: 2,
                                    ),
                                    itemBuilder: (context, index) {
                                      final emoji = filteredEmojis[index].value;
                                      return Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(6),
                                          onTap: () => _insertEmoji(emoji),
                                          child: Center(
                                            child: Text(
                                              emoji,
                                              style: const TextStyle(fontSize: 24),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    overlay.insert(_emojiOverlayEntry!);
  }

  void _removeEmojiOverlay() {
    _emojiOverlayEntry?.remove();
    _emojiOverlayEntry = null;
  }

  @override
  void dispose() {
    _removeEmojiOverlay();
    _focusNode.dispose();
    _emojiSearchFocusNode.dispose();
    _controller.removeListener(_onComposerChanged);
    _controller.dispose();
    _emojiSearchController.removeListener(_onEmojiSearchChanged);
    _emojiSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final activeChannel = state.activeChannel;
    final replyingTo = state.replyingTo;
    final editingMessage = state.editingMessage;
    final selectedAttachment = _selectedAttachment;
    final mentionQuery = _activeMentionQuery();
    final mentionSuggestions = mentionQuery == null
        ? const <User>[]
        : state.findMentionCandidates(mentionQuery.query);
    final showMentionSuggestions = mentionSuggestions.isNotEmpty;
    final hasReplyOrEditBanner = replyingTo != null || editingMessage != null;
    final hasContextBanner = hasReplyOrEditBanner || selectedAttachment != null;

    if (editingMessage != null &&
        _controller.text != editingMessage.content &&
        _controller.text.isEmpty) {
      _controller.text = editingMessage.content;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showMentionSuggestions)
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF2F3136),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF202225)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: mentionSuggestions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final user = mentionSuggestions[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.alternate_email, size: 16),
                    title: Text(
                      user.username,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(user.role),
                    onTap: () => _insertMention(user.username),
                  );
                },
              ),
            ),
          if (hasReplyOrEditBanner)
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
                          ? 'Replying to ${replyingTo.username}'
                          : 'Editing message',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
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
          if (selectedAttachment != null)
            Container(
              margin: const EdgeInsets.only(bottom: 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF2F3136),
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.attach_file, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      selectedAttachment.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (selectedAttachment.bytes != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      _formatByteCount(selectedAttachment.bytes!.length),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                    onPressed: state.attachmentUploadInProgress
                        ? null
                        : () {
                            setState(() {
                              _selectedAttachment = null;
                            });
                          },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          CompositedTransformTarget(
            link: _emojiPickerLayerLink,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onSubmitted: (_) {
                _submit();
              },
              textInputAction: TextInputAction.send,
              autofocus: true,
              onTap: () => _closeEmojiPicker(requestKeyboard: false),
              decoration: InputDecoration(
                hintText: editingMessage != null
                    ? 'Edit message'
                    : 'Message #${activeChannel?.name ?? ''}',
                filled: true,
                fillColor: const Color(0xFF40444B),
                border: OutlineInputBorder(
                  borderRadius: _inputBorderRadius(hasContextBanner: hasContextBanner),
                  borderSide: BorderSide.none,
                ),
                suffixIconConstraints: const BoxConstraints(minWidth: 144),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Attach file',
                      icon: const Icon(Icons.attach_file),
                      onPressed: state.attachmentUploadInProgress
                          ? null
                          : () {
                              _pickAttachment();
                            },
                    ),
                    IconButton(
                      tooltip: _showEmojiPicker ? 'Use keyboard' : 'Add emoji',
                      icon: Icon(
                        _showEmojiPicker
                            ? Icons.keyboard
                            : Icons.emoji_emotions_outlined,
                      ),
                      onPressed: state.attachmentUploadInProgress
                          ? null
                          : _toggleEmojiPicker,
                    ),
                    state.attachmentUploadInProgress
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: Icon(
                              editingMessage != null ? Icons.check : Icons.send,
                            ),
                            onPressed: () {
                              _submit();
                            },
                          ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _MentionQuery {
  const _MentionQuery({
    required this.start,
    required this.end,
    required this.query,
  });

  final int start;
  final int end;
  final String query;
}

class _EmojiOption {
  const _EmojiOption(this.value, this.keywords);

  final String value;
  final List<String> keywords;

  bool matches(String query) {
    if (query.isEmpty) {
      return true;
    }
    if (value.contains(query)) {
      return true;
    }
    return keywords.any((keyword) => keyword.contains(query));
  }
}
