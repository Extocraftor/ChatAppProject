class User {
  final int id;
  final String username;
  final String role;

  User({required this.id, required this.username, required this.role});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      role: json['role'] ?? "member",
    );
  }
}

class Channel {
  final int id;
  final String name;
  final String? description;
  final int? creatorUserId;

  Channel({
    required this.id,
    required this.name,
    this.description,
    this.creatorUserId,
  });

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      creatorUserId: json['creator_user_id'],
    );
  }
}

class VoiceChannel {
  final int id;
  final String name;
  final String? description;
  final int? creatorUserId;

  VoiceChannel({
    required this.id,
    required this.name,
    this.description,
    this.creatorUserId,
  });

  factory VoiceChannel.fromJson(Map<String, dynamic> json) {
    return VoiceChannel(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      creatorUserId: json['creator_user_id'],
    );
  }
}

class VoiceParticipant {
  final int userId;
  final String username;
  final bool isMuted;

  VoiceParticipant({
    required this.userId,
    required this.username,
    required this.isMuted,
  });

  VoiceParticipant copyWith({
    String? username,
    bool? isMuted,
  }) {
    return VoiceParticipant(
      userId: userId,
      username: username ?? this.username,
      isMuted: isMuted ?? this.isMuted,
    );
  }

  factory VoiceParticipant.fromJson(Map<String, dynamic> json) {
    return VoiceParticipant(
      userId: json['user_id'],
      username: json['username'] ?? "User #${json['user_id']}",
      isMuted: json['is_muted'] ?? false,
    );
  }
}

class Message {
  final int id;
  final int userId;
  final String username;
  final String content;
  final String timestamp;
  final int? parentId;
  final String? parentUsername;
  final String? parentContent;
  final bool isPinned;
  final String? pinnedAt;
  final int? pinnedByUserId;
  final String? pinnedByUsername;

  Message({
    required this.id,
    required this.userId,
    required this.username,
    required this.content,
    required this.timestamp,
    this.parentId,
    this.parentUsername,
    this.parentContent,
    this.isPinned = false,
    this.pinnedAt,
    this.pinnedByUserId,
    this.pinnedByUsername,
  });

  Message copyWith({
    String? content,
    bool? isPinned,
    String? pinnedAt,
    int? pinnedByUserId,
    String? pinnedByUsername,
  }) {
    return Message(
      id: id,
      userId: userId,
      username: username,
      content: content ?? this.content,
      timestamp: timestamp,
      parentId: parentId,
      parentUsername: parentUsername,
      parentContent: parentContent,
      isPinned: isPinned ?? this.isPinned,
      pinnedAt: pinnedAt ?? this.pinnedAt,
      pinnedByUserId: pinnedByUserId ?? this.pinnedByUserId,
      pinnedByUsername: pinnedByUsername ?? this.pinnedByUsername,
    );
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      userId: json['user_id'],
      username: json['username'] ?? "User #${json['user_id']}",
      content: json['content'],
      timestamp: json['timestamp'],
      parentId: json['parent_id'],
      parentUsername: json['parent_username'],
      parentContent: json['parent_content'],
      isPinned: json['is_pinned'] == true,
      pinnedAt: json['pinned_at'],
      pinnedByUserId: json['pinned_by_user_id'],
      pinnedByUsername: json['pinned_by_username'],
    );
  }
}

class ChannelVisibilityPermission {
  final int channelId;
  final String channelName;
  final bool canView;

  ChannelVisibilityPermission({
    required this.channelId,
    required this.channelName,
    required this.canView,
  });

  ChannelVisibilityPermission copyWith({
    bool? canView,
  }) {
    return ChannelVisibilityPermission(
      channelId: channelId,
      channelName: channelName,
      canView: canView ?? this.canView,
    );
  }

  factory ChannelVisibilityPermission.fromJson(Map<String, dynamic> json) {
    return ChannelVisibilityPermission(
      channelId: json['channel_id'],
      channelName: json['channel_name'] ?? "Unknown channel",
      canView: json['can_view'] == true,
    );
  }
}

class UserChannelPermissions {
  final int userId;
  final String username;
  final String role;
  final List<ChannelVisibilityPermission> textChannelPermissions;
  final List<ChannelVisibilityPermission> voiceChannelPermissions;

  UserChannelPermissions({
    required this.userId,
    required this.username,
    required this.role,
    required this.textChannelPermissions,
    required this.voiceChannelPermissions,
  });

  factory UserChannelPermissions.fromJson(Map<String, dynamic> json) {
    final textPermissions =
        (json['text_channel_permissions'] as List<dynamic>? ?? [])
            .whereType<Map<dynamic, dynamic>>()
            .map((item) => ChannelVisibilityPermission.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList();
    final voicePermissions =
        (json['voice_channel_permissions'] as List<dynamic>? ?? [])
            .whereType<Map<dynamic, dynamic>>()
            .map((item) => ChannelVisibilityPermission.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList();
    return UserChannelPermissions(
      userId: json['user_id'],
      username: json['username'] ?? "Unknown user",
      role: json['role'] ?? "member",
      textChannelPermissions: textPermissions,
      voiceChannelPermissions: voicePermissions,
    );
  }
}

class ChannelUserVisibility {
  final int userId;
  final String username;
  final String role;
  final bool canView;

  ChannelUserVisibility({
    required this.userId,
    required this.username,
    required this.role,
    required this.canView,
  });

  factory ChannelUserVisibility.fromJson(Map<String, dynamic> json) {
    return ChannelUserVisibility(
      userId: json['user_id'],
      username: json['username'] ?? "Unknown user",
      role: json['role'] ?? "member",
      canView: json['can_view'] == true,
    );
  }
}

class ChannelPermissions {
  final int channelId;
  final String channelName;
  final String channelType;
  final List<ChannelUserVisibility> users;

  ChannelPermissions({
    required this.channelId,
    required this.channelName,
    required this.channelType,
    required this.users,
  });

  factory ChannelPermissions.fromJson(Map<String, dynamic> json) {
    final users = (json['users'] as List<dynamic>? ?? [])
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (item) => ChannelUserVisibility.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
    return ChannelPermissions(
      channelId: json['channel_id'],
      channelName: json['channel_name'] ?? "Unknown channel",
      channelType: json['channel_type'] ?? "text",
      users: users,
    );
  }
}
