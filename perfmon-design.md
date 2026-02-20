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

### iostat（iostat_YYYYMMDD.log）
`iostat -dxkt INTERVAL` で拡張統計をデバイス単位で記録。各行にタイムスタンプを付与。

| カラム | 説明 |
|---|---|
| Device | デバイス名 |
| r/s | 読み取りリクエスト/秒 |
| w/s | 書き込みリクエスト/秒 |
| rkB/s | 読み取りKB/秒 |
| wkB/s | 書き込みKB/秒 |
| rrqm/s | 読み取りマージリクエスト/秒 |
| wrqm/s | 書き込みマージリクエスト/秒 |
| r_await | 平均読み取りIO待ち時間(ms) |
| w_await | 平均書き込みIO待ち時間(ms) |
| aqu-sz | 平均キュー長 |
| %util | デバイス使用率% |

### pidstat（pidstat_YYYYMMDD.log）
`pidstat -u -r -d INTERVAL` でプロセス単位のCPU/メモリ/ディスクIOを記録。

- **-u**: CPU使用率（%usr, %system, %guest, %wait, %CPU）
- **-r**: メモリ使用率（minflt/s, majflt/s, VSZ, RSS, %MEM）
- **-d**: ディスクIO（kB_rd/s, kB_wr/s, kB_ccwr/s, iodelay）

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
| %sys | システムCPU% |
| %iowait | IO待ちCPU% |
| %irq | ハードウェア割り込みCPU% |
| %soft | ソフトウェア割り込みCPU% |
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
| %ifutil | インタフェース使用率% |

### top（top_YYYYMMDD.log）
`top -b -d INTERVAL` でシステム概要とプロセス一覧をスナップショット形式で記録。各スナップショットの先頭に `=== YYYY-MM-DD HH:MM:SS ===` の区切り行を付与。

## 起動時平均の除外

vmstat/iostat/pidstat/mpstat/sar はいずれも起動直後の最初の出力がシステム起動時からの累積平均（since boot）となる。これは実際の計測区間の値ではないため、各コレクターでフィルタリングして除外している。

| コマンド | 除外方法 |
|---|---|
| vmstat | 最初の数値行（count==1）をスキップ |
| iostat | 最初の Device セクション（section==1）をスキップ |
| pidstat | ヘッダーとデータの内部タイムスタンプが一致する間はスキップ（一致=起動時平均） |
| mpstat | 最初の CPU ヘッダーセクション（section==1）をスキップ |
| sar | 最初の IFACE ヘッダーセクション（section==1）をスキップ |

## 動作フロー

1. **起動時**: confファイル読み込み → ログディレクトリ作成 → 古いログ削除 → 全収集プロセス起動
2. **通常時**: 60秒間隔でメインループが日付変更を監視
3. **日付変更時**: 収集プロセス停止 → 古いログ削除 → 新しい日付のファイルで収集プロセス再起動
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

ビルド成果物は `~/rpmbuild/RPMS/noarch/perfmon-1.1.0-1.*.noarch.rpm` に出力される。

## インストール・アンインストール

```bash
# インストール
sudo yum localinstall ~/rpmbuild/RPMS/noarch/perfmon-1.1.0-1.*.noarch.rpm

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
