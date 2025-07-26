// models/calendar_event.dart

import 'dart:convert';

class CalendarEvent {
  final int? id;
  final String title;
  final String? description;
  final DateTime dateTime;
  final List<int> reminderMinutes; // Minutes before event (e.g., [5, 15, 60])
  final String colorHex;
  final int? linkedTaskLocationId; // Optional link to TaskLocation
  final bool isCompleted;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  CalendarEvent({
    this.id,
    required this.title,
    this.description,
    required this.dateTime,
    required this.reminderMinutes,
    required this.colorHex,
    this.linkedTaskLocationId,
    this.isCompleted = false,
    this.completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'dateTime': dateTime.millisecondsSinceEpoch,
      'reminderMinutes': jsonEncode(reminderMinutes),
      'colorHex': colorHex,
      'linkedTaskLocationId': linkedTaskLocationId,
      'isCompleted': isCompleted ? 1 : 0,
      'completedAt': completedAt?.millisecondsSinceEpoch,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory CalendarEvent.fromMap(Map<String, dynamic> map) {
    return CalendarEvent(
      id: map['id'],
      title: map['title'] ?? 'Untitled Event',
      description: map['description'],
      dateTime: DateTime.fromMillisecondsSinceEpoch(map['dateTime'] ?? 0),
      reminderMinutes: map['reminderMinutes'] != null
          ? (map['reminderMinutes'] is String
          ? List<int>.from(jsonDecode(map['reminderMinutes']))
          : List<int>.from(map['reminderMinutes']))
          : <int>[15], // Default: 15 minutes before
      colorHex: map['colorHex'] ?? '#2196F3',
      linkedTaskLocationId: map['linkedTaskLocationId'],
      isCompleted: (map['isCompleted'] ?? 0) == 1,
      completedAt: map['completedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['completedAt'])
          : null,
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'])
          : DateTime.now(),
    );
  }

  // Helper methods
  bool get isPast => dateTime.isBefore(DateTime.now());
  bool get isToday {
    final now = DateTime.now();
    return dateTime.year == now.year &&
        dateTime.month == now.month &&
        dateTime.day == now.day;
  }

  bool get isTomorrow {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return dateTime.year == tomorrow.year &&
        dateTime.month == tomorrow.month &&
        dateTime.day == tomorrow.day;
  }

  Duration get timeUntilEvent => dateTime.difference(DateTime.now());

  bool get hasLinkedTask => linkedTaskLocationId != null;

  // Copy with method for updates
  CalendarEvent copyWith({
    int? id,
    String? title,
    String? description,
    DateTime? dateTime,
    List<int>? reminderMinutes,
    String? colorHex,
    int? linkedTaskLocationId,
    bool? isCompleted,
    DateTime? completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      dateTime: dateTime ?? this.dateTime,
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      colorHex: colorHex ?? this.colorHex,
      linkedTaskLocationId: linkedTaskLocationId ?? this.linkedTaskLocationId,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'CalendarEvent(id: $id, title: $title, dateTime: $dateTime, isCompleted: $isCompleted)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CalendarEvent && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}