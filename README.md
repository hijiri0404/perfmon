# perfmon — Linux システムパフォーマンス監視ツール

Linux (RHEL) 上で CPU/メモリ/ディスクIO/ネットワークなどのシステム負荷をプロセス単位含め時系列で記録する常駐ツール。
RPMパッケージとして配布可能。

## ファイル構成

```
perfmon/
├── README.md                  # 本ファイル
├── perfmon.spec               # RPM SPECファイル
├── perfmon-design.md          # 詳細設計ドキュメント（引き継ぎ用）
└── SOURCES/
    ├── perfmon-collector.sh   # 収集スクリプト本体
    ├── perfmon-save.sh        # ログzip圧縮コマンド
    ├── perfmon.conf           # 設定ファイル
    └── perfmon.service        # systemd ユニットファイル
```

## 前提条件

- RHEL 7 以降（systemd 環境）
- 必要パッケージ: `sysstat`, `gawk`, `zip`, `lsof`（RPM依存関係で自動インストール）
- ビルド時: `rpm-build`

## インストール（ビルド済みRPM）

GitHub Releases からビルド済み RPM を直接インストールできる。

```bash
curl -LO https://github.com/hijiri0404/perfmon/releases/download/v1.3.1/perfmon-1.3.1-1.el10.noarch.rpm
sudo yum localinstall -y perfmon-1.3.0-1.el10.noarch.rpm
```

> **注意**: el10 ビルドは AlmaLinux/RHEL 10 向け。他のバージョンはソースから RPM を再ビルドすること。

## RPM ビルド手順（RHEL上で実施）

```bash
# 1. ビルドツールをインストール
sudo yum install -y rpm-build

# 2. rpmbuild ディレクトリを作成
mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# 3. ソースファイルをコピー
cp SOURCES/* ~/rpmbuild/SOURCES/
cp perfmon.spec ~/rpmbuild/SPECS/

# 4. RPM ビルド
rpmbuild -bb ~/rpmbuild/SPECS/perfmon.spec
```

成果物: `~/rpmbuild/RPMS/noarch/perfmon-1.3.1-1.*.noarch.rpm`

## インストール・運用

```bash
# インストール（依存パッケージも自動解決）
sudo yum localinstall ~/rpmbuild/RPMS/noarch/perfmon-1.3.1-1.*.noarch.rpm

# 稼働確認
systemctl status perfmon

# ログ確認（1分後に実データが記録される）
ls -la /opt/perfmon/log/

# ログをzip保存
perfmon-save
# → /tmp/perfmon_<HOSTNAME>_<YYYYMMDD_HHMMSS>.zip

# アンインストール
sudo yum remove perfmon
```

## 設定（/etc/perfmon/perfmon.conf）

| パラメータ | デフォルト | 説明 |
|---|---|---|
| INTERVAL | 60 | 収集間隔（秒） |
| RETENTION_DAYS | 7 | ログ保持日数（超過分は自動削除） |
| LOG_DIR | /opt/perfmon/log | ログ出力先 |

設定変更後は `sudo systemctl restart perfmon` で反映。
`%config(noreplace)` により RPM 更新時に既存設定は上書きされない。

## 収集内容

| ログファイル | コマンド | 内容 |
|---|---|---|
| vmstat_YYYYMMDD.log | `vmstat -n` | CPU/メモリ/swap/IO 全体統計。カラムヘッダー付き |
| iostat_YYYYMMDD.log | `iostat -dxkt` | デバイス単位のディスクIO統計 |
| pidstat_YYYYMMDD.log | `pidstat -u -r -d -l` | プロセス単位のCPU/メモリ/ディスクIO（フルコマンドライン付き） |
| mpstat_YYYYMMDD.log | `mpstat -P ALL` | CPU コア別使用率 |
| sar_net_YYYYMMDD.log | `sar -n DEV` | ネットワークインタフェース統計 |
| top_YYYYMMDD.log | `top -b -c -w 512` | システム概要とプロセス一覧（フルコマンドライン・行幅512） |
| meminfo_YYYYMMDD.log | `/proc/meminfo` | 詳細メモリ情報（Slab/HugePages/Dirty/CommitLimit 等） |
| netstat_YYYYMMDD.log | `ss -s` | TCP接続状態サマリ（estab/timewait/orphaned 等） |
| df_YYYYMMDD.log | `df -hP` / `df -iP` | ファイルシステム別ディスク容量・inode使用率 |
| fdcount_YYYYMMDD.log | `/proc/sys/fs/file-nr` | システム全体のファイルディスクリプタ数 |
| dstate_YYYYMMDD.log | `ps` D状態フィルタ | D状態プロセス（PID/PPID/wchan/フルコマンド付き） |
| connections_YYYYMMDD.log | `ss -tunap` | TCP/UDP全ソケット一覧（LISTEN含む、プロセス付き） |
| lsof_YYYYMMDD.log | `lsof -n -P` | プロセス別オープンファイル一覧 |
| dmesg_YYYYMMDD.log | `dmesg -w -T` | カーネルメッセージ（OOM/ディスクエラー/HW障害） |

全行に収集タイムスタンプを付与。起動直後の起動時平均（since boot）は除外し、最初の計測区間から記録する。日付変更時にファイル自動切り替え。

### pidstat のタイムスタンプについて

pidstat ログの各行には収集タイムスタンプ（gawk付与）と pidstat 内部タイムスタンプの2つが含まれる。

```
2026-02-20 22:26:24  22:25:24  UID  PID  ...  ← ヘッダー（内部TSは区間開始時刻）
2026-02-20 22:26:24  22:26:24    0    1  ...  ← データ（内部TSは区間終了時刻）
```

ヘッダーの内部タイムスタンプが区間開始、データ行が区間終了を示すため、1分ずれるのは正常な仕様。

## 開発経緯メモ

- AlmaLinux 10 上でビルド・動作確認済み
- `%{_unitdir}` マクロが一部環境で未定義のため、systemd パスを `/usr/lib/systemd/system` に直接指定
- `%systemd_post` 等のマクロも同様に直接 systemctl コマンドに置換

## 検証チェックリスト

- [x] `rpmbuild -bb perfmon.spec` でビルド成功
- [x] `yum localinstall` でインストール → サービス自動起動
- [x] `systemctl status perfmon` で稼働確認
- [x] 1分後にログファイル（14種）が生成されている
- [x] 起動時平均が除外され、計測区間データのみ記録されている
- [x] `perfmon-save` でzipファイル生成
- [x] 日付変更時に新しいファイルへ切り替わる（日付ローテーション）
- [ ] `yum remove perfmon` でクリーンにアンインストール
