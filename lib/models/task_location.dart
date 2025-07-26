// models/task_location.dart - KOMPLETAN AŽURIRANI MODEL

class TaskLocation {
  int? id;
  double latitude;
  double longitude;
  String title;
  List<String> taskItems;
  String colorHex;

  // 🆕 NOVA POLJA ZA CALENDAR INTEGRATION
  DateTime? scheduledDateTime;    // Optional datum/vreme kada treba uraditi task
  int? linkedCalendarEventId;     // Link na povezani calendar event

  TaskLocation({
    this.id,
    required this.latitude,
    required this.longitude,
    required this.title,
    required this.taskItems,
    required this.colorHex,
    this.scheduledDateTime,        // 🆕 NOVO
    this.linkedCalendarEventId,    // 🆕 NOVO
  });

  // 🆕 HELPER PROPERTIES
  bool get hasScheduledTime => scheduledDateTime != null;
  bool get hasLinkedCalendarEvent => linkedCalendarEventId != null;

  // Helper za formatiranje scheduled time
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

  // Helper za proveru da li je task scheduled za danas
  bool get isScheduledToday {
    if (scheduledDateTime == null) return false;
    final now = DateTime.now();
    final scheduled = scheduledDateTime!;
    return now.year == scheduled.year &&
        now.month == scheduled.month &&
        now.day == scheduled.day;
  }

  // Helper za proveru da li je task scheduled u budućnosti
  bool get isScheduledFuture {
    if (scheduledDateTime == null) return false;
    return scheduledDateTime!.isAfter(DateTime.now());
  }

  // Helper za proveru da li je task zakašnjeo
  bool get isOverdue {
    if (scheduledDateTime == null) return false;
    return scheduledDateTime!.isBefore(DateTime.now());
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'title': title,
      'taskItems': taskItems.join('\n'),
      'colorHex': colorHex,
      'scheduledDateTime': scheduledDateTime?.toIso8601String(),  // 🆕 NOVO
      'linkedCalendarEventId': linkedCalendarEventId,             // 🆕 NOVO
    };
  }

  factory TaskLocation.fromMap(Map<String, dynamic> map) {
    return TaskLocation(
      id: map['id'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      title: map['title'],
      taskItems: map['taskItems'].toString().split('\n').where((item) => item.trim().isNotEmpty).toList(),
      colorHex: map['colorHex'],
      scheduledDateTime: map['scheduledDateTime'] != null      // 🆕 NOVO
          ? DateTime.parse(map['scheduledDateTime'])
          : null,
      linkedCalendarEventId: map['linkedCalendarEventId'],     // 🆕 NOVO
    );
  }

  // Copy with method for updates
  TaskLocation copyWith({
    int? id,
    double? latitude,
    double? longitude,
    String? title,
    List<String>? taskItems,
    String? colorHex,
    DateTime? scheduledDateTime,              // 🆕 NOVO
    int? linkedCalendarEventId,               // 🆕 NOVO
    bool clearScheduledDateTime = false,      // 🆕 Helper za clearing
    bool clearLinkedCalendarEvent = false,   // 🆕 Helper za clearing
  }) {
    return TaskLocation(
      id: id ?? this.id,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
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
    return 'TaskLocation{id: $id, title: $title, lat: $latitude, lng: $longitude, '
        'items: ${taskItems.length}, color: $colorHex, '
        'scheduled: ${scheduledDateTime?.toString() ?? 'none'}, '
        'linkedEvent: ${linkedCalendarEventId ?? 'none'}}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is TaskLocation &&
              runtimeType == other.runtimeType &&
              id == other.id;

  @override
  int get hashCode => id.hashCode;

  // 🆕 HELPER METODA ZA KREIRANJE CALENDAR EVENT NASLOVA
  String generateCalendarEventTitle() {
    return 'Task: $title';
  }

  // 🆕 HELPER METODA ZA KREIRANJE CALENDAR EVENT OPISA
  String generateCalendarEventDescription() {
    if (taskItems.isEmpty) {
      return 'Complete task at this location';
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