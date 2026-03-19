import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';

class InputTestScreen extends StatefulWidget {
  const InputTestScreen({super.key});

  @override
  State<InputTestScreen> createState() => _InputTestScreenState();
}

class _InputTestScreenState extends State<InputTestScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      unawaited(state.refreshAudioInputDevices());
      unawaited(state.startInputTest());
    });
  }

  @override
  void dispose() {
    final state = context.read<AppState>();
    unawaited(state.stopInputTest(notify: false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final meterLevel = state.inputTestLevel.clamp(0.0, 1.0);
    final selectedInputId = state.selectedAudioInputDeviceId;
    final hasSelectedInput = selectedInputId != null &&
        state.audioInputDevices.any((d) => d.deviceId == selectedInputId);
    final effectiveSelectedInputId = hasSelectedInput ? selectedInputId : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Microphone Input Test"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "Speak into your microphone. The level bar should move if input capture works.",
          ),
          const SizedBox(height: 12),
          if (state.isAudioInputDevicesLoading)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          DropdownButtonFormField<String>(
            value: effectiveSelectedInputId,
            decoration: const InputDecoration(
              labelText: "Input Device",
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: state.audioInputDevices.asMap().entries.map((entry) {
              final index = entry.key;
              final device = entry.value;
              return DropdownMenuItem<String>(
                value: device.deviceId,
                child: Text(
                  _audioInputLabel(device, index),
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (nextDeviceId) {
              if (nextDeviceId == null || state.isAudioInputSwitching) {
                return;
              }
              unawaited(state.selectAudioInputDevice(nextDeviceId));
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.isAudioInputDevicesLoading
                      ? null
                      : () => state.refreshAudioInputDevices(),
                  icon: const Icon(Icons.refresh),
                  label: const Text("Refresh Devices"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: state.isInputTestStarting
                      ? null
                      : () {
                          if (state.isInputTestRunning) {
                            unawaited(state.stopInputTest());
                          } else {
                            unawaited(state.startInputTest(forceRestart: true));
                          }
                        },
                  icon: Icon(
                    state.isInputTestRunning ? Icons.stop : Icons.play_arrow,
                  ),
                  label: Text(
                      state.isInputTestRunning ? "Stop Test" : "Start Test"),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF2F3136),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF202225)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Input Level",
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      "${(meterLevel * 100).round()}%",
                      style: TextStyle(
                        color: _meterColor(meterLevel),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 14,
                    value: meterLevel,
                    backgroundColor: const Color(0xFF202225),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _meterColor(meterLevel),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  state.inputTestUsesVoiceStream
                      ? "Testing active voice-call input stream."
                      : "Testing standalone microphone stream.",
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 6),
                Text(
                  "Level source: ${state.inputTestLevelSource}",
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF2F3136),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF202225)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Raw Stats",
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _statRow(
                  "Last sample",
                  _formatLastSample(state.inputTestLastSampleAt),
                ),
                _statRow(
                  "Raw audio level",
                  _formatDouble(state.inputTestRawAudioLevel),
                ),
                _statRow(
                  "Raw total energy",
                  _formatDouble(state.inputTestRawEnergy),
                ),
                _statRow(
                  "Raw total duration",
                  _formatDouble(state.inputTestRawDuration),
                ),
                _statRow(
                  "Estimated level",
                  _formatDouble(state.inputTestRawEstimatedLevel),
                ),
                _statRow(
                  "Voice activity flag",
                  state.inputTestRawVoiceActivity.toString(),
                ),
                const SizedBox(height: 8),
                if (state.inputTestRawStats.isEmpty)
                  const Text(
                    "No raw stats yet. Start the test and speak for 2-3 seconds.",
                    style: TextStyle(color: Colors.grey),
                  )
                else
                  SelectableText(
                    state.inputTestRawStats.entries
                        .map((entry) => "${entry.key}: ${entry.value}")
                        .join("\n"),
                    style: const TextStyle(
                      fontFamily: "monospace",
                      fontSize: 12,
                      color: Color(0xFFB9BBBE),
                    ),
                  ),
              ],
            ),
          ),
          if (state.inputTestError != null) ...[
            const SizedBox(height: 10),
            Text(
              state.inputTestError!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
        ],
      ),
    );
  }

  static String _audioInputLabel(MediaDeviceInfo device, int index) {
    final label = device.label.trim();
    if (label.isNotEmpty) {
      return label;
    }
    return "Microphone ${index + 1}";
  }

  static Color _meterColor(double level) {
    if (level > 0.7) {
      return Colors.greenAccent;
    }
    if (level > 0.35) {
      return Colors.lightGreenAccent;
    }
    if (level > 0.1) {
      return Colors.amberAccent;
    }
    return Colors.blueGrey;
  }

  static Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          Text(value),
        ],
      ),
    );
  }

  static String _formatDouble(double? value) {
    if (value == null) {
      return "--";
    }
    return value.toStringAsFixed(5);
  }

  static String _formatLastSample(DateTime? timestamp) {
    if (timestamp == null) {
      return "--";
    }

    final elapsedMs = DateTime.now().difference(timestamp).inMilliseconds;
    return "${elapsedMs} ms ago";
  }
}
