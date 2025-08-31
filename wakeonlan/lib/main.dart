import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wake_on_lan/wake_on_lan.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

void main() {
  runApp(const MyApp());
}

class Device {
  final String name, ip, mac;
  final int port;
  final String subnet; // Subnetzmaske als String

  Device({
    required this.name,
    required this.ip,
    required this.mac,
    required this.port,
    required this.subnet,
  });

  Map<String, dynamic> toJson() =>
      {'name': name, 'ip': ip, 'mac': mac, 'port': port, 'subnet': subnet};

  factory Device.fromJson(Map<String, dynamic> j) => Device(
        name: j['name'],
        ip: j['ip'],
        mac: j['mac'],
        port: (j['port'] as num).toInt(),
        subnet: j['subnet'] ?? '255.255.255.0', // Standardwert falls nicht vorhanden
      );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Wake on LAN',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        theme: ThemeData(
          brightness: Brightness.light,
          useMaterial3: true,
          scaffoldBackgroundColor: const Color.fromARGB(255, 255, 255, 255),
          cardColor: Colors.white,
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          shadowColor: Colors.black.withOpacity(0.2),
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF1D1D1D),
          cardColor: const Color(0xFF2A2A2A),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: Color(0xFF3A3A3A),
            foregroundColor: Colors.white,
          ),
          shadowColor: Colors.black.withOpacity(0.5),
          colorScheme: const ColorScheme.dark(
            primary: Colors.white,
            secondary: Colors.grey,
          ),
        ),
        home: const WakeOnLanHome(),
      );
}

class WakeOnLanHome extends StatefulWidget {
  const WakeOnLanHome({super.key});
  @override
  State<WakeOnLanHome> createState() => _WakeOnLanHomeState();
}

class _WakeOnLanHomeState extends State<WakeOnLanHome> {
  final List<Device> _devices = [];
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('devices') ?? [];
    _devices.clear();
    _devices.addAll(list.map((j) => Device.fromJson(json.decode(j))));
    setState(() {});
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'devices', _devices.map((d) => json.encode(d.toJson())).toList());
  }

  Future<void> _addEditDevice({Device? old, int? index}) async {
    final nameC = TextEditingController(text: old?.name);
    final ipC = TextEditingController(text: old?.ip);
    final macC = TextEditingController(text: old?.mac);
    final portC = TextEditingController(text: '${old?.port ?? 9}');
    final subnetC = TextEditingController(text: old?.subnet ?? '255.255.255.0');

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(old == null ? 'Gerät hinzufügen' : 'Gerät bearbeiten'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                  controller: nameC, decoration: const InputDecoration(labelText: 'Name')),
              TextField(
                  controller: ipC, decoration: const InputDecoration(labelText: 'IP-Adresse')),
              TextField(
                  controller: macC, decoration: const InputDecoration(labelText: 'MAC-Adresse')),
              TextField(
                controller: portC,
                decoration: const InputDecoration(labelText: 'Port'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                  controller: subnetC,
                  decoration: const InputDecoration(labelText: 'Subnetzmaske')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: Navigator.of(context).pop, child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () {
              final d = Device(
                name: nameC.text,
                ip: ipC.text,
                mac: macC.text,
                port: int.tryParse(portC.text) ?? 9,
                subnet: subnetC.text,
              );
              setState(() {
                if (index != null) {
                  _devices[index] = d;
                } else {
                  _devices.add(d);
                }
              });
              _save();
              Navigator.of(context).pop();
            },
            child: Text(old == null ? 'Hinzufügen' : 'Speichern'),
          ),
        ],
      ),
    );
  }

  Future<void> _wake(Device d) async {
    setState(() => _isSending = true);
    try {
      final vi = IPAddress.validate(d.ip);
      final vm = MACAddress.validate(d.mac);
      if (!vi.state || !vm.state) throw Exception(vi.error ?? vm.error);

      // Broadcast Adresse berechnen (basiert auf IP und Subnetzmaske)
      final broadcastIp = calculateBroadcastAddress(d.ip, d.subnet);

      await WakeOnLAN(IPAddress(broadcastIp), MACAddress(d.mac), port: d.port).wake();

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${d.name} wurde erfolgreich geweckt'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fehler: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
    setState(() => _isSending = false);
  }

  String calculateBroadcastAddress(String ip, String subnetMask) {
    List<int> ipParts = ip.split('.').map(int.parse).toList();
    List<int> subnetParts = subnetMask.split('.').map(int.parse).toList();

    List<int> broadcastParts = List.filled(4, 0);

    for (int i = 0; i < 4; i++) {
      broadcastParts[i] = ipParts[i] | (~subnetParts[i] & 0xFF);
    }
    return broadcastParts.join('.');
  }

  Future<void> _confirmDelete(int idx) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Gerät löschen?'),
        content: Text('Willst du "${_devices[idx].name}" wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _devices.removeAt(idx);
      });
      await _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wake on LAN')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: ListView.builder(
          itemCount: _devices.length,
          itemBuilder: (context, index) {
            final device = _devices[index];
            return Builder(
              builder: (context) {
                return Slidable(
                  key: ValueKey(device.name + index.toString()),
                  endActionPane: ActionPane(
                    motion: const DrawerMotion(),
                    dismissible: DismissiblePane(
                      onDismissed: () async {
                        final removedDevice = device;

                        setState(() {
                          _devices.removeAt(index);
                        });

                        final shouldDelete = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Gerät löschen?'),
                            content: Text('Willst du "${removedDevice.name}" wirklich löschen?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: const Text('Abbrechen'),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: () => Navigator.of(context).pop(true),
                                child: const Text('Löschen'),
                              ),
                            ],
                          ),
                        );

                        if (shouldDelete == true) {
                          await _save();
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Gerät "${removedDevice.name}" gelöscht.'),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ));
                        } else {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            setState(() {
                              _devices.insert(index, removedDevice);
                            });
                          });
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: const Text('Löschen abgebrochen.'),
                            backgroundColor: Colors.red,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ));
                        }
                      },
                    ),
                    children: [
                      SlidableAction(
                        onPressed: (_) => _addEditDevice(old: device, index: index),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          bottomLeft: Radius.circular(8),
                        ),
                        icon: Icons.edit,
                      ),
                      SlidableAction(
                        onPressed: (_) => _confirmDelete(index),
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          bottomLeft: Radius.circular(8),
                        ),
                        icon: Icons.delete,
                      ),
                    ],
                  ),
                  child: GestureDetector(
                    onTap: _isSending ? null : () => _wake(device),
                    child: SizedBox(
                      width: double.infinity, // volle Breite
                      child: Card(
                        margin: EdgeInsets.zero, // kein Außenabstand, volle Breite
                        elevation: 6,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Stack(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 40),
                                  Text(device.name,
                                      style: const TextStyle(
                                          fontSize: 20, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 6),
                                  Text('IP: ${device.ip}',
                                      style: const TextStyle(fontSize: 16)),
                                  Text('MAC: ${device.mac}',
                                      style: const TextStyle(fontSize: 16)),
                                  Text('Port: ${device.port}',
                                      style: const TextStyle(fontSize: 16)),
                                ],
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: IconButton(
                                  icon: const Icon(Icons.power_settings_new,
                                      color: Colors.blueAccent),
                                  onPressed: _isSending ? null : () => _wake(device),
                                  tooltip: 'Wake Gerät',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addEditDevice(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
