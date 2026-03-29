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
  final bool isBot;

  VoiceParticipant({
    required this.userId,
    required this.username,
    required this.isMuted,
    this.isBot = false,
  });

  VoiceParticipant copyWith({
    String? username,
    bool? isMuted,
    bool? isBot,
  }) {
    return VoiceParticipant(
      userId: userId,
      username: username ?? this.username,
      isMuted: isMuted ?? this.isMuted,
      isBot: isBot ?? this.isBot,
    );
  }

  factory VoiceParticipant.fromJson(Map<String, dynamic> json) {
    return VoiceParticipant(
      userId: json['user_id'],
      username: json['username'] ?? "User #${json['user_id']}",
      isMuted: json['is_muted'] ?? false,
      isBot: json['is_bot'] == true,
    );
  }
}

class Message {
  static const Object _unset = Object();

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
  final String? attachmentUrl;
  final String? attachmentName;
  final String? attachmentContentType;
  final int? attachmentSize;
  final List<int> mentionedUserIds;
  final List<String> mentionedUsernames;

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
    this.attachmentUrl,
    this.attachmentName,
    this.attachmentContentType,
    this.attachmentSize,
    List<int>? mentionedUserIds,
    List<String>? mentionedUsernames,
  })  : mentionedUserIds =
            List<int>.unmodifiable(mentionedUserIds ?? const <int>[]),
        mentionedUsernames =
            List<String>.unmodifiable(mentionedUsernames ?? const <String>[]);

  Message copyWith({
    String? content,
    bool? isPinned,
    Object? pinnedAt = _unset,
    Object? pinnedByUserId = _unset,
    Object? pinnedByUsername = _unset,
    Object? attachmentUrl = _unset,
    Object? attachmentName = _unset,
    Object? attachmentContentType = _unset,
    Object? attachmentSize = _unset,
    List<int>? mentionedUserIds,
    List<String>? mentionedUsernames,
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
      pinnedAt: identical(pinnedAt, _unset) ? this.pinnedAt : pinnedAt as String?,
      pinnedByUserId: identical(pinnedByUserId, _unset)
          ? this.pinnedByUserId
          : pinnedByUserId as int?,
      pinnedByUsername: identical(pinnedByUsername, _unset)
          ? this.pinnedByUsername
          : pinnedByUsername as String?,
      attachmentUrl: identical(attachmentUrl, _unset)
          ? this.attachmentUrl
          : attachmentUrl as String?,
      attachmentName: identical(attachmentName, _unset)
          ? this.attachmentName
          : attachmentName as String?,
      attachmentContentType: identical(attachmentContentType, _unset)
          ? this.attachmentContentType
          : attachmentContentType as String?,
      attachmentSize: identical(attachmentSize, _unset)
          ? this.attachmentSize
          : attachmentSize as int?,
      mentionedUserIds: mentionedUserIds ?? this.mentionedUserIds,
      mentionedUsernames: mentionedUsernames ?? this.mentionedUsernames,
    );
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    final mentionedUserIds = (json['mentioned_user_ids'] as List<dynamic>? ?? [])
        .map((value) {
          if (value is int) {
            return value;
          }
          if (value is String) {
            return int.tryParse(value);
          }
          return null;
        })
        .whereType<int>()
        .toList();
    final mentionedUsernames =
        (json['mentioned_usernames'] as List<dynamic>? ?? [])
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toList();

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
      attachmentUrl: json['attachment_url']?.toString(),
      attachmentName: json['attachment_name']?.toString(),
      attachmentContentType: json['attachment_content_type']?.toString(),
      attachmentSize: json['attachment_size'] is int
          ? json['attachment_size']
          : int.tryParse("${json['attachment_size'] ?? ''}"),
      mentionedUserIds: mentionedUserIds,
      mentionedUsernames: mentionedUsernames,
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
