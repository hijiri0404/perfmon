#!/usr/bin/bash
set -eu

# 使い方: bash do_oci_user_create.sh <ユーザー名> <メールアドレス> [OCIプロファイル名]
# 例:     bash do_oci_user_create.sh tanaka.taro tanaka@example.com
#         bash do_oci_user_create.sh tanaka.taro tanaka@example.com prod

LOG="/home/hijiri/claude2026001/do_oci_user_create_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
echo "=== ログ出力先: $LOG ==="

if [ "${#}" -lt 2 ]; then
  echo "使い方: $0 <ユーザー名> <メールアドレス> [OCIプロファイル名]"
  exit 1
fi

USERNAME="${1}"
EMAIL="${2}"
OCI_PROFILE="${3:-DEFAULT}"
READONLY_GROUP="readonly"

echo "=== パラメータ ==="
echo "  ユーザー名      : ${USERNAME}"
echo "  メールアドレス  : ${EMAIL}"
echo "  OCIプロファイル : ${OCI_PROFILE}"
echo "  追加グループ    : ${READONLY_GROUP}"

# ─────────────────────────────────────────
# [1/5] テナンシーID & Domain URL 取得
# ─────────────────────────────────────────
echo "=== [1/5] テナンシーID & Domain URL 取得 ==="
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

DOMAIN_URL=$(oci iam domain list \
  --profile "${OCI_PROFILE}" \
  --compartment-id "${TENANCY_ID}" \
  --query 'data[0].url' \
  --raw-output | sed 's|:443$||')
echo "Domain URL : ${DOMAIN_URL}"

# ─────────────────────────────────────────
# [2/5] ユーザー作成
# ─────────────────────────────────────────
echo "=== [2/5] ユーザー作成 ==="
USER_DATA=$(oci identity-domains user create \
  --endpoint "${DOMAIN_URL}" \
  --profile "${OCI_PROFILE}" \
  --schemas '["urn:ietf:params:scim:schemas:core:2.0:User"]' \
  --user-name "${USERNAME}" \
  --emails "[{\"value\":\"${EMAIL}\",\"type\":\"work\",\"primary\":true}]")

USER_ID=$(echo "${USER_DATA}" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo "ユーザーID: ${USER_ID}"

# ─────────────────────────────────────────
# [3/5] readonly グループID取得
# ─────────────────────────────────────────
echo "=== [3/5] グループID取得 (${READONLY_GROUP}) ==="
GROUP_DATA=$(oci identity-domains group list \
  --endpoint "${DOMAIN_URL}" \
  --profile "${OCI_PROFILE}" \
  --filter "displayName eq \"${READONLY_GROUP}\"")

GROUP_ID=$(echo "${GROUP_DATA}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['Resources'][0]['id'])")

if [ -z "${GROUP_ID}" ]; then
  echo "ERROR: グループ '${READONLY_GROUP}' が見つかりません"
  exit 1
fi
echo "グループID: ${GROUP_ID}"

# ─────────────────────────────────────────
# [4/5] グループにユーザー追加
# ─────────────────────────────────────────
echo "=== [4/5] '${READONLY_GROUP}' グループへ追加 ==="
oci identity-domains group patch \
  --endpoint "${DOMAIN_URL}" \
  --profile "${OCI_PROFILE}" \
  --group-id "${GROUP_ID}" \
  --schemas '["urn:ietf:params:scim:api:messages:2.0:PatchOp"]' \
  --operations "[{\"op\":\"add\",\"path\":\"members\",\"value\":[{\"value\":\"${USER_ID}\",\"type\":\"User\"}]}]"
echo "グループへの追加完了"

# ─────────────────────────────────────────
# [5/5] 完了サマリ
# ─────────────────────────────────────────
echo "=== [5/5] 作成完了サマリ ==="
echo ""
echo "========================================"
echo "  ユーザー作成完了！"
echo "  ユーザー名     : ${USERNAME}"
echo "  メールアドレス : ${EMAIL}"
echo "  グループ       : ${READONLY_GROUP}"
echo "  ※ アクティベーションメールが ${EMAIL} に送信されます"
echo "  ※ ユーザーはメール内のリンクからパスワードを設定します"
echo "========================================"

echo "=== 完了: ログを Claude に渡す場合は $LOG を共有 ==="
