import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'screens/incoming_screen.dart';
import 'services/api.dart';
import 'services/phone.dart';

class AppContact {
  final String name;
  final String phone; // normalized
  final bool registered;
  AppContact(this.name, this.phone, this.registered);
}

class AppState extends ChangeNotifier {
  // Set at build time: flutter build apk --dart-define=SERVER_URL=https://your-server
  // Fallback 10.0.2.2 = Android emulator -> host machine.
  static const defaultServer =
      String.fromEnvironment('SERVER_URL', defaultValue: 'http://10.0.2.2:3000');

  final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
  late SharedPreferences _prefs;
  Api api = Api(defaultServer);
  io.Socket? socket;

  String serverUrl = defaultServer;
  String? token;
  String? myPhone;
  bool ready = false;
  bool loadingContacts = false;
  String? contactsError;
  List<AppContact> contacts = [];

  bool get loggedIn => token != null;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    serverUrl = _prefs.getString('server') ?? defaultServer;
    token = _prefs.getString('token');
    myPhone = _prefs.getString('phone');
    api = Api(serverUrl, token: token);
    if (loggedIn) _connectSocket();
    ready = true;
    notifyListeners();
  }

  Future<void> setServer(String url) async {
    serverUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    await _prefs.setString('server', serverUrl);
    api = Api(serverUrl, token: token);
    notifyListeners();
  }

  Future<void> login(String phone, String code) async {
    final res = await api.verifyOtp(phone, code);
    token = res['token'] as String;
    myPhone = res['phone'] as String;
    await _prefs.setString('token', token!);
    await _prefs.setString('phone', myPhone!);
    api = Api(serverUrl, token: token);
    _connectSocket();
    notifyListeners();
  }

  Future<void> logout() async {
    socket?.dispose();
    socket = null;
    token = null;
    myPhone = null;
    contacts = [];
    await _prefs.remove('token');
    await _prefs.remove('phone');
    notifyListeners();
  }

  void _connectSocket() {
    socket?.dispose();
    final s = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableReconnection()
          .disableAutoConnect()
          .build(),
    );
    s.on('call:incoming', (data) {
      final m = Map<String, dynamic>.from(data as Map);
      _showIncoming(m['callId'] as String, m['from'] as String);
    });
    s.on('connect_error', (e) {
      // Expired/invalid token -> force re-login
      if (e.toString().contains('unauthorized')) logout();
    });
    s.connect();
    socket = s;
  }

  bool _ringing = false;

  void _showIncoming(String callId, String from) {
    if (_ringing) return;
    _ringing = true;
    final name = nameFor(from);
    navKey.currentState
        ?.push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => IncomingScreen(callId: callId, peerPhone: from, peerName: name),
        ))
        .whenComplete(() => _ringing = false);
  }

  String nameFor(String phone) {
    for (final c in contacts) {
      if (c.phone == phone) return c.name;
    }
    return '+$phone';
  }

  /// Reads the phone's contacts, hashes numbers, asks the server who has the app.
  Future<void> loadContacts() async {
    loadingContacts = true;
    contactsError = null;
    notifyListeners();
    try {
      if (!await FlutterContacts.requestPermission(readonly: true)) {
        contactsError = 'কন্টাক্ট দেখার অনুমতি দিন (Settings থেকে)';
        return;
      }
      final raw = await FlutterContacts.getContacts(withProperties: true);
      final byHash = <String, AppContact>{};
      final all = <String, String>{}; // phone -> name
      for (final c in raw) {
        for (final p in c.phones) {
          final n = normalizePhone(p.number);
          if (n == null || n == myPhone) continue;
          all[n] = c.displayName;
        }
      }
      final hashes = <String>[];
      for (final e in all.entries) {
        final h = sha256Hex(e.key);
        hashes.add(h);
        byHash[h] = AppContact(e.value, e.key, false);
      }
      final matched = <String>{};
      for (var i = 0; i < hashes.length; i += 1000) {
        final end = (i + 1000 > hashes.length) ? hashes.length : i + 1000;
        matched.addAll(await api.matchContacts(hashes.sublist(i, end)));
      }
      final list = byHash.entries
          .map((e) => AppContact(e.value.name, e.value.phone, matched.contains(e.key)))
          .toList()
        ..sort((a, b) {
          if (a.registered != b.registered) return a.registered ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      contacts = list;
    } on ApiException catch (e) {
      contactsError = e.message;
    } catch (e) {
      contactsError = 'কন্টাক্ট লোড করা যায়নি';
    } finally {
      loadingContacts = false;
      notifyListeners();
    }
  }
}
