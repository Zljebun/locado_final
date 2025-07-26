import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as user_location;  // Koristi alias za `location` paket
import 'package:locado_final/helpers/database_helper.dart';  // Importuj helper za bazu
import 'package:locado_final/models/location_model.dart';  // Importuj Location model

class GooglePickLocationScreen extends StatefulWidget {
  const GooglePickLocationScreen({Key? key}) : super(key: key);

  @override
  _GooglePickLocationScreenState createState() => _GooglePickLocationScreenState();
}

class _GooglePickLocationScreenState extends State<GooglePickLocationScreen> {
  late GoogleMapController mapController;
  LatLng _center = LatLng(48.2082, 16.3738); // Default location (Vienna)
  final TextEditingController _descriptionController = TextEditingController();
  String _selectedType = 'General';

  // Funkcija za dobijanje trenutne lokacije korisnika
  void _getCurrentLocation() async {
    user_location.Location location = user_location.Location();

    // Proveri da li je dozvoljen pristup lokaciji
    bool serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) return;
    }

    user_location.PermissionStatus permissionGranted = await location.hasPermission();
    if (permissionGranted == user_location.PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != user_location.PermissionStatus.granted) return;
    }

    // Dohvati trenutnu lokaciju korisnika
    user_location.LocationData _locationData = await location.getLocation();
    setState(() {
      // Proveri da li su latitude i longitude dostupni
      if (_locationData.latitude != null && _locationData.longitude != null) {
        _center = LatLng(_locationData.latitude!, _locationData.longitude!); // Ažuriraj centar sa trenutnom lokacijom
      }
    });

    // Pomeri kameru na trenutnu lokaciju
    mapController.animateCamera(CameraUpdate.newLatLng(_center));
  }

  // Funkcija za sačuvanje lokacije
  void _saveLocation() async {
    final location = Location(
      latitude: _center.latitude,
      longitude: _center.longitude,
      description: _descriptionController.text,
      type: _selectedType,
    );

    // Sačuvaj lokaciju u bazu
    await DatabaseHelper.instance.addLocation(location);

    // Vraćanje na početnu stranicu sa izabranom lokacijom
    Navigator.pop(context, _center); // Pošaljemo izabranu lokaciju nazad na HomeMapScreen
  }

  @override
  void initState() {
    super.initState();
    _getCurrentLocation(); // Pozivamo funkciju da dobijemo trenutnu lokaciju čim se stranica otvori
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pick a Location")),
      body: Column(
        children: [
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _center,
                zoom: 15,
              ),
              onMapCreated: (GoogleMapController controller) {
                mapController = controller;
              },
              onTap: (LatLng position) {
                setState(() {
                  _center = position; // Ažuriraj poziciju kada korisnik klikne na mapu
                });
              },
              markers: {
                Marker(
                  markerId: MarkerId('selectedLocation'),
                  position: _center,
                  infoWindow: InfoWindow(title: 'Selected Location'),
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure), // Ikona za trenutnu lokaciju
                ),
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _selectedType,
                  items: ['General', 'Pharmacy', 'Post Office', 'DM']
                      .map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(e),
                  ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedType = value;
                      });
                    }
                  },
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _saveLocation, // Sačuvaj lokaciju
                  icon: const Icon(Icons.check),
                  label: const Text("Save"),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}