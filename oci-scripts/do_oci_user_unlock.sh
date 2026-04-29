#!/usr/bin/bash
set -eu

# 使い方: bash do_oci_user_unlock.sh <ユーザー名> [OCIプロファイル名]
# 例:     bash do_oci_user_unlock.sh tanaka.taro
#         bash do_oci_user_unlock.sh tanaka.taro prod

LOG="/home/hijiri/claude2026001/do_oci_user_unlock_$(date +%Y%m%d_%H%M%S).log"
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
# [2/3] ユーザーID取得 & 現在の状態確認
# ─────────────────────────────────────────
echo "=== [2/3] ユーザー確認 (${USERNAME}) ==="
USER_INFO=$(oci iam user list \
  --profile "${OCI_PROFILE}" \
  --compartment-id "${TENANCY_ID}" \
  --name "${USERNAME}" \
  --query 'data[0].{id:id, blocked:"is-blocked"}' \
  --output json 2>/dev/null || echo "")

USER_ID=$(echo "${USER_INFO}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || true)
IS_BLOCKED=$(echo "${USER_INFO}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('blocked',''))" 2>/dev/null || true)

if [ -z "${USER_ID}" ] || [ "${USER_ID}" = "None" ]; then
  echo "ERROR: ユーザー '${USERNAME}' が見つかりません"
  exit 1
fi
echo "ユーザーID  : ${USER_ID}"
echo "ロック状態  : ${IS_BLOCKED}"

if [ "${IS_BLOCKED}" = "False" ]; then
  echo "INFO: ユーザー '${USERNAME}' はロックされていません"
  exit 0
fi

# ─────────────────────────────────────────
# [3/3] アカウントロック解除
# ─────────────────────────────────────────
echo "=== [3/3] アカウントロック解除 ==="
oci iam user update \
  --profile "${OCI_PROFILE}" \
  --user-id "${USER_ID}" \
  --blocked false \
  --force \
  --query 'data.{Name:name, Blocked:"is-blocked", State:"lifecycle-state"}' \
  --output table

echo ""
echo "========================================"
echo "  アカウントロック解除完了！"
echo "  ユーザー名 : ${USERNAME}"
echo "========================================"

echo "=== 完了: ログを Claude に渡す場合は $LOG を共有 ==="
