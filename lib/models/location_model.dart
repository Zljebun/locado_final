class Location {
  final int? id;
  final double? latitude;
  final double? longitude;
  final String? description;
  final String? type;

  Location({
    this.id,
    this.latitude,
    this.longitude,
    this.description,
    this.type,
  });

  // Mapiranje iz baze u model
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'description': description,
      'type': type,
    };
  }

  // Mapiranje iz modela u Location objekat
  factory Location.fromMap(Map<String, dynamic> map) {
    return Location(
      id: map['id'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      description: map['description'],
      type: map['type'],
    );
  }
}