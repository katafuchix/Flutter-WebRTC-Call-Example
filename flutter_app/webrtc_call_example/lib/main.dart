import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: CallDemoPage(),
  ));
}

class CallDemoPage extends StatefulWidget {
  const CallDemoPage({super.key});

  @override
  State<CallDemoPage> createState() => _CallDemoPageState();
}

class _CallDemoPageState extends State<CallDemoPage> {
  final urlController = TextEditingController(
      text: dotenv.env['SOCKET_URL'] ?? ''
  );

  final tokenController = TextEditingController(
      text: dotenv.env['DEMO_TOKEN'] ?? ''
  );

  final turnPasswordController = TextEditingController(
      text: dotenv.env['TURN_PASSWORD'] ?? ''
  );

  IO.Socket? socket;
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;

  final List<RTCIceCandidate> pendingCandidates = [];
  final List<String> logs = [];

  String userId = 'user-b';
  String status = '未接続';
  String callState = 'idle';
  String? callPeer;

  bool connected = false;
  bool muted = false;
  bool busy = false;

  String get peerId =>
      userId == 'user-a' ? 'user-b' : 'user-a';

  void log(String message) {
    debugPrint(message);
    if (!mounted) return;
    setState(() {
      logs.insert(0, message);
      if (logs.length > 100) logs.removeLast();
    });
  }

  void updateCallState(String state) {
    if (!mounted) return;
    setState(() => callState = state);
  }

  // Socket.IO接続
  void connect() {
    if (socket != null) return;

    final url = urlController.text.trim();
    final token = tokenController.text.trim();

    if (url.isEmpty || token.isEmpty) {
      log('サーバーURLとDEMO_TOKENを入力してください');
      return;
    }

    setState(() => status = '接続中');

    final s = IO.io(
      url,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableForceNew()
          .setAuth({
        'userId': userId,
        'token': token,
      })
          .build(),
    );

    socket = s;

    s.onConnect((_) {
      if (!mounted || socket != s) return;
      setState(() {
        connected = true;
        status = '接続済み';
      });
      log('Socket.IO接続成功');
    });

    s.onConnectError((error) {
      log('接続エラー: $error');
      if (mounted) setState(() => status = '接続エラー');
    });

    s.on('server:ready', (_) {
      log('サーバー準備完了');
    });

    s.on('server:error', (data) {
      log('サーバーエラー: $data');
      disconnect();
    });

    s.onDisconnect((_) {
      if (socket != s) return;
      if (mounted) {
        setState(() {
          connected = false;
          status = '切断';
        });
      }
      unawaited(cleanupCall());
      log('Socket.IO切断');
    });

    // 着信
    s.on('call:invite', (data) {
      if (data is! Map) return;
      final from = data['from']?.toString();
      if (from == null || from != peerId) return;

      if (callState != 'idle' || busy) {
        s.emit('call:reject', {
          'to': from,
          'reason': 'busy',
        });
        return;
      }

      callPeer = from;
      updateCallState('ringing');
      log('$from から着信');
    });

    // 相手が応答したらOfferを作成
    s.on('call:accept', (data) async {
      if (data is! Map ||
          data['from'] != callPeer ||
          callState != 'calling') {
        return;
      }

      log('相手が応答しました');
      updateCallState('connecting');

      try {
        await preparePeerConnection();
        final pc = peerConnection!;
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);

        s.emit('call:offer', {
          'to': callPeer,
          'sdp': offer.sdp,
          'type': offer.type,
        });
        log('Offer送信');
      } catch (e) {
        await callFailed(e);
      }
    });

