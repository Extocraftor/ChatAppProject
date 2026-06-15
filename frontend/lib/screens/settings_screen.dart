import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),
      body: ListView(
        children: [
          _buildSection(
            context,
            "User Settings",
            [
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text("My Profile"),
                subtitle: const Text("Change your username and profile picture"),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                },
              ),
            ],
          ),
          _buildSection(
            context,
            "App Settings",
            [
              Consumer<AppState>(
                builder: (context, state, child) {
                  return Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.notifications),
                        title: const Text("Message Notifications"),
                        subtitle: const Text("Play a sound when you receive a message"),
                        value: state.playNotificationSounds,
                        onChanged: (value) {
                          state.setPlayNotificationSounds(value);
                        },
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.record_voice_over),
                        title: const Text("Voice Join Sounds"),
                        subtitle: const Text("Play a sound when you or someone else joins a voice channel"),
                        value: state.playVoiceNotificationSounds,
                        onChanged: (value) {
                          state.setPlayVoiceNotificationSounds(value);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.mic),
                        title: const Text("Microphone"),
                        subtitle: state.audioInputDevices.isEmpty
                            ? const Text("No microphones found")
                            : DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: state.audioInputDevices.any((d) =>
                                          d.deviceId == state.selectedAudioInputDeviceId)
                                      ? state.selectedAudioInputDeviceId
                                      : null,
                                  icon: state.isAudioInputSwitching
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.keyboard_arrow_down,
                                          color: Colors.grey),
                                  items: state.audioInputDevices.map((device) {
                                    return DropdownMenuItem<String>(
                                      value: device.deviceId,
                                      child: Text(
                                        device.label.isEmpty
                                            ? "Microphone (${device.deviceId})"
                                            : device.label,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: state.isAudioInputSwitching
                                      ? null
                                      : (id) {
                                          if (id != null) {
                                            state.selectAudioInputDevice(id);
                                          }
                                        },
                                ),
                              ),
                        trailing: IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: () {
                            state.refreshAudioInputDevices();
                          },
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.palette),
                        title: const Text("Theme"),
                        subtitle: const Text("Select app appearance"),
                        trailing: DropdownButton<String>(
                          value: state.themeMode,
                          items: const [
                            DropdownMenuItem(value: 'dark', child: Text('Dark')),
                            DropdownMenuItem(value: 'light', child: Text('Light')),
                            DropdownMenuItem(value: 'midnight', child: Text('Midnight')),
                            DropdownMenuItem(value: 'ocean', child: Text('Ocean')),
                          ],
                          onChanged: (value) {
                            if (value != null) state.setThemeMode(value);
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text("Logout", style: TextStyle(color: Colors.redAccent)),
            onTap: () {
              context.read<AppState>().logout();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}
