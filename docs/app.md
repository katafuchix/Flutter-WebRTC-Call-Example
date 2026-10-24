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


## 4. 今回の実装内容

### 1. 自宅サーバー（AlmaLinux）で構築するシステム

|構成	|技術	|役割|
|---|---|---|
|スマートフォン	|Flutter + flutter_webrtc	|音声通話・通話画面|
|通話制御サーバー	|Node.js + Socket.IO	|発信・着信・応答・切断|
|STUN/TURNサーバー	|coturn	|NAT越え・音声中継|
|OS	|AlmaLinux	|自宅サーバー|
|通信暗号化	|Let's Encrypt	|HTTPS / WSS用証明書|

### 2. 通話の流れ

1. Flutterアプリを起動し、Node.jsサーバーに接続。
2. ユーザーAがユーザーBに発信。
3. Socket.IO経由でBに着信通知。
4. Bが応答するとWebRTCの接続処理を開始。
5. 音声通話を行い、終了時に接続を切断。

相手が別のWi-Fiや携帯電話回線を使っていても、通話できる構成にできます。
ただし、インターネット経由の場合は、自宅ルーターのポート転送やファイアウォール設定が必要になります。

### 3. 自宅サーバーで注意すること
- グローバルIPv4アドレス：自宅回線がCGNATや一部のIPv4 over IPv6方式の場合、通常のポート転送ができない可能性があります。
- ポート開放：Node.js用のHTTPS/WSS（443/TCP）、coturn用の3478/UDP・TCP、TURN中継用UDPポート範囲などを設定します。
- coturnの外部IP設定：ルーターの内側に設置する場合、公開IPとサーバーのLAN側IPの対応設定が必要です。
