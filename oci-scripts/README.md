# OCI 運用スクリプト集

OCI CLI を使った運用自動化スクリプトです。
実行環境: root ユーザー / OCI CLI インストール済み / `/root/.oci/config` に profile 設定済み

---

## 前提条件

- OCI CLI がインストールされていること（root で実行可能）
- `/root/.oci/config` に profile が設定されていること
- Identity Domain を使用している環境

### profile の設定例 (`/root/.oci/config`)

```ini
[DEFAULT]
tenancy=ocid1.tenancy.oc1..xxxxx
user=ocid1.user.oc1..xxxxx
fingerprint=xx:xx:xx:xx
key_file=/root/.oci/oci_api_key.pem
region=ap-tokyo-1

[prod]
tenancy=ocid1.tenancy.oc1..yyyyy
user=ocid1.user.oc1..yyyyy
fingerprint=yy:yy:yy:yy
key_file=/root/.oci/prod_api_key.pem
region=ap-tokyo-1
```

---

## コンピュートインスタンス管理

### インスタンス起動

```bash
bash do_oci_start.sh <インスタンス名> <コンパートメント名> [profile名]
```

| 引数 | 説明 | 省略 |
|------|------|------|
| インスタンス名 | 起動対象インスタンスの表示名 | 必須 |
| コンパートメント名 | インスタンスが属するコンパートメント名 | 必須 |
| profile名 | `/root/.oci/config` のプロファイル名 | 省略時: `DEFAULT` |

```bash
# 例
bash do_oci_start.sh claude-instance-01 dev
bash do_oci_start.sh claude-instance-01 dev prod
```

- STOPPED 状態のインスタンスを検索して起動
- 同名インスタンスが複数ある場合は全て起動
- 既に RUNNING の場合は何もせず終了

---

### インスタンス停止

```bash
bash do_oci_stop.sh <インスタンス名> <コンパートメント名> [profile名]
```

```bash
# 例
bash do_oci_stop.sh claude-instance-01 dev
bash do_oci_stop.sh claude-instance-01 dev prod
```

- RUNNING 状態のインスタンスを検索して停止
- 同名インスタンスが複数ある場合は全て停止
- 既に STOPPED の場合は何もせず終了

---

## IAM ユーザー管理（Identity Domain）

> **注意**: これらのスクリプトは OCI Identity Domain 環境に対応しています。

### ユーザー一覧取得

```bash
bash do_oci_user_list.sh [profile名]
```

```bash
# 例
bash do_oci_user_list.sh
bash do_oci_user_list.sh prod
```

- 全ユーザーの名前・状態・ロック状態・MFA有無を表示

---

### ユーザー作成

```bash
bash do_oci_user_create.sh <ユーザー名> <メールアドレス> [profile名]
```

```bash
# 例
bash do_oci_user_create.sh tanaka.taro tanaka@example.com
bash do_oci_user_create.sh tanaka.taro tanaka@example.com prod
```

- ユーザーを作成し `readonly` グループへ追加
- 作成後、アクティベーションメールが登録メールアドレスへ送信される
- ユーザーはメール内のリンクからパスワードを設定する

---

### ユーザー削除

```bash
bash do_oci_user_delete.sh <ユーザー名> [profile名]
```

```bash
# 例
bash do_oci_user_delete.sh tanaka.taro
bash do_oci_user_delete.sh tanaka.taro prod
```

- グループメンバーシップを全て削除してからユーザーを削除

---

### パスワードリセット

```bash
bash do_oci_user_password_reset.sh <ユーザー名> [profile名]
```

```bash
# 例
bash do_oci_user_password_reset.sh tanaka.taro
```

> **OCI 仕様**: パスワードはランダム生成。初回ログイン時に変更強制。

---

### アカウントロック解除

```bash
bash do_oci_user_unlock.sh <ユーザー名> [profile名]
```

```bash
# 例
bash do_oci_user_unlock.sh tanaka.taro
```

- コンソールパスワードを 10 回連続で間違えるとアカウントがロックされる
- このスクリプトでロックを解除する
- 既にロック解除済みの場合は何もせず終了

---

### MFA 再登録

```bash
bash do_oci_user_mfa_reset.sh <ユーザー名> [profile名]
```

```bash
# 例
bash do_oci_user_mfa_reset.sh tanaka.taro
```

- 登録済みの MFA デバイス（TOTP）を削除する
- 次回ログイン時にユーザーが MFA デバイスを再登録する
- MFA 未登録の場合は何もせず終了

---

### administrator 権限付与

```bash
bash do_oci_user_grant_admin.sh <ユーザー名> [profile名]
```

```bash
# 例
bash do_oci_user_grant_admin.sh tanaka.taro
```

- `readonly` グループに所属しているユーザーを `administrator` グループにも追加する
- `readonly` のメンバーシップは維持される
- 既に `administrator` に所属している場合は何もせず終了

---

### administrator 権限剥奪

```bash
bash do_oci_user_revoke_admin.sh <ユーザー名> [profile名]
```

```bash
# 例
bash do_oci_user_revoke_admin.sh tanaka.taro
```

- `administrator` グループからユーザーを除外する
- `readonly` のメンバーシップは維持される
- 既に `administrator` に所属していない場合は何もせず終了

---

## ログについて

各スクリプトはログファイルを自動生成します。

```
do_oci_<操作名>_YYYYMMDD_HHMMSS.log
```

ログは画面と同時にファイルへ出力されるため、実行結果を後から確認・共有できます。
