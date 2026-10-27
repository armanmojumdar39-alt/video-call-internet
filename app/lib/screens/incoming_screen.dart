import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../app_state.dart';
import 'call_screen.dart';

class IncomingScreen extends StatefulWidget {
  final String callId;
  final String peerPhone;
  final String peerName;
  const IncomingScreen({super.key, required this.callId, required this.peerPhone, required this.peerName});

  @override
  State<IncomingScreen> createState() => _IncomingScreenState();
}

class _IncomingScreenState extends State<IncomingScreen> {
  io.Socket? _socket;
  late final void Function(dynamic) _onEnded;

  @override
  void initState() {
    super.initState();
    _socket = context.read<AppState>().socket;
    _onEnded = (data) {
      if (data is Map && data['callId'] == widget.callId && mounted) Navigator.of(context).pop();
    };
    _socket?.on('call:ended', _onEnded);
  }

  @override
  void dispose() {
    _socket?.off('call:ended', _onEnded);
    super.dispose();
  }

  void _reject() {
    _socket?.emit('call:reject', {'callId': widget.callId});
    Navigator.of(context).pop();
  }

  void _accept() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => CallScreen(
        peerPhone: widget.peerPhone,
        peerName: widget.peerName,
        incoming: true,
        callId: widget.callId,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            CircleAvatar(
              radius: 56,
              backgroundColor: cs.primary,
              child: Text(widget.peerName.isEmpty ? '?' : widget.peerName.characters.first.toUpperCase(),
                  style: TextStyle(fontSize: 44, color: cs.onPrimary)),
            ),
            const SizedBox(height: 24),
            Text(widget.peerName,
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('Connecto ভিডিও কল...', style: TextStyle(color: Colors.white70, fontSize: 16)),
            const Spacer(flex: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _RoundButton(color: Colors.red, icon: Icons.call_end, label: 'কেটে দিন', onTap: _reject),
                  _RoundButton(color: Colors.green, icon: Icons.videocam, label: 'ধরুন', onTap: _accept),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _RoundButton({required this.color, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(20), child: Icon(icon, color: Colors.white, size: 32)),
        ),
      ),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(color: Colors.white70)),
    ]);
  }
}
