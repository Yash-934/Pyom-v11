class Project {
  final String id;
  String name;
  String path;
  DateTime createdAt;
  DateTime modifiedAt;
  List<ProjectFile> files;
  Map<String, dynamic> metadata;

  Project({
    required this.id,
    required this.name,
    required this.path,
    required this.createdAt,
    required this.modifiedAt,
    this.files = const [],
    this.metadata = const {},
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'],
      name: json['name'],
      path: json['path'],
      createdAt: DateTime.parse(json['createdAt']),
      modifiedAt: DateTime.parse(json['modifiedAt']),
      files: (json['files'] as List?)
              ?.map((f) => ProjectFile.fromJson(f))
              .toList() ??
          [],
      metadata: json['metadata'] ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt.toIso8601String(),
      'files': files.map((f) => f.toJson()).toList(),
      'metadata': metadata,
    };
  }

  Project copyWith({
    String? id,
    String? name,
    String? path,
    DateTime? createdAt,
    DateTime? modifiedAt,
    List<ProjectFile>? files,
    Map<String, dynamic>? metadata,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      files: files ?? this.files,
      metadata: metadata ?? this.metadata,
    );
  }
}

class ProjectFile {
  final String id;
  String name;
  String path;
  String content;
  DateTime modifiedAt;
  bool isOpen;
  bool isModified;

  ProjectFile({
    required this.id,
    required this.name,
    required this.path,
    this.content = '',
    required this.modifiedAt,
    this.isOpen = false,
    this.isModified = false,
  });

  factory ProjectFile.fromJson(Map<String, dynamic> json) {
    return ProjectFile(
      id: json['id'],
      name: json['name'],
      path: json['path'],
      content: json['content'] ?? '',
      modifiedAt: DateTime.parse(json['modifiedAt']),
      isOpen: json['isOpen'] ?? false,
      isModified: json['isModified'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'content': content,
      'modifiedAt': modifiedAt.toIso8601String(),
      'isOpen': isOpen,
      'isModified': isModified,
    };
  }

  ProjectFile copyWith({
    String? id,
    String? name,
    String? path,
    String? content,
    DateTime? modifiedAt,
    bool? isOpen,
    bool? isModified,
  }) {
    return ProjectFile(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      content: content ?? this.content,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      isOpen: isOpen ?? this.isOpen,
      isModified: isModified ?? this.isModified,
    );
  }

  String get extension {
    return name.contains('.') ? name.split('.').last.toLowerCase() : '';
  }

  bool get isPythonFile => extension == 'py';
  bool get isTextFile => 
    ['txt', 'md', 'json', 'yaml', 'yml', 'xml', 'csv'].contains(extension);
}
