# coturnのインストールと設定

## 1. coturnのインストール
AlmaLinux 8・9では、EPELリポジトリからcoturnをインストールできます。

```
cat /etc/almalinux-release
```

```
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --set-enabled crb
sudo dnf install -y epel-release
sudo dnf install -y coturn
```
AlmaLinux 8 ならcrbの代わりに powertools

確認
```
turnserver --version
```

## 2. 自宅サーバーのIPアドレスを確認

```
# 自宅サーバーのLAN側IP
ip -4 addr

# インターネット側のグローバルIP
curl -4 https://api.ipify.org
```


## 3. coturnの設定ファイルを作成
設定ファイルの場所は次のコマンドで確認できます。一般的には /etc/turnserver.conf。

```
sudo cp -a /etc/turnserver.conf /etc/turnserver.conf.bak

sudo nano /etc/turnserver.conf
```

- /etc/turnserver.conf 編集  
パスワードは次のコマンドで作成しておく。

```
openssl rand -hex 24
```

```
# STUN/TURN待ち受け
listening-port=3478

# AlmaLinuxのLAN側IP
listening-ip=192.168.1.100
relay-ip=192.168.1.100

# グローバルIPとLAN側IPの対応
external-ip=203.0.113.10/192.168.1.100

# 音声中継用UDPポート
min-port=49160
max-port=49200

# 認証
fingerprint
lt-cred-mech

realm=your-domain.example
user=demo-user:ここに強力なTURN用パスワード

# デモ用の接続数制限
user-quota=4
total-quota=10

# 不要な機能を無効化
no-multicast-peers
no-loopback-peers
no-cli
no-tls
no-dtls

# ログ
simple-log
```


## 4. coturnを起動

```
sudo systemctl enable --now coturn
```

確認

```
sudo systemctl status coturn
```
active (running)なら正常に起動しています。  


ポート確認

```
sudo ss -lunp | grep 3478
sudo ss -lntp | grep 3478

```

## 5. AlmaLinuxのファイアウォール設定

|ポート	|プロトコル	|用途|
|---|---|---|
|443	|TCP	|既存Apache / Socket.IO|
|3478	|UDP	|TURN接続|
|3478	|TCP	|TURN接続の代替経路|
|49160〜49200	|UDP	|TURN音声中継|


現在の設定を確認

```
sudo firewall-cmd --get-active-zones
```

設定を追加

```
sudo firewall-cmd --permanent --zone=public --add-port=3478/udp

sudo firewall-cmd --permanent --zone=public --add-port=3478/tcp

sudo firewall-cmd --permanent --zone=public --add-port=49160-49200/udp

sudo firewall-cmd --reload
```

確認
```
sudo firewall-cmd --zone=public --list-ports
```
3478/udp、3478/tcp、49160-49200/udpが表示されれば設定完了です。

## 6. 自宅ルーターのポート転送

|外部ポート	|転送先IP	|内部ポート|プロトコル|
|---|---|---|---|
|3478	|192.168.1.100	|3478	|UDP|
|3478	|192.168.1.100	|3478	|TCP|
|49160〜49200	|192.168.1.100	|同じ番号	|UDP|


## 7. 外部からTURN接続をテスト

https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/?utm_source=chatgpt.com

|項目	|値|
|---|---|
|STUN/TURN URI	|turn:your-domain.example:3478?transport=udp|
|TURN username	|demo-user|
|TURN password	|設定したTURN用パスワード|

Gather candidatesを押して、候補一覧に relay タイプが表示されるか確認。

```
Candidate type
relay

URL: turn:your-domain.example:3478?transport=udp

relay候補が取得できれば、TURNサーバーへの接続・認証と中継用アドレスの割り当てが確認できます。
```

- DDNSによるサーバーへの接続が成功
- coturnのTURN認証が成功
- TURN中継用のアドレスとポートを取得できた
- 設定した49160〜49200番の範囲が使用されている
