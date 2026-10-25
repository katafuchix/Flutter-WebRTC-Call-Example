# Flutter-WebRTC-Call-Example

FlutterとWebRTCを利用した、iOS・Android間の音声通話デモアプリです。
Amazon Chime SDKなどの有料通話サービスを利用せず、オープンソースの技術と自宅のAlmaLinuxサーバーを組み合わせて、発信・着信・音声通話を実現しています。

<div>
<img width="320" alt="Image" src="https://github.com/user-attachments/assets/231d0039-6fe3-436f-844e-99f94b8bf768" />&nbsp;&nbsp;
<img width="320" alt="Image" src="https://github.com/user-attachments/assets/1d19d0fa-4388-40ad-8cc1-d61606debcd1" />
</div>
## 主な機能

- iOS・Android間の音声通話
- ユーザー間の発信・着信・応答・拒否
- 通話終了・マイクのミュート
- WebSocketによる通話制御
- TURNサーバーを経由した音声通信
- 接続状態・通信ログの表示

## システム構成

| 区分 | 使用技術 | 役割 |
|---|---|---|
| モバイルアプリ | Flutter / Dart | 通話画面・ユーザー操作 |
| 音声通信 | flutter_webrtc / WebRTC | リアルタイム音声通信 |
| 通話制御 | Node.js / Socket.IO | 発信・着信・接続情報の交換 |
| STUN/TURN | coturn | NAT越え・音声中継 |
| Webサーバー | Apache / HTTPS | Socket.IOへのリバースプロキシ |
| サーバーOS | AlmaLinux 8.10 | 通話サーバーの実行環境 |

## 通話の仕組み

1. FlutterアプリからSocket.IOサーバーに接続します。
2. WebSocketを使って発信・着信・応答などの情報を交換します。
3. WebRTCのOffer・Answer・ICE候補を交換して通信経路を確立します。
4. coturnを経由して音声データを送受信します。
5. 通話終了時にWebRTC接続を切断します。

## 動作確認

以下の環境で基本動作を確認しています。

- iPhone・Androidの実機間で音声通話
- 異なるネットワーク間での接続
- TURNサーバー経由の音声通信
- 発信・着信・応答・切断

音声通話は成立していますが、音声品質には改善の余地があります。

## セットアップ・技術資料

サーバーの構築手順、Flutterアプリの実装方法、設定ファイルなどの詳細は、別途Markdownファイルにまとめています。

- [`docs/overview.md`](docs/overview.md) — システム概要
- [`docs/server.md`](docs/server.md) — Node.js、Socket.IO、Apache などのサーバー構築
- [`docs/coturn.md`](docs/coturn.md) — coturnの設定とテスト
- [`docs/app.md`](docs/app.md) — Flutter アプリ
- [`docs/call_test.md`](docs/call_test.md) — テスト手順

※ 各資料へのリンクは実際のファイル名に合わせて設定してください。

## 設定情報の管理

サーバーURLや認証情報は環境設定ファイルで管理します。

## 開発目的

WebRTCによる音声通話の仕組みを理解し、Flutterとオープンソースのサーバー技術だけで通話アプリを構築できることを検証するためのプロジェクトです。
本プロジェクトは技術検証用のデモであり、商用運用を想定したものではありません。