    // 着信側がOfferを受信
    s.on('call:offer', (data) async {
      if (data is! Map ||
          data['from'] != callPeer ||
          callState != 'connecting') {
        return;
      }

      try {
        await preparePeerConnection();

        final pc = peerConnection!;
        await pc.setRemoteDescription(
          RTCSessionDescription(
            data['sdp'] as String,
            data['type'] as String,
          ),
        );

        await flushCandidates();

        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);

        s.emit('call:answer', {
          'to': callPeer,
          'sdp': answer.sdp,
          'type': answer.type,
        });

        log('Answer送信');
      } catch (e) {
        await callFailed(e);
      }
    });

    // 発信側がAnswerを受信
    s.on('call:answer', (data) async {
      if (data is! Map ||
          data['from'] != callPeer ||
          peerConnection == null) {
        return;
      }

      try {
        await peerConnection!.setRemoteDescription(
          RTCSessionDescription(
            data['sdp'] as String,
            data['type'] as String,
          ),
        );
        await flushCandidates();
        log('Answer受信');
      } catch (e) {
        await callFailed(e);
      }
    });

    // ICE候補の交換
    s.on('call:ice', (data) async {
      if (data is! Map ||
          data['from'] != callPeer) {
        return;
      }

      final candidate = RTCIceCandidate(
        data['candidate'] as String?,
        data['sdpMid'] as String?,
        (data['sdpMLineIndex'] as num?)?.toInt(),
      );

      try {
        final pc = peerConnection;
        if (pc == null ||
            await pc.getRemoteDescription() == null) {
          pendingCandidates.add(candidate);
        } else {
          await pc.addCandidate(candidate);
        }
      } catch (e) {
        log('ICE候補エラー: $e');
      }
    });

    s.on('call:reject', (data) async {
      if (data is! Map || data['from'] != callPeer) return;
      log('相手が拒否しました');
      await cleanupCall();
    });

    s.on('call:hangup', (data) async {
      if (data is! Map || data['from'] != callPeer) return;
      log('相手が通話を終了しました');
      await cleanupCall();
    });

    s.on('call:unavailable', (_) async {
      log('相手はオフラインです');
      await cleanupCall();
    });

    s.connect();
  }

  // WebRTCとマイクを準備
  Future<void> preparePeerConnection() async {
    if (peerConnection != null) return;

    final turnPassword = turnPasswordController.text.trim();

    if (turnPassword.isEmpty) {
      throw Exception('TURNパスワードが未入力です');
    }

    final config = <String, dynamic>{
      'iceServers': [
        {
          'urls': [
            'turn:spidering.mine.nu:3478?transport=udp',
          ],
          'username': 'demo-user',
          'credential': turnPassword,
        },
      ],
      // デモでは必ずTURNを使用
      'iceTransportPolicy': 'all', //'relay',
      'sdpSemantics': 'unified-plan',
    };

    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });

    localStream = stream;
    log('マイク取得成功');

    final pc = await createPeerConnection(config);
    peerConnection = pc;

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null || callPeer == null) {
        return;
      }

      socket?.emit('call:ice', {
        'to': callPeer,
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    pc.onIceConnectionState = (state) {
      log('ICE状態: $state');

      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        updateCallState('talking');
      }
    };

    pc.onConnectionState = (state) {
      log('接続状態: $state');
    };

    // 受信した音声はWebRTCがネイティブ側で再生
    pc.onTrack = (event) {
      if (event.track.kind == 'audio') {
        if (event.streams.isNotEmpty) {
          remoteStream = event.streams.first;
        }
        log('相手の音声トラックを受信');
      }
    };

    for (final track in stream.getAudioTracks()) {
      await pc.addTrack(track, stream);
    }
  }

  Future<void> flushCandidates() async {
    final pc = peerConnection;
    if (pc == null) return;

    final candidates = List<RTCIceCandidate>.from(pendingCandidates);
    pendingCandidates.clear();

    for (final candidate in candidates) {
      await pc.addCandidate(candidate);
    }
  }

  // 発信
  void makeCall() {
    if (!connected || callState != 'idle' || busy) return;

    if (turnPasswordController.text.trim().isEmpty) {
      log('TURNパスワードを入力してください');
      return;
    }

    callPeer = peerId;
    updateCallState('calling');

    socket?.emit('call:invite', {
      'to': peerId,
    });

    log('$peerId に発信しました');
  }

  // 着信応答
  Future<void> acceptCall() async {
    if (!connected || callState != 'ringing' || busy) return;

    if (turnPasswordController.text.trim().isEmpty) {
      log('TURNパスワードを入力してください');
      return;
    }

    updateCallState('connecting');

    // 応答前にマイク使用許可を取得する
    try {
      await preparePeerConnection();
      socket?.emit('call:accept', {
        'to': callPeer,
      });
      log('着信に応答');
    } catch (e) {
      await callFailed(e);
    }
  }

  void rejectCall() {
    if (callState != 'ringing') return;

    socket?.emit('call:reject', {
      'to': callPeer,
    });

    unawaited(cleanupCall());
  }

  // 通話終了
  Future<void> hangup() async {
    if (callState == 'idle') return;

    socket?.emit('call:hangup', {
      'to': callPeer,
    });

    await cleanupCall();
    log('通話終了');
  }

  Future<void> callFailed(Object error) async {
    log('通話エラー: $error');

    socket?.emit('call:hangup', {
      'to': callPeer,
    });

    await cleanupCall();
  }

  Future<void> cleanupCall() async {
    if (busy) return;
    busy = true;

    final pc = peerConnection;
    final stream = localStream;

    peerConnection = null;
    localStream = null;
    remoteStream = null;
    callPeer = null;
    pendingCandidates.clear();

    if (mounted) {
      setState(() {
        callState = 'idle';
        muted = false;
      });
    }

    try {
      await pc?.close();
      await pc?.dispose();
      if (stream != null) {
        for (final track in stream.getTracks()) {
          track.stop();
        }
        await stream.dispose();
      }
    } finally {
      busy = false;
    }
  }

  void toggleMute() {
    final tracks = localStream?.getAudioTracks() ?? [];
    if (tracks.isEmpty) return;

    final next = !muted;
    for (final track in tracks) {
      track.enabled = !next;
    }

    setState(() => muted = next);
  }

  void disconnect() {
    if (callState != 'idle') {
      socket?.emit('call:hangup', {
        'to': callPeer,
      });
    }

    socket?.dispose();
    socket = null;
    unawaited(cleanupCall());

    if (mounted) {
      setState(() {
        connected = false;
        status = '未接続';
      });
    }
  }

  @override
  void dispose() {
    socket?.dispose();
    final pc = peerConnection;
    final stream = localStream;
    if (pc != null) {
      unawaited(pc.close().then((_) => pc.dispose()));
    }
    if (stream != null) {
      for (final track in stream.getTracks()) {
        track.stop();
      }
      unawaited(stream.dispose());
    }
    urlController.dispose();
    tokenController.dispose();
    turnPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inCall = callState != 'idle';

    return Scaffold(
      appBar: AppBar(title: const Text('WebRTC音声通話デモ')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: urlController,
            enabled: !connected && socket == null,
            decoration: const InputDecoration(
              labelText: 'Socket.IO URL',
            ),
          ),
          TextField(
            controller: tokenController,
            enabled: !connected && socket == null,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'DEMO_TOKEN',
            ),
          ),
          TextField(
            controller: turnPasswordController,
            enabled: !inCall,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'TURNパスワード',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButton<String>(
            value: userId,
            isExpanded: true,
            items: const [
              DropdownMenuItem(
                value: 'user-a',
                child: Text('ユーザーA'),
              ),
              DropdownMenuItem(
                value: 'user-b',
                child: Text('ユーザーB'),
              ),
            ],
            onChanged: connected || socket != null
                ? null
                : (value) {
              if (value != null) {
                setState(() => userId = value);
              }
            },
          ),
          const SizedBox(height: 12),
          Text('サーバー: $status'),
          Text('通話状態: $callState'),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: connected
                ? disconnect
                : socket == null
                ? connect
                : null,
            child: Text(connected ? 'サーバー切断' : 'サーバー接続'),
          ),
          const Divider(height: 32),
          if (callState == 'idle')
            ElevatedButton.icon(
              onPressed: connected && !busy ? makeCall : null,
              icon: const Icon(Icons.call),
              label: Text('$peerId に発信'),
            ),
          if (callState == 'ringing') ...[
            Text('$callPeer から着信'),
            ElevatedButton.icon(
              onPressed: busy ? null : acceptCall,
              icon: const Icon(Icons.call),
              label: const Text('応答'),
            ),
            ElevatedButton.icon(
              onPressed: rejectCall,
              icon: const Icon(Icons.call_end),
              label: const Text('拒否'),
            ),
          ],
          if (inCall && callState != 'ringing') ...[
            ElevatedButton.icon(
              onPressed: toggleMute,
              icon: Icon(muted ? Icons.mic_off : Icons.mic),
              label: Text(muted ? 'ミュート解除' : 'ミュート'),
            ),
            ElevatedButton.icon(
              onPressed: hangup,
              icon: const Icon(Icons.call_end),
              label: const Text('通話終了'),
            ),
          ],
          const Divider(height: 32),
          const Text(
            '通信ログ',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 260,
            padding: const EdgeInsets.all(12),
            color: Colors.black87,
            child: ListView.builder(
              itemCount: logs.length,
              itemBuilder: (context, index) {
                return Text(
                  logs[index],
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}