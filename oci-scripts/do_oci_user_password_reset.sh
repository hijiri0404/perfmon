#!/usr/bin/bash
set -eu

# 使い方: bash do_oci_user_password_reset.sh <ユーザー名> [OCIプロファイル名]
# 例:     bash do_oci_user_password_reset.sh tanaka.taro
#         bash do_oci_user_password_reset.sh tanaka.taro prod
# ※ OCI仕様: パスワードはランダム生成。初回ログイン時に変更強制。

LOG="/home/hijiri/claude2026001/do_oci_user_password_reset_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
echo "=== ログ出力先: $LOG ==="

if [ "${#}" -lt 1 ]; then
  echo "使い方: $0 <ユーザー名> [OCIプロファイル名]"
  exit 1
fi

USERNAME="${1}"
OCI_PROFILE="${2:-DEFAULT}"

echo "=== パラメータ ==="
echo "  ユーザー名      : ${USERNAME}"
echo "  OCIプロファイル : ${OCI_PROFILE}"

# ─────────────────────────────────────────
# [1/3] テナンシーID取得
# ─────────────────────────────────────────
echo "=== [1/3] テナンシーID取得 ==="
TENANCY_ID=$(awk -v profile="${OCI_PROFILE}" '
  $0 ~ "\\[" profile "\\]" { found=1; next }
  found && /^\[/ { found=0 }
  found && /^tenancy=/ { print substr($0, 9); exit }
' /root/.oci/config | tr -d ' \r')

if [ -z "${TENANCY_ID}" ]; then
  echo "ERROR: プロファイル '${OCI_PROFILE}' が /root/.oci/config に見つかりません"
  exit 1
fi

# ─────────────────────────────────────────
# [2/3] ユーザーID取得
# ─────────────────────────────────────────
echo "=== [2/3] ユーザーID取得 (${USERNAME}) ==="
USER_ID=$(oci iam user list \
  --profile "${OCI_PROFILE}" \
  --compartment-id "${TENANCY_ID}" \
  --name "${USERNAME}" \
  --query 'data[0].id' \
  --raw-output 2>/dev/null || true)

if [ -z "${USER_ID}" ] || [ "${USER_ID}" = "null" ]; then
  echo "ERROR: ユーザー '${USERNAME}' が見つかりません"
  exit 1
fi
echo "ユーザーID: ${USER_ID}"

# ─────────────────────────────────────────
# [3/3] パスワードリセット
# ─────────────────────────────────────────
echo "=== [3/3] コンソールパスワードリセット ==="
TEMP_PASSWORD=$(oci iam user ui-password create-or-reset \
  --profile "${OCI_PROFILE}" \
  --user-id "${USER_ID}" \
  --query 'data.password' \
  --raw-output)

echo ""
echo "========================================"
echo "  パスワードリセット完了！"
echo "  ユーザー名     : ${USERNAME}"
echo "  新しいパスワード: ${TEMP_PASSWORD}"
echo "  ※ 初回ログイン時にパスワード変更が必要"
echo "========================================"

echo "=== 完了: ログを Claude に渡す場合は $LOG を共有 ==="
