#!/usr/bin/bash
set -eu

# 使い方: bash do_oci_start.sh <インスタンス名> <コンパートメント名> [OCIプロファイル名]
# 例:     bash do_oci_start.sh claude-instance-01 dev
#         bash do_oci_start.sh claude-instance-01 dev prod

LOG="/home/hijiri/claude2026001/do_oci_start_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
echo "=== ログ出力先: $LOG ==="

# ─────────────────────────────────────────
# 引数チェック
# ─────────────────────────────────────────
if [ "${#}" -lt 2 ]; then
  echo "使い方: $0 <インスタンス名> <コンパートメント名> [OCIプロファイル名]"
  echo "例:     $0 claude-instance-01 dev"
  echo "例:     $0 claude-instance-01 dev prod"
  exit 1
fi

INSTANCE_NAME="${1}"
COMPARTMENT_NAME="${2}"
OCI_PROFILE="${3:-DEFAULT}"

echo "=== パラメータ ==="
echo "  インスタンス名     : ${INSTANCE_NAME}"
echo "  コンパートメント名 : ${COMPARTMENT_NAME}"
echo "  OCIプロファイル    : ${OCI_PROFILE}"

# ─────────────────────────────────────────
# [1/4] テナンシーID取得 (configから)
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
# [2/4] コンパートメントID取得 (名前で検索)
# ─────────────────────────────────────────
echo "=== [2/4] コンパートメントID取得 (${COMPARTMENT_NAME}) ==="
COMPARTMENT_ID=$(oci iam compartment list \
  --profile "${OCI_PROFILE}" \
  --compartment-id "${TENANCY_ID}" \
  --compartment-id-in-subtree true \
  --all \
  --query "data[?name=='${COMPARTMENT_NAME}'].id | [0]" \
  --raw-output 2>/dev/null || true)

if [ -z "${COMPARTMENT_ID}" ] || [ "${COMPARTMENT_ID}" = "null" ]; then
  echo "ERROR: コンパートメント '${COMPARTMENT_NAME}' が見つかりません"
  exit 1
fi
echo "コンパートメントID: ${COMPARTMENT_ID}"

# ─────────────────────────────────────────
# [3/4] STOPPED状態のインスタンスを検索
# ─────────────────────────────────────────
echo "=== [3/4] インスタンス検索 (name=${INSTANCE_NAME}, state=STOPPED) ==="
INSTANCE_IDS=$(oci compute instance list \
  --profile "${OCI_PROFILE}" \
  --compartment-id "${COMPARTMENT_ID}" \
  --display-name "${INSTANCE_NAME}" \
  --lifecycle-state STOPPED \
  --all \
  --query 'data[*].id' \
  --output json | python3 -c "import sys,json; data=sys.stdin.read().strip(); [print(i) for i in (json.loads(data) if data else [])]")

if [ -z "${INSTANCE_IDS}" ]; then
  echo "INFO: '${INSTANCE_NAME}' の STOPPED インスタンスが見つかりません (既に起動中か存在しない)"
  oci compute instance list \
    --profile "${OCI_PROFILE}" \
    --compartment-id "${COMPARTMENT_ID}" \
    --display-name "${INSTANCE_NAME}" \
    --all \
    --query 'data[*].{Name:"display-name", State:"lifecycle-state"}' \
    --output table 2>/dev/null || true
  exit 0
fi

COUNT=$(echo "${INSTANCE_IDS}" | wc -l | tr -d ' ')
echo "対象インスタンス: ${COUNT}件"

# ─────────────────────────────────────────
# [4/4] インスタンス起動
# ─────────────────────────────────────────
echo "=== [4/4] インスタンス起動 ==="
while IFS= read -r INSTANCE_ID; do
  [ -z "${INSTANCE_ID}" ] && continue
  echo "--- 起動中: ${INSTANCE_ID} ---"
  oci compute instance action \
    --profile "${OCI_PROFILE}" \
    --instance-id "${INSTANCE_ID}" \
    --action START \
    --wait-for-state RUNNING \
    --max-wait-seconds 300 \
    --query 'data.{ID:id, State:"lifecycle-state"}' \
    --output table
done <<< "${INSTANCE_IDS}"

echo ""
echo "=== 起動完了サマリ ==="
oci compute instance list \
  --profile "${OCI_PROFILE}" \
  --compartment-id "${COMPARTMENT_ID}" \
  --display-name "${INSTANCE_NAME}" \
  --all \
  --query 'data[*].{Name:"display-name", ID:id, State:"lifecycle-state"}' \
  --output table

echo "=== 完了: ログを Claude に渡す場合は $LOG を共有 ==="
