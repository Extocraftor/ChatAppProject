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
        backgroundColor: const Color(0xFF2F3136),
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
              SwitchListTile(
                secondary: const Icon(Icons.notifications),
                title: const Text("Notification Sounds"),
                subtitle: const Text("Play a sound when you receive a message"),
                value: true, // For now, always on
                onChanged: (value) {
                  // TODO: Implement toggle in AppState
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
