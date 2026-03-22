import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_models.dart';
import '../providers/app_state.dart';

class AdminPermissionsScreen extends StatefulWidget {
  const AdminPermissionsScreen({super.key});

  @override
  State<AdminPermissionsScreen> createState() => _AdminPermissionsScreenState();
}

class _AdminPermissionsScreenState extends State<AdminPermissionsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().fetchAdminUsers();
    });
  }

  Future<void> _selectUser(AppState state, int userId) async {
    await state.fetchAdminPermissionsForUser(userId);
  }

  Future<void> _updateRole(
    BuildContext context,
    AppState state,
    UserChannelPermissions selected,
    String role,
  ) async {
    final success = await state.updateUserRoleAsAdmin(selected.userId, role);
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unable to update role")),
      );
      return;
    }
    await state.fetchAdminPermissionsForUser(selected.userId);
  }

  Future<void> _updateTextPermission(
    BuildContext context,
    AppState state,
    int channelId,
    bool canView,
  ) async {
    final success =
        await state.updateSelectedUserTextChannelPermission(channelId, canView);
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unable to update text channel permission")),
      );
    }
  }

  Future<void> _updateVoicePermission(
    BuildContext context,
    AppState state,
    int channelId,
    bool canView,
  ) async {
    final success =
        await state.updateSelectedUserVoiceChannelPermission(channelId, canView);
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unable to update voice channel permission")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (!state.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text("Admin Permissions")),
        body: const Center(
          child: Text("Only admins can access this page."),
        ),
      );
    }

    final selected = state.selectedUserChannelPermissions;
    final roleLocked = selected?.role.toLowerCase() == "admin";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Permissions"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => state.fetchAdminUsers(),
            tooltip: "Refresh",
          ),
        ],
      ),
      body: Row(
        children: [
          Container(
            width: 280,
            decoration: const BoxDecoration(
              border: Border(
                right: BorderSide(color: Color(0xFF202225)),
              ),
            ),
            child: Column(
              children: [
                if (state.adminUsersLoading)
                  const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: state.adminUsers.isEmpty
                      ? const Center(
                          child: Text("No users found"),
                        )
                      : ListView.builder(
                          itemCount: state.adminUsers.length,
                          itemBuilder: (context, index) {
                            final user = state.adminUsers[index];
                            final isSelected =
                                state.selectedAdminUser?.id == user.id;
                            return ListTile(
                              dense: true,
                              selected: isSelected,
                              selectedTileColor: const Color(0xFF40444B),
                              title: Text(
                                user.username,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(user.role),
                              onTap: () => _selectUser(state, user.id),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          Expanded(
            child: state.adminPermissionsLoading
                ? const Center(child: CircularProgressIndicator())
                : selected == null
                    ? Center(
                        child: Text(
                          state.adminPermissionsError ??
                              "Select a user to edit permissions.",
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selected.username,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "User ID: ${selected.userId}",
                              style: const TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              value: selected.role.toLowerCase(),
                              decoration: const InputDecoration(
                                labelText: "Role",
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: "member",
                                  child: Text("Member"),
                                ),
                                DropdownMenuItem(
                                  value: "moderator",
                                  child: Text("Moderator"),
                                ),
                                DropdownMenuItem(
                                  value: "admin",
                                  child: Text("Admin"),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }
                                _updateRole(context, state, selected, value);
                              },
                            ),
                            const SizedBox(height: 20),
                            if (roleLocked)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: Text(
                                  "Admins can always view all channels. Visibility toggles below do not restrict admins.",
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            _PermissionSection(
                              title: "Text Channels",
                              items: selected.textChannelPermissions,
                              onChanged: roleLocked
                                  ? null
                                  : (item, value) => _updateTextPermission(
                                        context,
                                        state,
                                        item.channelId,
                                        value,
                                      ),
                            ),
                            const SizedBox(height: 20),
                            _PermissionSection(
                              title: "Voice Channels",
                              items: selected.voiceChannelPermissions,
                              onChanged: roleLocked
                                  ? null
                                  : (item, value) => _updateVoicePermission(
                                        context,
                                        state,
                                        item.channelId,
                                        value,
                                      ),
                            ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _PermissionSection extends StatelessWidget {
  const _PermissionSection({
    required this.title,
    required this.items,
    required this.onChanged,
  });

  final String title;
  final List<ChannelVisibilityPermission> items;
  final void Function(ChannelVisibilityPermission item, bool canView)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Text("No channels available.")
        else
          ...items.map(
            (item) => SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(item.channelName),
              value: item.canView,
              onChanged: onChanged == null
                  ? null
                  : (value) => onChanged!(item, value),
            ),
          ),
      ],
    );
  }
}
