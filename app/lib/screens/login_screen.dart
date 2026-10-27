import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/api.dart';
import '../services/phone.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _server = TextEditingController();
  bool _otpSent = false;
  bool _busy = false;
  String? _error;
  String? _normalized;

  @override
  void initState() {
    super.initState();
    _server.text = context.read<AppState>().serverUrl;
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn();
    } on ApiException catch (e) {
      setState(() => _error = _friendly(e.message));
    } catch (_) {
      setState(() => _error = 'সার্ভারে সংযোগ করা যায়নি। ইন্টারনেট/সার্ভার ঠিকানা দেখুন।');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(String m) {
    switch (m) {
      case 'invalid phone':
        return 'ফোন নাম্বারটি সঠিক নয়';
      case 'code expired':
        return 'কোডের মেয়াদ শেষ, আবার কোড নিন';
      case 'wrong code':
        return 'কোডটি ভুল';
      case 'too many attempts':
      case 'too_many_requests':
        return 'অনেকবার চেষ্টা হয়েছে, কিছুক্ষণ পরে চেষ্টা করুন';
      default:
        return m;
    }
  }

  Future<void> _sendOtp() => _run(() async {
        final n = normalizePhone(_phone.text);
        if (n == null) throw ApiException('invalid phone');
        final state = context.read<AppState>();
        if (_server.text.trim().isNotEmpty) await state.setServer(_server.text);
        if (!await state.api.otpRequired()) {
          await state.login(n, '0'); // server runs without OTP: log in directly
          return;
        }
        await state.api.requestOtp(n);
        setState(() {
          _normalized = n;
          _otpSent = true;
        });
      });

  Future<void> _verify() => _run(() async {
        await context.read<AppState>().login(_normalized!, _code.text.trim());
      });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 40),
            Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(26)),
                child: Icon(Icons.videocam_rounded, size: 48, color: cs.onPrimary),
              ),
            ),
            const SizedBox(height: 20),
            Text('Connecto',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('ফোন নাম্বার দিয়ে সরাসরি ভিডিও কল।\nইউজারনেম বা পাসওয়ার্ড লাগবে না।',
                textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 36),
            if (!_otpSent) ...[
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'আপনার ফোন নাম্বার', hintText: '01XXXXXXXXX', prefixIcon: Icon(Icons.phone)),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _busy ? null : _sendOtp, child: const Text('কোড পাঠান')),
            ] else ...[
              Text('+$_normalized নাম্বারে SMS কোড পাঠানো হয়েছে',
                  textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                decoration: const InputDecoration(labelText: '৬ সংখ্যার কোড', counterText: ''),
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: _busy ? null : _verify, child: const Text('যাচাই করুন')),
              TextButton(
                  onPressed: _busy ? null : () => setState(() => _otpSent = false),
                  child: const Text('নাম্বার বদলান')),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
            ],
            if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
            const SizedBox(height: 28),
            ExpansionTile(
              title: const Text('সার্ভার সেটিংস (ডেভেলপার)'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    controller: _server,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                        labelText: 'সার্ভার URL', helperText: 'আসল ফোনে টেস্ট করলে পিসির IP দিন, যেমন http://192.168.0.5:3000'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
