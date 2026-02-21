#!/bin/bash
# perfmon-conftrack.sh — システム設定ファイル変更追跡モジュール
# perfmon-collector.sh から dot-source で読み込まれる
# 直接実行不可（LOG_DIR 等の変数は呼び出し元から継承）

# ---------------------------------------------------------------------------
# デフォルト設定（perfmon.conf で上書き可能）
# ---------------------------------------------------------------------------
CONFTRACK_ENABLED="${CONFTRACK_ENABLED:-yes}"
CONFTRACK_DIRS="${CONFTRACK_DIRS:-/etc /var/spool/cron /root /usr/lib/systemd/system}"
CONFTRACK_TIME="${CONFTRACK_TIME:-02:00}"
CONFTRACK_MAX_FILE_SIZE="${CONFTRACK_MAX_FILE_SIZE:-524288}"
CONFTRACK_EXCLUDE_PATHS="${CONFTRACK_EXCLUDE_PATHS:-/etc/pki:/etc/ssl/certs:/etc/ssh/ssh_host_*:/etc/selinux/targeted/active:/etc/alternatives:/etc/ld.so.cache:/etc/udev/hwdb.bin}"
CONFTRACK_METADATA_ONLY_PATHS="${CONFTRACK_METADATA_ONLY_PATHS:-/etc/shadow:/etc/gshadow}"
PERFMON_VERSION="${PERFMON_VERSION:-1.4.0}"

# ---------------------------------------------------------------------------
# 内部変数（ステートキャッシュ）
# ---------------------------------------------------------------------------
CONFTRACK_LAST_MASTER_DATE=""
CONFTRACK_LAST_DIFF_DATE=""

# ---------------------------------------------------------------------------
# conftrack_read_state — ステートファイルをシェル変数へ展開
# ---------------------------------------------------------------------------
conftrack_read_state() {
    local state_file="${LOG_DIR}/conftrack/.conftrack_state"
    CONFTRACK_LAST_MASTER_DATE=""
    CONFTRACK_LAST_DIFF_DATE=""
    if [[ -f "$state_file" ]]; then
        while IFS='=' read -r key val; do
            case "$key" in
                LAST_MASTER_DATE) CONFTRACK_LAST_MASTER_DATE="$val" ;;
                LAST_DIFF_DATE)   CONFTRACK_LAST_DIFF_DATE="$val"   ;;
            esac
        done < "$state_file"
    fi
}

# ---------------------------------------------------------------------------
# conftrack_write_state — ステートをアトミックに書き込み
# ---------------------------------------------------------------------------
conftrack_write_state() {
    local state_file="${LOG_DIR}/conftrack/.conftrack_state"
    local tmp_file="${state_file}.tmp"
    printf 'LAST_MASTER_DATE=%s\nLAST_DIFF_DATE=%s\n' \
        "$CONFTRACK_LAST_MASTER_DATE" \
        "$CONFTRACK_LAST_DIFF_DATE" > "$tmp_file"
    mv "$tmp_file" "$state_file"
}

# ---------------------------------------------------------------------------
# conftrack_is_binary — file --mime-encoding でバイナリ判定
# 戻り値: 0=バイナリ, 1=テキスト
# ---------------------------------------------------------------------------
conftrack_is_binary() {
    local filepath="$1"
    local encoding
    encoding=$(file --mime-encoding -b "$filepath" 2>/dev/null)
    case "$encoding" in
        us-ascii|utf-8|iso-8859-*|utf-16*|utf-32*|ascii) return 1 ;;
        *) return 0 ;;
    esac
}

