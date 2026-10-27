import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../app_state.dart';

class CallScreen extends StatefulWidget {
  final String peerPhone;
  final String peerName;
  final bool incoming;
  final String? callId;
  const CallScreen({
    super.key,
    required this.peerPhone,
    required this.peerName,
    required this.incoming,
    this.callId,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _local = RTCVideoRenderer();
  final _remote = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _stream;
  io.Socket? _socket;
  String? _callId;

  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescSet = false;
  bool _closed = false;
  bool _connected = false;
  bool _muted = false;
  bool _camOff = false;
  bool _speaker = true;
  String _status = 'প্রস্তুত হচ্ছে...';
  Timer? _timer;
  int _seconds = 0;

  late final void Function(dynamic) _onSignal;
  late final void Function(dynamic) _onAccepted;
  late final void Function(dynamic) _onEnded;

  @override
  void initState() {
    super.initState();
    _callId = widget.callId;
    _start();
  }

  Future<void> _start() async {
    final state = context.read<AppState>();
    _socket = state.socket;
    if (_socket == null) return _fail('সার্ভারের সাথে সংযোগ নেই');

    final cam = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    if (!cam.isGranted || !mic.isGranted) return _fail('ক্যামেরা ও মাইক্রোফোনের অনুমতি দিন');

    try {
      await _local.initialize();
      await _remote.initialize();

      final ice = await state.api.iceServers();
      _stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {'facingMode': 'user', 'width': 640, 'height': 480},
      });
      _local.srcObject = _stream;

      final pc = await createPeerConnection({'iceServers': ice, 'sdpSemantics': 'unified-plan'});
      _pc = pc;
      for (final t in _stream!.getTracks()) {
        await pc.addTrack(t, _stream!);
      }
      pc.onIceCandidate = (c) {
        if (c.candidate != null) _sendSignal({'type': 'candidate', 'candidate': c.toMap()});
      };
      pc.onTrack = (e) {
        if (e.streams.isNotEmpty && mounted) setState(() => _remote.srcObject = e.streams.first);
      };
      pc.onConnectionState = (s) {
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _onConnected();
        } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _fail('সংযোগ ব্যর্থ হয়েছে');
        }
      };
      Helper.setSpeakerphoneOn(true);
    } catch (e) {
      return _fail('ক্যামেরা/মাইক চালু করা যায়নি');
    }

    // Register listeners BEFORE accepting/inviting so no early signal is missed.
    _onSignal = (d) => _handleSignal(Map<String, dynamic>.from(d as Map));
    _onAccepted = (d) => _handleAccepted(Map<String, dynamic>.from(d as Map));
    _onEnded = (d) {
      final m = Map<String, dynamic>.from(d as Map);
      if (m['callId'] != _callId) return;
      _finish(_reasonText(m['reason'] as String?));
    };
    _socket!
      ..on('signal', _onSignal)
      ..on('call:accepted', _onAccepted)
      ..on('call:ended', _onEnded);

    if (widget.incoming) {
      setState(() => _status = 'সংযোগ হচ্ছে...');
      _socket!.emit('call:accept', {'callId': _callId});
    } else {
      setState(() => _status = 'রিং হচ্ছে...');
      _socket!.emitWithAck('call:invite', {'to': widget.peerPhone}, ack: (res) {
        final m = (res is Map) ? res : {};
        if (m['error'] != null) {
          _fail(_errText(m['error'] as String));
        } else {
          _callId = m['callId'] as String?;
        }
      });
    }
  }

  // Caller: callee accepted -> create offer
  Future<void> _handleAccepted(Map<String, dynamic> d) async {
    if (d['callId'] != _callId || _pc == null) return;
    setState(() => _status = 'সংযোগ হচ্ছে...');
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    _sendSignal({'type': 'offer', 'sdp': offer.sdp});
  }

  Future<void> _handleSignal(Map<String, dynamic> d) async {
    if (d['callId'] != _callId || _pc == null || _closed) return;
    final data = Map<String, dynamic>.from(d['data'] as Map);
    switch (data['type']) {
      case 'offer':
        await _pc!.setRemoteDescription(RTCSessionDescription(data['sdp'] as String, 'offer'));
        _remoteDescSet = true;
        final answer = await _pc!.createAnswer();
        await _pc!.setLocalDescription(answer);
        _sendSignal({'type': 'answer', 'sdp': answer.sdp});
        await _flushCandidates();
        break;
      case 'answer':
        await _pc!.setRemoteDescription(RTCSessionDescription(data['sdp'] as String, 'answer'));
        _remoteDescSet = true;
        await _flushCandidates();
        break;
      case 'candidate':
        final c = Map<String, dynamic>.from(data['candidate'] as Map);
        final cand = RTCIceCandidate(c['candidate'] as String?, c['sdpMid'] as String?, c['sdpMLineIndex'] as int?);
        if (_remoteDescSet) {
          await _pc!.addCandidate(cand);
        } else {
          _pendingCandidates.add(cand);
        }
        break;
    }
  }

  Future<void> _flushCandidates() async {
    for (final c in _pendingCandidates) {
      await _pc!.addCandidate(c);
    }
    _pendingCandidates.clear();
  }

  void _sendSignal(Map<String, dynamic> data) {
    _socket?.emit('signal', {'callId': _callId, 'data': data});
  }

  void _onConnected() {
    if (_connected || !mounted) return;
    _connected = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
    setState(() => _status = 'সংযুক্ত');
  }

  String _errText(String code) {
    switch (code) {
      case 'not_registered':
        return 'এই নাম্বারে Connecto নেই';
      case 'busy':
        return 'ব্যস্ত আছেন';
      default:
        return 'কল করা যায়নি';
    }
  }

  String _reasonText(String? r) {
    switch (r) {
      case 'rejected':
        return 'কল কেটে দেওয়া হয়েছে';
      case 'no_answer':
        return 'উত্তর দেননি';
      case 'disconnected':
        return 'সংযোগ বিচ্ছিন্ন হয়েছে';
      default:
        return 'কল শেষ';
    }
  }

  void _fail(String msg) {
    if (_callId != null) _socket?.emit('call:end', {'callId': _callId});
    _finish(msg);
  }

  void _hangUp() {
    if (_callId != null) _socket?.emit('call:end', {'callId': _callId});
    _finish(null);
  }

  Future<void> _finish(String? message) async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    await _cleanup();
    if (!mounted) return;
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _cleanup() async {
    try {
      _socket
        ?..off('signal', _onSignal)
        ..off('call:accepted', _onAccepted)
        ..off('call:ended', _onEnded);
    } catch (_) {}
    try {
      for (final t in _stream?.getTracks() ?? <MediaStreamTrack>[]) {
        await t.stop();
      }
      await _stream?.dispose();
      await _pc?.close();
    } catch (_) {}
    _stream = null;
    _pc = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (!_closed) {
      _closed = true;
      if (_callId != null) _socket?.emit('call:end', {'callId': _callId});
      _cleanup();
    }
    _local.dispose();
    _remote.dispose();
    super.dispose();
  }

  void _toggleMute() {
    _muted = !_muted;
    for (final t in _stream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !_muted;
    }
    setState(() {});
  }

  void _toggleCam() {
    _camOff = !_camOff;
    for (final t in _stream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !_camOff;
    }
    setState(() {});
  }

  Future<void> _switchCamera() async {
    final tracks = _stream?.getVideoTracks() ?? [];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  void _toggleSpeaker() {
    _speaker = !_speaker;
    Helper.setSpeakerphoneOn(_speaker);
    setState(() {});
  }

  String get _timeText {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final hasRemote = _remote.srcObject != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hangUp();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1220),
        body: Stack(
          children: [
            Positioned.fill(
              child: hasRemote
                  ? RTCVideoView(_remote, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        CircleAvatar(
                          radius: 52,
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          child: Text(widget.peerName.isEmpty ? '?' : widget.peerName.characters.first.toUpperCase(),
                              style: const TextStyle(fontSize: 40, color: Colors.white)),
                        ),
                        const SizedBox(height: 20),
                        Text(widget.peerName,
                            style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text(_status, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                      ]),
                    ),
            ),
            if (hasRemote)
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration:
                        BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                    child: Text('${widget.peerName} · $_timeText',
                        style: const TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            // Self preview
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Container(
                  margin: const EdgeInsets.all(12),
                  width: 104,
                  height: 148,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _camOff
                      ? const ColoredBox(color: Colors.black54, child: Center(child: Icon(Icons.videocam_off, color: Colors.white54)))
                      : RTCVideoView(_local, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                ),
              ),
            ),
            // Controls
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Ctl(icon: _muted ? Icons.mic_off : Icons.mic, active: _muted, onTap: _toggleMute),
                      _Ctl(icon: _camOff ? Icons.videocam_off : Icons.videocam, active: _camOff, onTap: _toggleCam),
                      _Ctl(icon: Icons.cameraswitch, onTap: _switchCamera),
                      _Ctl(icon: _speaker ? Icons.volume_up : Icons.volume_down, active: !_speaker, onTap: _toggleSpeaker),
                      _Ctl(icon: Icons.call_end, color: Colors.red, onTap: _hangUp),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Ctl extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final Color? color;
  const _Ctl({required this.icon, required this.onTap, this.active = false, this.color});

  @override
  Widget build(BuildContext context) {
    final bg = color ?? (active ? Colors.white : Colors.white24);
    final fg = color != null ? Colors.white : (active ? Colors.black : Colors.white);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(15), child: Icon(icon, color: fg, size: 26)),
        ),
      ),
    );
  }
}
