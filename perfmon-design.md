# perfmon 設計ドキュメント

## 概要
Linux (RHEL) 上で CPU/メモリ/ディスクIO などのシステム負荷をプロセス単位含め時系列で記録する常駐ツール。RPMパッケージとして配布する。

## ファイル構成

```
/opt/perfmon/
  bin/
    perfmon-collector.sh   # メイン収集スクリプト（systemdから起動）
  log/
    vmstat_YYYYMMDD.log    # vmstat 出力ログ
    iostat_YYYYMMDD.log    # iostat 出力ログ
    pidstat_YYYYMMDD.log   # pidstat 出力ログ
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
各行の先頭にタイムスタンプを付与。

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
`iostat -dxkt` で拡張統計をデバイス単位で記録。

| カラム | 説明 |
|---|---|
| Device | デバイス名 |
| rrqm/s | 読み取りマージリクエスト/秒 |
| wrqm/s | 書き込みマージリクエスト/秒 |
| r/s | 読み取りリクエスト/秒 |
| w/s | 書き込みリクエスト/秒 |
| rkB/s | 読み取りKB/秒 |
| wkB/s | 書き込みKB/秒 |
| avgrq-sz | 平均リクエストサイズ(セクタ) |
| avgqu-sz | 平均キュー長 |
| await | 平均IO待ち時間(ms) |
| r_await | 平均読み取りIO待ち時間(ms) |
| w_await | 平均書き込みIO待ち時間(ms) |
| svctm | 平均サービス時間(ms) |
| %util | デバイス使用率% |

### pidstat（pidstat_YYYYMMDD.log）
`pidstat -u -r -d` でプロセス単位のCPU/メモリ/ディスクIOを記録。

- **-u**: CPU使用率（%usr, %system, %guest, %wait, %CPU）
- **-r**: メモリ使用率（minflt/s, majflt/s, VSZ, RSS, %MEM）
- **-d**: ディスクIO（kB_rd/s, kB_wr/s, kB_ccwr/s, iodelay）

## 動作フロー

1. **起動時**: confファイル読み込み → ログディレクトリ作成 → 古いログ削除 → 収集プロセス起動
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
cp /home/hijiri/perfmon/SOURCES/* ~/rpmbuild/SOURCES/

# ビルド実行
rpmbuild -bb /home/hijiri/perfmon/perfmon.spec
```

ビルド成果物は `~/rpmbuild/RPMS/noarch/perfmon-1.0.0-1.*.noarch.rpm` に出力される。

## インストール・アンインストール

```bash
# インストール
sudo yum localinstall ~/rpmbuild/RPMS/noarch/perfmon-1.0.0-1.*.noarch.rpm

# 稼働確認
systemctl status perfmon

# ログ確認
ls -la /opt/perfmon/log/

# zip保存
perfmon-save

# アンインストール
sudo yum remove perfmon
```

## 運用メモ

- ログは `RETENTION_DAYS`（デフォルト7日）で自動削除される
- 設定変更後は `systemctl restart perfmon` で反映
- `perfmon-save` はいつでも手動実行可能。実行時点のログファイルをまとめてzip化する
- zip出力先: `/tmp/perfmon_<HOSTNAME>_<YYYYMMDD_HHMMSS>.zip`
- `%config(noreplace)` により、RPM更新時に既存の設定ファイルは上書きされない
