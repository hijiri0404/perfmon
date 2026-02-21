# perfmon 設計ドキュメント

## 概要
Linux (RHEL) 上で CPU/メモリ/ディスクIO/ネットワークなどのシステム負荷をプロセス単位含め時系列で記録する常駐ツール。RPMパッケージとして配布する。

## ファイル構成

```
/opt/perfmon/
  bin/
    perfmon-collector.sh   # メイン収集スクリプト（systemdから起動）
  log/
    vmstat_YYYYMMDD.log    # vmstat 出力ログ
    iostat_YYYYMMDD.log    # iostat 出力ログ
    pidstat_YYYYMMDD.log   # pidstat 出力ログ
    mpstat_YYYYMMDD.log    # mpstat 出力ログ
    sar_net_YYYYMMDD.log   # sar ネットワーク統計ログ
    top_YYYYMMDD.log       # top バッチ出力ログ
    meminfo_YYYYMMDD.log   # /proc/meminfo 詳細メモリ情報ログ
    netstat_YYYYMMDD.log   # ss -s TCP接続状態ログ
    df_YYYYMMDD.log        # ディスク容量・inode使用率ログ
    fdcount_YYYYMMDD.log   # ファイルディスクリプタ数ログ
    dstate_YYYYMMDD.log    # D状態プロセスログ
    connections_YYYYMMDD.log # TCP/UDP全ソケット一覧ログ
    lsof_YYYYMMDD.log      # プロセス別オープンファイルログ
    dmesg_YYYYMMDD.log     # カーネルメッセージログ
/etc/perfmon/
  perfmon.conf             # 設定ファイル
/usr/bin/
  perfmon-save             # zip圧縮コマンド
/usr/lib/systemd/system/
  perfmon.service          # systemd ユニットファイル
```

## 設定パラメータ（/etc/perfmon/perfmon.conf）

| パラメータ | デフォルト | 説明 |
|---|---|---|
| INTERVAL | 60 | 収集間隔（秒） |
| LSOF_INTERVAL | 300 | lsof 収集間隔（秒）。出力が大きいため INTERVAL より長い値を推奨 |
| RETENTION_DAYS | 7 | ログ保持日数 |
| LOG_DIR | /opt/perfmon/log | ログ出力先 |

## 収集コマンドと出力カラム

### vmstat（vmstat_YYYYMMDD.log）
`vmstat -n INTERVAL` で収集。先頭行にカラムヘッダーを出力し、以降の各行にタイムスタンプを付与。

| カラム | 説明 |
|---|---|
| r | 実行待ちプロセス数 |
| b | ブロック中プロセス数 |
| swpd | 使用中swap (KB) |
| free | 空きメモリ (KB) |
| buff | バッファ (KB) |
| cache | キャッシュ (KB) |
| si | swap in (KB/s) |
| so | swap out (KB/s) |
| bi | ブロックin (blocks/s) |
| bo | ブロックout (blocks/s) |
| in | 割り込み回数/秒 |
| cs | コンテキストスイッチ回数/秒 |
| us | ユーザーCPU% |
| sy | システムCPU% |
| id | アイドルCPU% |
| wa | IO待ちCPU% |
| st | steal CPU% |
| gu | guest nice CPU% |

### iostat（iostat_YYYYMMDD.log）
`iostat -dxkt INTERVAL` で拡張統計をデバイス単位で記録。各行にタイムスタンプを付与。

| カラム | 説明 |
|---|---|
| Device | デバイス名 |
| r/s | 読み取りリクエスト/秒 |
| rkB/s | 読み取りKB/秒 |
| rrqm/s | 読み取りマージリクエスト/秒 |
| %rrqm | マージ率% |
| r_await | 平均読み取りIO待ち時間(ms) |
| rareq-sz | 平均読み取りリクエストサイズ(KB) |
| w/s | 書き込みリクエスト/秒 |
| wkB/s | 書き込みKB/秒 |
| wrqm/s | 書き込みマージリクエスト/秒 |
| %wrqm | 書き込みマージ率% |
| w_await | 平均書き込みIO待ち時間(ms) |
| wareq-sz | 平均書き込みリクエストサイズ(KB) |
| d/s | discard リクエスト/秒 |
| dkB/s | discard KB/秒 |
| drqm/s | discard マージリクエスト/秒 |
| %drqm | discard マージ率% |
| d_await | 平均discard IO待ち時間(ms) |
| dareq-sz | 平均discardリクエストサイズ(KB) |
| f/s | flush リクエスト/秒 |
| f_await | 平均flush待ち時間(ms) |
| aqu-sz | 平均キュー長 |
| %util | デバイス使用率% |

