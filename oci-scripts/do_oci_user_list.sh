#!/usr/bin/bash
set -eu

# 使い方: bash do_oci_user_list.sh [OCIプロファイル名]
# 例:     bash do_oci_user_list.sh
#         bash do_oci_user_list.sh prod

LOG="/home/hijiri/claude2026001/do_oci_user_list_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
echo "=== ログ出力先: $LOG ==="

OCI_PROFILE="${1:-DEFAULT}"

echo "=== パラメータ ==="
echo "  OCIプロファイル : ${OCI_PROFILE}"

# ─────────────────────────────────────────
# [1/2] テナンシーID取得
# ─────────────────────────────────────────
echo "=== [1/2] テナンシーID取得 ==="
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
# [2/2] ユーザー一覧取得
# ─────────────────────────────────────────
echo "=== [2/2] ユーザー一覧 ==="
oci iam user list \
  --profile "${OCI_PROFILE}" \
  --compartment-id "${TENANCY_ID}" \
  --all \
  --query 'data[*].{Name:name, State:"lifecycle-state", Blocked:"is-blocked", MFA:"is-mfa-activated", Created:"time-created"}' \
  --output table

echo "=== 完了: ログを Claude に渡す場合は $LOG を共有 ==="
