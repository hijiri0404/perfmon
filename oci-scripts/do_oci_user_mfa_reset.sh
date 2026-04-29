#!/usr/bin/bash
set -eu

# 使い方: bash do_oci_user_mfa_reset.sh <ユーザー名> [OCIプロファイル名]
# 例:     bash do_oci_user_mfa_reset.sh tanaka.taro
#         bash do_oci_user_mfa_reset.sh tanaka.taro prod
# ※ MFAデバイスを削除し、次回ログイン時に再登録を促す

LOG="/home/hijiri/claude2026001/do_oci_user_mfa_reset_$(date +%Y%m%d_%H%M%S).log"
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
# [2/3] ユーザーID取得 & MFAデバイス確認
# ─────────────────────────────────────────
echo "=== [2/3] ユーザー確認 & MFAデバイス検索 (${USERNAME}) ==="
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

DEVICE_IDS=$(oci iam mfa-totp-device list \
  --profile "${OCI_PROFILE}" \
  --user-id "${USER_ID}" \
  --query 'data[*].id' \
  --output json | python3 -c "import sys,json; data=sys.stdin.read().strip(); [print(i) for i in (json.loads(data) if data else [])]")

if [ -z "${DEVICE_IDS}" ]; then
  echo "INFO: ユーザー '${USERNAME}' にMFAデバイスが登録されていません"
  exit 0
fi

COUNT=$(echo "${DEVICE_IDS}" | wc -l | tr -d ' ')
echo "登録済みMFAデバイス: ${COUNT}件"

# ─────────────────────────────────────────
# [3/3] MFAデバイス削除
# ─────────────────────────────────────────
echo "=== [3/3] MFAデバイス削除 ==="
while IFS= read -r DEVICE_ID; do
  [ -z "${DEVICE_ID}" ] && continue
  echo "--- 削除中: ${DEVICE_ID} ---"
  oci iam mfa-totp-device delete \
    --profile "${OCI_PROFILE}" \
    --user-id "${USER_ID}" \
    --mfa-totp-device-id "${DEVICE_ID}" \
    --force
  echo "削除完了"
done <<< "${DEVICE_IDS}"

echo ""
echo "========================================"
echo "  MFAデバイス削除完了！"
echo "  ユーザー名 : ${USERNAME}"
echo "  ※ 次回ログイン時にMFAデバイスの再登録が必要"
echo "========================================"

echo "=== 完了: ログを Claude に渡す場合は $LOG を共有 ==="