### pidstat（pidstat_YYYYMMDD.log）
`pidstat -u -r -d -l INTERVAL` でプロセス単位のCPU/メモリ/ディスクIOを記録。`-l` でフルコマンドパス+引数を表示する。

- **-u**: CPU使用率（%usr, %system, %guest, %wait, %CPU）
- **-r**: メモリ使用率（minflt/s, majflt/s, VSZ, RSS, %MEM）
- **-d**: ディスクIO（kB_rd/s, kB_wr/s, kB_ccwr/s, iodelay）
- **-l**: フルコマンドライン（パス+引数）を表示

**タイムスタンプについて**: 各行には収集タイムスタンプ（gawk付与）と pidstat 内部タイムスタンプの2つが含まれる。pidstat はヘッダーを区間開始時刻、データ行を区間終了時刻で出力するため、1分ずれるのは正常な仕様。

```
収集TS       pidstat内部TS  内容
22:26:24     22:25:24       UID PID %usr ...  ← ヘッダー（区間開始）
22:26:24     22:26:24       0   1   0.15 ...  ← データ（区間終了）
```

### mpstat（mpstat_YYYYMMDD.log）
`mpstat -P ALL INTERVAL` で CPU コア別使用率を記録。all（全体）と各コアの行を出力。

| カラム | 説明 |
|---|---|
| CPU | コア番号（all=全体） |
| %usr | ユーザーCPU% |
| %nice | nice付きユーザーCPU% |
| %sys | システムCPU% |
| %iowait | IO待ちCPU% |
| %irq | ハードウェア割り込みCPU% |
| %soft | ソフトウェア割り込みCPU% |
| %steal | steal CPU% |
| %guest | ゲストCPU% |
| %gnice | nice付きゲストCPU% |
| %idle | アイドルCPU% |

### sar（sar_net_YYYYMMDD.log）
`sar -n DEV INTERVAL` でネットワークインタフェース統計を記録。

| カラム | 説明 |
|---|---|
| IFACE | インタフェース名 |
| rxpck/s | 受信パケット/秒 |
| txpck/s | 送信パケット/秒 |
| rxkB/s | 受信KB/秒 |
| txkB/s | 送信KB/秒 |
| rxcmp/s | 受信圧縮パケット/秒 |
| txcmp/s | 送信圧縮パケット/秒 |
| rxmcst/s | 受信マルチキャストパケット/秒 |
| %ifutil | インタフェース使用率% |

### top（top_YYYYMMDD.log）
`top -b -c -w 512 -d INTERVAL` でシステム概要とプロセス一覧をスナップショット形式で記録。`-c` でフルコマンドパス+引数を表示し、`-w 512` で行幅を広げて切り捨てを防ぐ。他のログと同様に各行の先頭にタイムスタンプを付与する。スナップショット間は空行で区切る。

### meminfo（meminfo_YYYYMMDD.log）
`/proc/meminfo` を INTERVAL 秒ごとに読み取り全行にタイムスタンプを付与して記録する。vmstat では取得できない詳細項目（Slab/HugePages/Dirty/CommitLimit 等）を補完する。スナップショット間は空行で区切る。

障害調査で特に参照頻度が高い項目を以下に示す。

**基本メモリ**

| フィールド | 説明 |
|---|---|
| MemTotal | 物理メモリ合計 (kB) |
| MemFree | 未使用メモリ (kB)。低くても MemAvailable が十分なら問題なし |
| MemAvailable | アプリが実際に利用可能なメモリの推定値 (kB)。キャッシュの解放分を含む |
| Buffers | ブロックデバイスのバッファキャッシュ (kB) |
| Cached | ページキャッシュ (kB)。MemAvailable の算出に含まれる |
| SwapCached | swap に書き出されたがメモリにも残っているページ (kB) |

**スワップ**

| フィールド | 説明 |
|---|---|
| SwapTotal | swap 合計 (kB) |
| SwapFree | 空き swap (kB)。減少傾向がある場合はメモリ不足のサイン |

**メモリ逼迫の指標**

