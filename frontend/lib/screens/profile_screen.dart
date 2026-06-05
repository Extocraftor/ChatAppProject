import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _usernameController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppState>().currentUser;
    if (user != null) {
      _usernameController.text = user.username;
    }
  }

  Future<void> _pickAndUploadImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );

    if (result != null && result.files.single.bytes != null) {
      final bytes = result.files.single.bytes!;
      final filename = result.files.single.name;
      
      setState(() => _isSaving = true);
      final error = await context.read<AppState>().uploadProfilePicture(bytes, filename);
      setState(() => _isSaving = false);

      if (error != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  Future<void> _saveUsername() async {
    final newUsername = _usernameController.text.trim();
    if (newUsername.isEmpty) return;

    setState(() => _isSaving = true);
    final error = await context.read<AppState>().updateProfile(username: newUsername);
    setState(() => _isSaving = false);

    if (error != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.redAccent),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile updated"), backgroundColor: Colors.green),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.currentUser;

    if (user == null) return const Scaffold(body: Center(child: Text("Not logged in")));

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Profile"),
        backgroundColor: const Color(0xFF2F3136),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundImage: user.profilePictureUrl != null
                        ? NetworkImage(state.resolveMediaUrl(user.profilePictureUrl!))
                        : null,
                    child: user.profilePictureUrl == null
                        ? const Icon(Icons.person, size: 60)
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      backgroundColor: Colors.blueAccent,
                      radius: 20,
                      child: IconButton(
                        icon: const Icon(Icons.camera_alt, size: 20, color: Colors.white),
                        onPressed: _isSaving ? null : _pickAndUploadImage,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: "Username",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveUsername,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text("Save Changes"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
