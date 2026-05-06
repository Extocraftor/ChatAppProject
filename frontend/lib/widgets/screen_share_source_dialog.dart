import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class ScreenShareSourceDialog extends StatefulWidget {
  const ScreenShareSourceDialog({super.key});

  @override
  State<ScreenShareSourceDialog> createState() =>
      _ScreenShareSourceDialogState();
}

class _ScreenShareSourceDialogState extends State<ScreenShareSourceDialog> {
  final Map<String, DesktopCapturerSource> _sources = {};
  final List<StreamSubscription<DesktopCapturerSource>> _subscriptions = [];
  DesktopCapturerSource? _selectedSource;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscriptions.add(desktopCapturer.onAdded.stream.listen((source) {
      if (!mounted) {
        return;
      }
      setState(() {
        _sources[source.id] = source;
        _selectedSource ??= source;
      });
    }));
    _subscriptions.add(desktopCapturer.onRemoved.stream.listen((source) {
      if (!mounted) {
        return;
      }
      setState(() {
        _sources.remove(source.id);
        if (_selectedSource?.id == source.id) {
          _selectedSource = _sources.values.isEmpty ? null : _sources.values.first;
        }
      });
    }));
    _subscriptions.add(desktopCapturer.onNameChanged.stream.listen((_) {
      if (mounted) {
        setState(() {});
      }
    }));
    _subscriptions.add(desktopCapturer.onThumbnailChanged.stream.listen((_) {
      if (mounted) {
        setState(() {});
      }
    }));
    unawaited(_loadSources());
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  Future<void> _loadSources() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sources = await desktopCapturer.getSources(
        types: [SourceType.Screen, SourceType.Window],
        thumbnailSize: ThumbnailSize(320, 180),
      );
      if (!mounted) {
        return;
      }

      final nextSources = <String, DesktopCapturerSource>{};
      for (final source in sources) {
        nextSources[source.id] = source;
      }

      DesktopCapturerSource? preferredSource;
      for (final source in sources) {
        if (_isScreen(source)) {
          preferredSource = source;
          break;
        }
      }
      preferredSource ??= sources.isEmpty ? null : sources.first;

      setState(() {
        _sources
          ..clear()
          ..addAll(nextSources);
        if (_selectedSource == null ||
            !_sources.containsKey(_selectedSource!.id)) {
          _selectedSource = preferredSource;
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = "Could not list screens or windows: $error";
        _loading = false;
      });
    }
  }

  bool _isScreen(DesktopCapturerSource source) => source.type == SourceType.Screen;

  List<DesktopCapturerSource> _sourcesFor(SourceType type) {
    return _sources.values.where((source) => source.type == type).toList();
  }

  void _shareSelected() {
    Navigator.of(context).pop(_selectedSource);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2F3136),
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 680,
          maxHeight: 560,
        ),
        child: DefaultTabController(
          length: 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Choose What To Share",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: "Close",
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const TabBar(
                tabs: [
                  Tab(text: "Screens"),
                  Tab(text: "Windows"),
                ],
              ),
              Expanded(
                child: _SourceDialogBody(
                  loading: _loading,
                  error: _error,
                  screenSources: _sourcesFor(SourceType.Screen),
                  windowSources: _sourcesFor(SourceType.Window),
                  selectedSource: _selectedSource,
                  onRetry: _loadSources,
                  onSelected: (source) {
                    setState(() {
                      _selectedSource = source;
                    });
                  },
                  onConfirmed: _shareSelected,
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFF202225))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text("Cancel"),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _selectedSource == null ? null : _shareSelected,
                      icon: const Icon(Icons.screen_share, size: 18),
                      label: const Text("Share"),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceDialogBody extends StatelessWidget {
  const _SourceDialogBody({
    required this.loading,
    required this.error,
    required this.screenSources,
    required this.windowSources,
    required this.selectedSource,
    required this.onRetry,
    required this.onSelected,
    required this.onConfirmed,
  });

  final bool loading;
  final String? error;
  final List<DesktopCapturerSource> screenSources;
  final List<DesktopCapturerSource> windowSources;
  final DesktopCapturerSource? selectedSource;
  final VoidCallback onRetry;
  final ValueChanged<DesktopCapturerSource> onSelected;
  final VoidCallback onConfirmed;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text("Retry"),
              ),
            ],
          ),
        ),
      );
    }

    return TabBarView(
      children: [
        _SourceGrid(
          emptyLabel: "No screens found.",
          sources: screenSources,
          selectedSource: selectedSource,
          onSelected: onSelected,
          onConfirmed: onConfirmed,
        ),
        _SourceGrid(
          emptyLabel: "No windows found.",
          sources: windowSources,
          selectedSource: selectedSource,
          onSelected: onSelected,
          onConfirmed: onConfirmed,
        ),
      ],
    );
  }
}

class _SourceGrid extends StatelessWidget {
  const _SourceGrid({
    required this.emptyLabel,
    required this.sources,
    required this.selectedSource,
    required this.onSelected,
    required this.onConfirmed,
  });

  final String emptyLabel;
  final List<DesktopCapturerSource> sources;
  final DesktopCapturerSource? selectedSource;
  final ValueChanged<DesktopCapturerSource> onSelected;
  final VoidCallback onConfirmed;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) {
      return Center(
        child: Text(
          emptyLabel,
          style: const TextStyle(color: Colors.white60),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 210,
        mainAxisExtent: 154,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: sources.length,
      itemBuilder: (context, index) {
        final source = sources[index];
        return _SourceTile(
          source: source,
          selected: selectedSource?.id == source.id,
          onSelected: () => onSelected(source),
          onConfirmed: onConfirmed,
        );
      },
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.selected,
    required this.onSelected,
    required this.onConfirmed,
  });

  final DesktopCapturerSource source;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback onConfirmed;

  @override
  Widget build(BuildContext context) {
    final thumbnail = source.thumbnail;

    return Material(
      color: selected ? const Color(0xFF3B485F) : const Color(0xFF202225),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onSelected,
        onDoubleTap: onConfirmed,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? Colors.lightBlueAccent : const Color(0xFF4F545C),
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _SourcePreview(
                    thumbnail: thumbnail,
                    type: source.type,
                  ),
                ),
              ),
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.centerLeft,
                color: Colors.black.withOpacity(0.18),
                child: Text(
                  source.name,
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
    );
  }
}

class _SourcePreview extends StatelessWidget {
  const _SourcePreview({
    required this.thumbnail,
    required this.type,
  });

  final Uint8List? thumbnail;
  final SourceType type;

  @override
  Widget build(BuildContext context) {
    if (thumbnail != null && thumbnail!.isNotEmpty) {
      return Image.memory(
        thumbnail!,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Icon(
          type == SourceType.Screen ? Icons.monitor : Icons.web_asset,
          color: Colors.white54,
          size: 34,
        ),
      ),
    );
  }
}