# ---------------------------------------------------------------------------
# conftrack_is_excluded — 除外パスに該当するか判定
# 戻り値: 0=除外対象, 1=対象外
# ---------------------------------------------------------------------------
conftrack_is_excluded() {
    local filepath="$1"
    local IFS=':'
    local excl
    for excl in $CONFTRACK_EXCLUDE_PATHS; do
        # シェルグロブで判定
        case "$filepath" in
            $excl) return 0 ;;
            ${excl}/*) return 0 ;;
        esac
    done
    return 1
}

# ---------------------------------------------------------------------------
# conftrack_is_metadata_only — 内容非記録パスか判定
# 戻り値: 0=メタデータのみ, 1=内容記録可
# ---------------------------------------------------------------------------
conftrack_is_metadata_only() {
    local filepath="$1"
    local IFS=':'
    local mo
    for mo in $CONFTRACK_METADATA_ONLY_PATHS; do
        case "$filepath" in
            $mo) return 0 ;;
            ${mo}/*) return 0 ;;
        esac
    done
    return 1
}

# ---------------------------------------------------------------------------
# conftrack_scan_files — CONFTRACK_DIRS を find でスキャン
# stdout に対象ファイルパスを1行ずつ出力
# ---------------------------------------------------------------------------
conftrack_scan_files() {
    local dir
    for dir in $CONFTRACK_DIRS; do
        [[ -d "$dir" ]] || continue
        find "$dir" -type f 2>/dev/null
    done | sort -u
}

# ---------------------------------------------------------------------------
# conftrack_generate_master — マスターファイル生成
# ---------------------------------------------------------------------------
conftrack_generate_master() {
    local today="$1"
    local ct_dir="${LOG_DIR}/conftrack"
    local master_file="${ct_dir}/master_${today}.txt"
    local tmp_file="${master_file}.tmp"
    local lock_file="${ct_dir}/.conftrack_master.lock"

    # 排他ロック（並行実行防止）
    if ! mkdir "$lock_file" 2>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') conftrack: master generation already running (lock: $lock_file), skipping" >&2
        return
    fi
    trap "rmdir '$lock_file' 2>/dev/null" RETURN

    local hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")
    local generated
    generated=$(date '+%Y-%m-%d %H:%M:%S')

    echo "$(date '+%Y-%m-%d %H:%M:%S') conftrack: generating master for $today" >&2

    {
        printf '###CONFTRACK_MASTER###\n'
        printf 'generated=%s\n' "$generated"
        printf 'hostname=%s\n' "$hostname"
        printf 'conftrack_dirs=%s\n' "$CONFTRACK_DIRS"
        printf 'perfmon_version=%s\n' "$PERFMON_VERSION"
        printf '\n'
    } > "$tmp_file"

    local total_captured=0
    local total_skipped=0

    while IFS= read -r filepath; do
        # 除外パス判定
        if conftrack_is_excluded "$filepath"; then
            continue
        fi

        # ファイルが消えた場合
        if [[ ! -f "$filepath" ]]; then
            printf '###FILE_SKIPPED### %s\nreason=disappeared_during_scan\n\n' "$filepath" >> "$tmp_file"
            (( ++total_skipped ))
            continue
        fi

        # メタデータのみパス
        if conftrack_is_metadata_only "$filepath"; then
            local fsize fmtime fsha256
            fsize=$(stat -c '%s' "$filepath" 2>/dev/null || echo "0")
            fmtime=$(stat -c '%y' "$filepath" 2>/dev/null | cut -c1-19 || echo "unknown")
            fsha256=$(sha256sum "$filepath" 2>/dev/null | awk '{print $1}' || echo "unavailable")
            printf '###FILE_SKIPPED### %s\nreason=metadata_only\nsize=%s\nmtime=%s\nsha256=%s\n\n' \
                "$filepath" "$fsize" "$fmtime" "$fsha256" >> "$tmp_file"
            (( ++total_skipped ))
            continue
        fi

        # サイズチェック
        local fsize
        fsize=$(stat -c '%s' "$filepath" 2>/dev/null || echo "0")
        if [[ "$fsize" -gt "$CONFTRACK_MAX_FILE_SIZE" ]]; then
            printf '###FILE_SKIPPED### %s\nreason=exceeds_max_size\nsize=%s\n\n' \
                "$filepath" "$fsize" >> "$tmp_file"
            (( ++total_skipped ))
            continue
        fi

        # バイナリ判定
        if conftrack_is_binary "$filepath"; then
            printf '###FILE_SKIPPED### %s\nreason=binary\nsize=%s\n\n' \
                "$filepath" "$fsize" >> "$tmp_file"
            (( ++total_skipped ))
            continue
        fi

        # 通常ファイル記録
        local fmtime fsha256
        fmtime=$(stat -c '%y' "$filepath" 2>/dev/null | cut -c1-19 || echo "unknown")
        fsha256=$(sha256sum "$filepath" 2>/dev/null | awk '{print $1}' || echo "unavailable")
        {
            printf '###FILE### %s\n' "$filepath"
            printf 'size=%s\n' "$fsize"
            printf 'mtime=%s\n' "$fmtime"
            printf 'sha256=%s\n' "$fsha256"
            printf '%s\n' '---CONTENT---'
            cat "$filepath" 2>/dev/null || printf '(read error)\n'
            printf '\n%s\n\n' '---END---'
        } >> "$tmp_file"
        (( ++total_captured ))

    done < <(conftrack_scan_files)

    {
        printf '###CONFTRACK_MASTER_END###\n'
        printf 'total_captured=%s\n' "$total_captured"
        printf 'total_skipped=%s\n' "$total_skipped"
    } >> "$tmp_file"

    mv "$tmp_file" "$master_file"

    # 前月分以外のマスターを削除（月初以外の古いマスターを消さないよう、
    # 名前で当月・前月分のみ残し90日超えは cleanup_old_logs で削除）
    CONFTRACK_LAST_MASTER_DATE="$today"
    conftrack_write_state

    echo "$(date '+%Y-%m-%d %H:%M:%S') conftrack: master generated: $master_file (captured=$total_captured skipped=$total_skipped)" >&2
}

# ---------------------------------------------------------------------------
# conftrack_parse_master — マスターファイルから sha256 テーブルをロード
# stdout に "sha256\tfilepath" を出力
# ---------------------------------------------------------------------------
conftrack_parse_master() {
    local master_file="$1"
    awk '
        /^###FILE### / {
            filepath = substr($0, 12)
            sha = ""
            next
        }
        /^sha256=/ {
            sha = substr($0, 8)
            next
        }
        /^---CONTENT---/ {
            if (filepath != "" && sha != "") {
                print sha "\t" filepath
            }
            filepath = ""; sha = ""
            next
        }
        /^###FILE_SKIPPED### / {
            filepath = ""; sha = ""
            next
        }
    ' "$master_file"
}

# ---------------------------------------------------------------------------
# conftrack_generate_diff — 日次差分ファイル生成
# ---------------------------------------------------------------------------
conftrack_generate_diff() {
    local today="$1"
    local ct_dir="${LOG_DIR}/conftrack"

    # ステートをロード（LAST_MASTER_DATE が未設定の場合に備えて）
    conftrack_read_state

    # マスターファイルを特定（最新の master_*.txt）
    local master_file
    master_file=$(ls -t "${ct_dir}"/master_*.txt 2>/dev/null | head -1)
    if [[ -z "$master_file" || ! -f "$master_file" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') conftrack: no master file found, skipping diff (run conftrack_init to generate master)" >&2
        return
    fi

    local master_date
    master_date=$(basename "$master_file" | sed 's/master_\(.*\)\.txt/\1/')

    local diff_file="${ct_dir}/diff_${today}.txt"
    local tmp_file="${diff_file}.tmp"
    local generated
    generated=$(date '+%Y-%m-%d %H:%M:%S')

    echo "$(date '+%Y-%m-%d %H:%M:%S') conftrack: generating diff for $today (master=$master_date)" >&2

    {
        printf '###CONFTRACK_DIFF###\n'
        printf 'generated=%s\n' "$generated"
        printf 'master_date=%s\n' "$master_date"
        printf 'master_file=%s\n' "$(basename "$master_file")"
        printf '\n'
    } > "$tmp_file"

    # マスターから sha256 テーブルをロード（連想配列）
    declare -A master_sha
    declare -A master_content_start  # ファイルの ---CONTENT--- 行番号（未使用、差分は再取得）
    while IFS=$'\t' read -r sha fp; do
        master_sha["$fp"]="$sha"
    done < <(conftrack_parse_master "$master_file")

    # マスターに記録されているファイルセット
    declare -A master_files
    for fp in "${!master_sha[@]}"; do
        master_files["$fp"]=1
    done

    local count_new=0 count_deleted=0 count_modified=0 count_unchanged=0

    # 現在のファイルをスキャン
    declare -A current_files
    while IFS= read -r filepath; do
        conftrack_is_excluded "$filepath" && continue
        current_files["$filepath"]=1

        if [[ ! -f "$filepath" ]]; then
            continue
        fi

        if conftrack_is_metadata_only "$filepath"; then
            continue
        fi

        local fsize
        fsize=$(stat -c '%s' "$filepath" 2>/dev/null || echo "0")
        if [[ "$fsize" -gt "$CONFTRACK_MAX_FILE_SIZE" ]] || conftrack_is_binary "$filepath"; then
            continue
        fi

        local cur_sha
        cur_sha=$(sha256sum "$filepath" 2>/dev/null | awk '{print $1}')

        if [[ -z "${master_sha[$filepath]+x}" ]]; then
            # 新規ファイル
            printf '###NEW### %s\n---CONTENT---\n' "$filepath" >> "$tmp_file"
            cat "$filepath" 2>/dev/null >> "$tmp_file"
            printf '\n---END---\n\n' >> "$tmp_file"
            (( ++count_new ))
        elif [[ "${master_sha[$filepath]}" != "$cur_sha" ]]; then
            # 変更ファイル
            {
                printf '###MODIFIED### %s\n---DIFF---\n' "$filepath"
                # マスターの内容を一時ファイルで取得して diff
                local master_content_tmp
                master_content_tmp=$(mktemp /tmp/conftrack_master_XXXXXX)
                awk -v target="$filepath" '
                    /^###FILE### / { current = substr($0, 12); in_content = 0; next }
                    /^---CONTENT---/ { if (current == target) in_content = 1; next }
                    /^---END---/ { in_content = 0; next }
                    in_content { print }
                ' "$master_file" > "$master_content_tmp"
                diff -u \
                    --label "master_${master_date} ${filepath}" \
                    --label "current        ${filepath}" \
                    "$master_content_tmp" "$filepath" 2>/dev/null || true
                rm -f "$master_content_tmp"
                printf '%s\n\n' '---END---'
            } >> "$tmp_file"
            (( ++count_modified ))
        else
            (( ++count_unchanged ))
        fi

    done < <(conftrack_scan_files)

    # 削除されたファイル（マスターにあって現在ない）
    for fp in "${!master_files[@]}"; do
        if [[ -z "${current_files[$fp]+x}" ]]; then
            printf '###DELETED### %s\n\n' "$fp" >> "$tmp_file"
            (( ++count_deleted ))
        fi
    done

    {
        printf '###CONFTRACK_DIFF_END###\n'
        printf 'new=%s deleted=%s modified=%s unchanged=%s\n' \
            "$count_new" "$count_deleted" "$count_modified" "$count_unchanged"
    } >> "$tmp_file"

    mv "$tmp_file" "$diff_file"

    CONFTRACK_LAST_DIFF_DATE="$today"
    conftrack_write_state

    echo "$(date '+%Y-%m-%d %H:%M:%S') conftrack: diff generated: $diff_file (new=$count_new deleted=$count_deleted modified=$count_modified unchanged=$count_unchanged)" >&2
}

# ---------------------------------------------------------------------------
# conftrack_init — ディレクトリ作成・ステートロード・初回マスター生成判断
# ---------------------------------------------------------------------------
conftrack_init() {
    [[ "$CONFTRACK_ENABLED" != "yes" ]] && return

    local ct_dir="${LOG_DIR}/conftrack"
    mkdir -p "$ct_dir"

    conftrack_read_state

    local today
    today=$(date +%Y%m%d)
    local day
    day=$(date +%-d)

    # マスターが存在しない場合は即座に生成
    if [[ -z "$CONFTRACK_LAST_MASTER_DATE" ]] || \
       ! ls "${ct_dir}"/master_*.txt >/dev/null 2>&1; then
        conftrack_generate_master "$today"
        return
    fi

    # 月初でマスターが未生成の場合も生成
    if [[ "$day" -eq 1 && "$CONFTRACK_LAST_MASTER_DATE" != "$today" ]]; then
        conftrack_generate_master "$today"
    fi
}

# ---------------------------------------------------------------------------
# conftrack_check — メインループから毎 60s 呼ばれるエントリーポイント
# ---------------------------------------------------------------------------
conftrack_check() {
    [[ "$CONFTRACK_ENABLED" != "yes" ]] && return

    local current_hhmm
    current_hhmm=$(date +%H:%M)
    local today
    today=$(date +%Y%m%d)
    local day
    day=$(date +%-d)

    # 設定時刻(HH:MM)を過ぎていて、かつ本日未実行か判定
    if [[ "$current_hhmm" > "$CONFTRACK_TIME" || "$current_hhmm" == "$CONFTRACK_TIME" ]]; then
        if [[ "$day" -eq 1 && "$CONFTRACK_LAST_MASTER_DATE" != "$today" ]]; then
            conftrack_generate_master "$today"
        elif [[ "$day" -ne 1 && "$CONFTRACK_LAST_DIFF_DATE" != "$today" ]]; then
            conftrack_generate_diff "$today"
        fi
    fi
}