| フィールド | 説明 |
|---|---|
| Dirty | ディスクへの書き込み待ちページ (kB)。高い場合は IO ボトルネックの可能性 |
| Writeback | 現在ディスクへ書き込み中のページ (kB) |
| CommitLimit | オーバーコミットを考慮したメモリ割り当て上限 (kB) |
| Committed_AS | プロセスが要求済みの仮想メモリ合計 (kB)。CommitLimit を超えると新規割り当て失敗 |

**カーネルメモリ・Slab**

| フィールド | 説明 |
|---|---|
| Slab | カーネルのデータ構造キャッシュ合計 (kB) |
| SReclaimable | 解放可能な Slab (kB)。ページキャッシュ同様に回収される |
| SUnreclaim | 解放不可の Slab (kB)。増加し続ける場合はカーネルリークの可能性 |
| KernelStack | カーネルスタック使用量 (kB)。スレッド数に比例して増加 |
| PageTables | ページテーブルの使用メモリ (kB) |

**HugePages**

| フィールド | 説明 |
|---|---|
| HugePages_Total | 静的 HugePage の総ページ数 |
| HugePages_Free | 未使用の静的 HugePage 数 |
| AnonHugePages | THP（Transparent HugePages）の使用量 (kB) |

### netstat（netstat_YYYYMMDD.log）
`ss -s` を INTERVAL 秒ごとに実行し TCP 接続状態サマリを記録する。`sar -n DEV` が帯域のみを記録するのに対し、こちらは TCP 状態（estab/timewait/orphaned 等）を補完する。スナップショット間は空行で区切る。

### df（df_YYYYMMDD.log）
`df -hP`（容量）と `df -iP`（inode）を INTERVAL 秒ごとに実行し同一ファイルに記録する。容量セクションと inode セクションは `--- inode ---` マーカー行で区切る。

**容量セクション（df -hP）**

| カラム | 説明 |
|---|---|
| Filesystem | デバイス名またはファイルシステム名 |
| Size | 合計容量 |
| Used | 使用済み容量 |
| Avail | 利用可能容量 |
| Use% | 使用率（%）。85〜90% を超えたら要注意 |
| Mounted on | マウントポイント |

**inode セクション（df -iP）**

| カラム | 説明 |
|---|---|
| Filesystem | デバイス名またはファイルシステム名 |
| Inodes | inode 合計数 |
| IUsed | 使用済み inode 数 |
| IFree | 空き inode 数 |
| IUse% | inode 使用率（%）。小さいファイルを大量生成する用途では容量より先に枯渇することがある |
| Mounted on | マウントポイント |

### fdcount（fdcount_YYYYMMDD.log）
`/proc/sys/fs/file-nr` を INTERVAL 秒ごとに読み取り、システム全体の fd 使用数・最大数を記録する。先頭行にカラムヘッダー（`allocated unused max_open`）を出力する。

### dstate（dstate_YYYYMMDD.log）
`ps -eo pid,ppid,stat,wchan:20,args` をフィルタリングし D 状態（uninterruptible sleep）のプロセスのみを記録する。top と同じ 60 秒間隔のスナップショットだが、D 状態プロセスのみを専用ファイルに集約することで障害調査時に即座に参照できる。`wchan` でどのカーネル関数で待機中かも記録するため、NFS 待機・ジャーナルコミット待機等の原因特定に活用できる。`args` によりフルコマンドパス+引数を記録する。先頭行にカラムヘッダーを出力する。

### connections（connections_YYYYMMDD.log）
`ss -tunap` を INTERVAL 秒ごとに実行し、TCP/UDP の全ソケット情報をプロセス付きで記録する。

| カラム | 説明 |
|---|---|
| Netid | プロトコル（tcp/udp） |
| State | ソケット状態（LISTEN/ESTAB/TIME_WAIT 等） |
| Recv-Q | 受信キューバイト数 |
| Send-Q | 送信キューバイト数 |
| Local Address:Port | ローカルアドレス:ポート |
| Peer Address:Port | 接続先アドレス:ポート（LISTEN時は `*`） |
| Process | プロセス名と PID |

`-a` オプションで LISTEN 状態も含む全ソケットを出力するため、どのプロセスが何番ポートで待受しているかと、確立済み接続の接続先を一括で把握できる。`ss -s`（netstat ログ）のサマリと合わせて参照する。

### lsof（lsof_YYYYMMDD.log）
`lsof -n -P` を INTERVAL 秒ごとに実行し、プロセスごとのオープンファイル一覧を記録する。

- **-n**: DNS 逆引きを行わない（高速化）
- **-P**: ポート番号を名前解決しない（高速化）

