import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/phone.dart';
import 'call_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AppState>().loadContacts());
  }

  void _call(String phone, String name) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CallScreen(peerPhone: phone, peerName: name, incoming: false),
    ));
  }

  void _dial() async {
    final c = TextEditingController();
    final n = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('নাম্বারে কল করুন'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(hintText: '01XXXXXXXXX'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('বাতিল')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('কল'),
          ),
        ],
      ),
    );
    if (n == null) return;
    final p = normalizePhone(n);
    if (p == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('নাম্বারটি সঠিক নয়')));
      }
      return;
    }
    _call(p, '+$p');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final list = s.contacts
        .where((c) => _q.isEmpty || c.name.toLowerCase().contains(_q) || c.phone.contains(_q))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connecto', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
              tooltip: 'রিফ্রেশ', onPressed: s.loadingContacts ? null : s.loadContacts, icon: const Icon(Icons.refresh)),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') s.logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text('আমার নাম্বার: +${s.myPhone}')),
              const PopupMenuItem(value: 'logout', child: Text('লগআউট')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'কন্টাক্ট খুঁজুন',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _dial,
        icon: const Icon(Icons.dialpad),
        label: const Text('নাম্বারে কল'),
      ),
      body: Builder(builder: (context) {
        if (s.loadingContacts && s.contacts.isEmpty) return const Center(child: CircularProgressIndicator());
        if (s.contactsError != null && s.contacts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(s.contactsError!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
                    onPressed: s.loadContacts,
                    child: const Text('আবার চেষ্টা')),
              ]),
            ),
          );
        }
        if (list.isEmpty) return const Center(child: Text('কোনো কন্টাক্ট পাওয়া যায়নি'));
        final registeredCount = list.where((c) => c.registered).length;
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 90),
          itemCount: list.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('$registeredCount জন কন্টাক্টে Connecto আছে',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              );
            }
            final c = list[i - 1];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: c.registered ? cs.primaryContainer : cs.surfaceContainerHighest,
                child: Text(c.name.isEmpty ? '?' : c.name.characters.first.toUpperCase()),
              ),
              title: Text(c.name, style: TextStyle(fontWeight: c.registered ? FontWeight.w600 : FontWeight.w400)),
              subtitle: Text(c.registered ? '+${c.phone}' : '+${c.phone} · Connecto ইনস্টল করেননি'),
              trailing: c.registered
                  ? IconButton.filledTonal(
                      onPressed: () => _call(c.phone, c.name), icon: const Icon(Icons.videocam_rounded))
                  : null,
              onTap: c.registered ? () => _call(c.phone, c.name) : null,
            );
          },
        );
      }),
    );
  }
}
