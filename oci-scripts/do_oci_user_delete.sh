#!/usr/bin/bash
set -eu

# 使い方: bash do_oci_user_delete.sh <ユーザー名> [OCIプロファイル名]
# 例:     bash do_oci_user_delete.sh tanaka.taro
#         bash do_oci_user_delete.sh tanaka.taro prod

LOG="/home/hijiri/claude2026001/do_oci_user_delete_$(date +%Y%m%d_%H%M%S).log"
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
# [1/4] テナンシーID取得
# ─────────────────────────────────────────
echo "=== [1/4] テナンシーID取得 ==="
TENANCY_ID=$(awk -v profile="${OCI_PROFILE}" '
  $0 ~ "\\[" profile "\\]" { found=1; next }
  found && /^\[/ { found=0 }
  found && /^tenancy=/ { print substr($0, 9); exit }
' /root/.oci/config | tr -d ' \r')

if [ -z "${TENANCY_ID}" ]; then
  echo "ERROR: プロファイル '${OCI_PROFILE}' が /root/.oci/config に見つかりません"
  exit 1
fi
echo "テナンシーID: ${TENANCY_ID}"

# ─────────────────────────────────────────
# [2/4] ユーザーID取得
# ─────────────────────────────────────────
echo "=== [2/4] ユーザーID取得 (${USERNAME}) ==="
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
# [3/4] グループメンバーシップ削除
# ─────────────────────────────────────────
echo "=== [3/4] グループメンバーシップ削除 ==="
MEMBERSHIPS=$(oci iam user list-groups \
  --profile "${OCI_PROFILE}" \
  --user-id "${USER_ID}" \
  --query 'data[*].id' \
  --output json | python3 -c "import sys,json; data=sys.stdin.read().strip(); [print(i) for i in (json.loads(data) if data else [])]")

if [ -z "${MEMBERSHIPS}" ]; then
  echo "グループメンバーシップなし"
else
  while IFS= read -r MEMBERSHIP_ID; do
    [ -z "${MEMBERSHIP_ID}" ] && continue
    oci iam group remove-user \
      --profile "${OCI_PROFILE}" \
      --group-id "" \
      --user-id "${USER_ID}" 2>/dev/null || \
    oci iam user-group-membership delete \
      --profile "${OCI_PROFILE}" \
      --user-group-membership-id "${MEMBERSHIP_ID}" \
      --force
    echo "メンバーシップ削除: ${MEMBERSHIP_ID}"
  done <<< "${MEMBERSHIPS}"
fi

# ─────────────────────────────────────────
# [4/4] ユーザー削除
# ─────────────────────────────────────────
echo "=== [4/4] ユーザー削除 ==="
oci iam user delete \
  --profile "${OCI_PROFILE}" \
  --user-id "${USER_ID}" \
  --force

echo ""
echo "========================================"
echo "  ユーザー削除完了！"
echo "  ユーザー名 : ${USERNAME}"
echo "  ユーザーID : ${USER_ID}"
echo "========================================"

echo "=== 完了: ログを Claude に渡す場合は $LOG を共有 ==="
