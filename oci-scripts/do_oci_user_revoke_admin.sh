#!/usr/bin/bash
set -eu

# 使い方: bash do_oci_user_revoke_admin.sh <ユーザー名> [OCIプロファイル名]
# 例:     bash do_oci_user_revoke_admin.sh tanaka.taro
#         bash do_oci_user_revoke_admin.sh tanaka.taro prod

LOG="/home/hijiri/claude2026001/do_oci_user_revoke_admin_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
echo "=== ログ出力先: $LOG ==="

if [ "${#}" -lt 1 ]; then
  echo "使い方: $0 <ユーザー名> [OCIプロファイル名]"
  exit 1
fi

USERNAME="${1}"
OCI_PROFILE="${2:-DEFAULT}"
ADMIN_GROUP="administrator"
READONLY_GROUP="readonly"

echo "=== パラメータ ==="
echo "  ユーザー名      : ${USERNAME}"
echo "  OCIプロファイル : ${OCI_PROFILE}"
echo "  除外グループ    : ${ADMIN_GROUP}"

# ─────────────────────────────────────────
# [1/4] テナンシーID & Domain URL 取得
# ─────────────────────────────────────────
echo "=== [1/4] テナンシーID & Domain URL 取得 ==="
TENANCY_ID=$(awk -v profile="${OCI_PROFILE}" '
  $0 ~ "\\[" profile "\\]" { found=1; next }
  found && /^\[/ { found=0 }
  found && /^tenancy=/ { print substr($0, 9); exit }
' /root/.oci/config | tr -d ' \r')

if [ -z "${TENANCY_ID}" ]; then
  echo "ERROR: プロファイル '${OCI_PROFILE}' が /root/.oci/config に見つかりません"
  exit 1
fi

DOMAIN_URL=$(oci iam domain list \
  --profile "${OCI_PROFILE}" \
  --compartment-id "${TENANCY_ID}" \
  --query 'data[0].url' \
  --raw-output | sed 's|:443$||')
echo "Domain URL: ${DOMAIN_URL}"

# ─────────────────────────────────────────
# [2/4] ユーザーID取得 & administrator所属確認
# ─────────────────────────────────────────
echo "=== [2/4] ユーザー確認 & グループ所属チェック ==="
USER_DATA=$(oci identity-domains user list \
  --endpoint "${DOMAIN_URL}" \
  --profile "${OCI_PROFILE}" \
  --filter "userName eq \"${USERNAME}\"")

USER_ID=$(echo "${USER_DATA}" | python3 -c "
import sys,json
d=json.load(sys.stdin)
resources=d.get('Resources',[])
if not resources:
    print('')
else:
    print(resources[0]['id'])
")

if [ -z "${USER_ID}" ]; then
  echo "ERROR: ユーザー '${USERNAME}' が見つかりません"
  exit 1
fi
echo "ユーザーID: ${USER_ID}"

# administrator グループ所属確認
ADMIN_CHECK=$(oci identity-domains group list \
  --endpoint "${DOMAIN_URL}" \
  --profile "${OCI_PROFILE}" \
  --filter "displayName eq \"${ADMIN_GROUP}\" and members.value eq \"${USER_ID}\"")

ADMIN_COUNT=$(echo "${ADMIN_CHECK}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('totalResults',0))")

if [ "${ADMIN_COUNT}" = "0" ]; then
  echo "INFO: ユーザー '${USERNAME}' は既に '${ADMIN_GROUP}' グループに所属していません"
  exit 0
fi

# ─────────────────────────────────────────
# [3/4] administrator グループID取得
# ─────────────────────────────────────────
echo "=== [3/4] グループID取得 (${ADMIN_GROUP}) ==="
GROUP_DATA=$(oci identity-domains group list \
  --endpoint "${DOMAIN_URL}" \
  --profile "${OCI_PROFILE}" \
  --filter "displayName eq \"${ADMIN_GROUP}\"")

ADMIN_GROUP_ID=$(echo "${GROUP_DATA}" | python3 -c "
import sys,json
d=json.load(sys.stdin)
resources=d.get('Resources',[])
if not resources:
    print('')
else:
    print(resources[0]['id'])
")

if [ -z "${ADMIN_GROUP_ID}" ]; then
  echo "ERROR: グループ '${ADMIN_GROUP}' が見つかりません"
  exit 1
fi
echo "グループID: ${ADMIN_GROUP_ID}"

# ─────────────────────────────────────────
# [4/4] administrator グループから除外
# ─────────────────────────────────────────
echo "=== [4/4] '${ADMIN_GROUP}' グループから除外 ==="
oci identity-domains group patch \
  --endpoint "${DOMAIN_URL}" \
  --profile "${OCI_PROFILE}" \
  --group-id "${ADMIN_GROUP_ID}" \
  --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' \
  --operations "[{\"op\":\"remove\",\"path\":\"members[value eq \\\"${USER_ID}\\\"]\"}]"

echo ""
echo "========================================"
echo "  administrator 権限剥奪完了！"
echo "  ユーザー名 : ${USERNAME}"
echo "  所属グループ: ${READONLY_GROUP} のみ"
echo "========================================"

echo "=== 完了: ログを Claude に渡す場合は $LOG を共有 ==="
