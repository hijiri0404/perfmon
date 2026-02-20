# perfmon — Linux システムパフォーマンス監視ツール

Linux (RHEL) 上で CPU/メモリ/ディスクIO などのシステム負荷をプロセス単位含め時系列で記録する常駐ツール。
RPMパッケージとして配布可能。

## ファイル構成

```
perfmon/
├── README.md                  # 本ファイル
├── perfmon.spec               # RPM SPECファイル
├── perfmon-design.md          # 詳細設計ドキュメント（引き継ぎ用）
└── SOURCES/
    ├── perfmon-collector.sh   # 収集スクリプト本体（vmstat/iostat/pidstat）
    ├── perfmon-save.sh        # ログzip圧縮コマンド
    ├── perfmon.conf           # 設定ファイル
    └── perfmon.service        # systemd ユニットファイル
```

## 前提条件

- RHEL 7 以降（systemd 環境）
- 必要パッケージ: `sysstat`, `gawk`, `zip`（RPM依存関係で自動インストール）
- ビルド時: `rpm-build`

## RPM ビルド手順（RHEL上で実施）

```bash
# 1. ビルドツールをインストール
sudo yum install -y rpm-build

# 2. rpmbuild ディレクトリを作成
mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# 3. ソースファイルをコピー
cp SOURCES/* ~/rpmbuild/SOURCES/

# 4. RPM ビルド
rpmbuild -bb perfmon.spec
```

成果物: `~/rpmbuild/RPMS/noarch/perfmon-1.0.0-1.*.noarch.rpm`

## インストール・運用

```bash
# インストール（依存パッケージも自動解決）
sudo yum localinstall ~/rpmbuild/RPMS/noarch/perfmon-1.0.0-1.*.noarch.rpm

# 稼働確認
systemctl status perfmon

# ログ確認（1分後に生成される）
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
| vmstat_YYYYMMDD.log | `vmstat` | CPU/メモリ/swap/IO 全体統計 |
| iostat_YYYYMMDD.log | `iostat -dxkt` | デバイス単位のディスクIO統計 |
| pidstat_YYYYMMDD.log | `pidstat -u -r -d` | プロセス単位のCPU/メモリ/ディスクIO |

全行にタイムスタンプ付与。日付変更時にファイル自動切り替え。

## 開発経緯メモ

- Ubuntu 22.04 上で開発・ビルド検証を実施
- `%{_unitdir}` マクロが Ubuntu の rpm では未定義だったため、systemd パスを `/usr/lib/systemd/system` に直接指定
- `%systemd_post` 等のマクロも同様に直接 systemctl コマンドに置換
- RHEL 上での RPM ビルド・インストール・動作確認は未実施（次のステップ）

## 検証チェックリスト（RHEL上で実施）

- [ ] `rpmbuild -bb perfmon.spec` でビルド成功
- [ ] `yum localinstall` でインストール → サービス自動起動
- [ ] `systemctl status perfmon` で稼働確認
- [ ] 1分後にログファイルが生成されている
- [ ] `perfmon-save` でzipファイル生成
- [ ] `yum remove perfmon` でクリーンにアンインストール
