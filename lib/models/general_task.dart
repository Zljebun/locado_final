// models/general_task.dart - Model for tasks without location

class GeneralTask {
  int? id;
  String title;
  List<String> taskItems;
  String colorHex;

  // Calendar integration fields
  DateTime? scheduledDateTime;
  int? linkedCalendarEventId;

  GeneralTask({
    this.id,
    required this.title,
    required this.taskItems,
    required this.colorHex,
    this.scheduledDateTime,
    this.linkedCalendarEventId,
  });

  // Helper properties
  bool get hasScheduledTime => scheduledDateTime != null;
  bool get hasLinkedCalendarEvent => linkedCalendarEventId != null;

  String get formattedScheduledTime {
    if (scheduledDateTime == null) return 'Not scheduled';

    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    final date = scheduledDateTime!;
    final hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? 'AM' : 'PM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);

    return '${months[date.month]} ${date.day} at $displayHour:$minute $period';
  }

  bool get isScheduledToday {
    if (scheduledDateTime == null) return false;
    final now = DateTime.now();
    final scheduled = scheduledDateTime!;
    return now.year == scheduled.year &&
        now.month == scheduled.month &&
        now.day == scheduled.day;
  }

  bool get isScheduledFuture {
    if (scheduledDateTime == null) return false;
    return scheduledDateTime!.isAfter(DateTime.now());
  }

  bool get isOverdue {
    if (scheduledDateTime == null) return false;
    return scheduledDateTime!.isBefore(DateTime.now());
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'taskItems': taskItems.join('\n'),
      'colorHex': colorHex,
      'scheduledDateTime': scheduledDateTime?.toIso8601String(),
      'linkedCalendarEventId': linkedCalendarEventId,
    };
  }

  factory GeneralTask.fromMap(Map<String, dynamic> map) {
    return GeneralTask(
      id: map['id'],
      title: map['title'],
      taskItems: map['taskItems'].toString().split('\n').where((item) => item.trim().isNotEmpty).toList(),
      colorHex: map['colorHex'],
      scheduledDateTime: map['scheduledDateTime'] != null
          ? DateTime.parse(map['scheduledDateTime'])
          : null,
      linkedCalendarEventId: map['linkedCalendarEventId'],
    );
  }

  GeneralTask copyWith({
    int? id,
    String? title,
    List<String>? taskItems,
    String? colorHex,
    DateTime? scheduledDateTime,
    int? linkedCalendarEventId,
    bool clearScheduledDateTime = false,
    bool clearLinkedCalendarEvent = false,
  }) {
    return GeneralTask(
      id: id ?? this.id,
      title: title ?? this.title,
      taskItems: taskItems ?? this.taskItems,
      colorHex: colorHex ?? this.colorHex,
      scheduledDateTime: clearScheduledDateTime
          ? null
          : (scheduledDateTime ?? this.scheduledDateTime),
      linkedCalendarEventId: clearLinkedCalendarEvent
          ? null
          : (linkedCalendarEventId ?? this.linkedCalendarEventId),
    );
  }

  @override
  String toString() {
    return 'GeneralTask{id: $id, title: $title, items: ${taskItems.length}, '
        'color: $colorHex, scheduled: ${scheduledDateTime?.toString() ?? 'none'}}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is GeneralTask &&
              runtimeType == other.runtimeType &&
              id == other.id;

  @override
  int get hashCode => id.hashCode;

  String generateCalendarEventTitle() {
    return 'General Task: $title';
  }

  String generateCalendarEventDescription() {
    if (taskItems.isEmpty) {
      return 'Complete general task';
    }

    if (taskItems.length == 1) {
      return taskItems.first;
    }

    final preview = taskItems.take(3).join(', ');
    final remaining = taskItems.length - 3;

    return remaining > 0
        ? '$preview... (+$remaining more items)'
        : preview;
  }
}