主な用途:
- "too many open files" 障害の原因プロセス特定
- 削除済みファイルを保持しているプロセスの発見（ディスク残量が戻らない原因調査）
- ロック中ファイルの確認
- ネットワーク接続のプロセス別詳細確認

> **注意**: lsof の出力は1スナップショットあたり数千〜数万行になる場合がある。日付ローテーション後は gzip 圧縮されるため、長期保持でもディスク消費は抑えられる。

### dmesg（dmesg_YYYYMMDD.log）
`dmesg -w -T` でカーネルのリングバッファ新着メッセージをリアルタイムに追跡する。行頭に収集時刻（gawk 付与）、続いてカーネルイベント発生時刻（`-T` オプション付与）の 2 段のタイムスタンプとなる。OOM Killer 発動・ディスクエラー・ハードウェア障害の記録に使用する。

## 起動時平均の除外

vmstat/iostat/pidstat/mpstat/sar はいずれも起動直後の最初の出力がシステム起動時からの累積平均（since boot）となる。これは実際の計測区間の値ではないため、各コレクターでフィルタリングして除外している。

| コマンド | 除外方法 |
|---|---|
| vmstat | 最初の数値行（count==1）をスキップ |
| iostat | 最初の Device セクション（section==1）をスキップ |
| pidstat | ヘッダーとデータの内部タイムスタンプが一致する間はスキップ（一致=起動時平均） |
| mpstat | 最初の CPU ヘッダーセクション（section==1）をスキップ |
| sar | 最初の IFACE ヘッダーセクション（section==1）をスキップ |

## ログローテーションと圧縮

日付変更時に前日ログを gzip 圧縮することでディスク使用量を削減する。

| ファイル種別 | 説明 |
|---|---|
| `*_YYYYMMDD.log` | 当日収集中のログ（非圧縮・追記中） |
| `*_YYYYMMDD.log.gz` | 前日以前のローテート済みログ（gzip圧縮） |

- **圧縮タイミング**: 日付変更直後（収集プロセス停止後）に `gzip -f` で前日の `.log` を圧縮
- **起動時救済**: サービス再起動時に前日以前の未圧縮 `.log` を圧縮（停止中に溜まった分を救済）
- **自動削除**: `RETENTION_DAYS` 超過の `.log` および `.log.gz` を削除
- **perfmon-save**: `.log` と `.log.gz` の両方を zip に収録

## 動作フロー

1. **起動時**: confファイル読み込み → ログディレクトリ作成 → 前日以前の未圧縮ログを圧縮 → 古いログ削除 → 全収集プロセス起動
2. **通常時**: 60秒間隔でメインループが日付変更を監視
3. **日付変更時**: 収集プロセス停止 → 前日ログを圧縮 → 古いログ削除 → 新しい日付のファイルで収集プロセス再起動
4. **停止時**: SIGTERM を trap → 全子プロセスを kill → wait → 正常終了

## RPMビルド手順

```bash
# ビルド環境セットアップ
sudo yum install -y rpm-build

# ディレクトリ作成（rpmbuild用）
mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# ソースファイルをコピー
cp SOURCES/* ~/rpmbuild/SOURCES/
cp perfmon.spec ~/rpmbuild/SPECS/

# ビルド実行
rpmbuild -bb ~/rpmbuild/SPECS/perfmon.spec
```

ビルド成果物は `~/rpmbuild/RPMS/noarch/perfmon-1.3.2-1.*.noarch.rpm` に出力される。

## インストール・アンインストール

```bash
# インストール
sudo yum localinstall ~/rpmbuild/RPMS/noarch/perfmon-1.3.2-1.*.noarch.rpm

# 稼働確認
systemctl status perfmon

# ログ確認（1分後に実データが記録される）
ls -la /opt/perfmon/log/

# zip保存
perfmon-save

# アンインストール
sudo yum remove perfmon
```

## 運用メモ

- ログは `RETENTION_DAYS`（デフォルト7日）で自動削除される
- 設定変更後は `systemctl restart perfmon` で反映
- `perfmon-save` はいつでも手動実行可能。実行時点の全ログファイルをまとめてzip化する
- zip出力先: `/tmp/perfmon_<HOSTNAME>_<YYYYMMDD_HHMMSS>.zip`
- `%config(noreplace)` により、RPM更新時に既存の設定ファイルは上書きされない
- 各コレクターは起動時平均を自動除外するため、サービス再起動後 INTERVAL 秒後から実データが記録される
