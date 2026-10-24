# Flutterアプリ作成時のメモ

```
flutter pub add flutter_webrtc socket_io_client
```


## 1. iOSのマイク権限

- ios/Runner/Info.plist

```
<key>NSMicrophoneUsageDescription</key>
<string>音声通話のためにマイクを使用します。</string>
```

## 2. Androidのマイク権限
- android/app/src/main/AndroidManifest.xml <manifest> 内

```
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
```


## 3. FlutterからのTURN接続設定
WebRTCの接続設定

```
final configuration = {
  'iceServers': [
    {
      'urls': [
        'turn:your-domain.example:3478?transport=udp',
      ],
      'username': 'demo-user',
      'credential': 'TURN用パスワード',
    },
  ],
  'iceTransportPolicy': 'relay',
};
```

今回は確実にTURNサーバーを経由したことを確認するため、relayを指定しています。

実際には、この設定を使ってRTCPeerConnectionを作成し、Socket.IOでOffer・Answer・ICE候補を交換します。デモ用の認証情報は限定的に利用し、後に必要なら短期認証情報へ変更します。
