class User {
  final int id;
  final String username;

  User({required this.id, required this.username});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(id: json['id'], username: json['username']);
  }
}

class Channel {
  final int id;
  final String name;
  final String? description;

  Channel({required this.id, required this.name, this.description});

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(id: json['id'], name: json['name'], description: json['description']);
  }
}

class VoiceChannel {
  final int id;
  final String name;
  final String? description;

  VoiceChannel({required this.id, required this.name, this.description});

  factory VoiceChannel.fromJson(Map<String, dynamic> json) {
    return VoiceChannel(
      id: json['id'],
      name: json['name'],
      description: json['description'],
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

  Message({
    required this.id,
    required this.userId,
    required this.username,
    required this.content,
    required this.timestamp,
    this.parentId,
    this.parentUsername,
    this.parentContent,
  });

  Message copyWith({
    String? content,
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
    );
  }
}
