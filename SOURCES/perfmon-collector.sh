#!/usr/bin/bash
# perfmon-collector.sh — CPU/メモリ/ディスクIOをプロセス単位含め時系列で記録する

set -u

CONF=/etc/perfmon/perfmon.conf
if [[ -f "$CONF" ]]; then
    . "$CONF"
fi
INTERVAL="${INTERVAL:-60}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
LOG_DIR="${LOG_DIR:-/opt/perfmon/log}"

mkdir -p "$LOG_DIR"

# 子プロセスPIDを管理
CHILD_PIDS=()

cleanup() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') Stopping perfmon-collector..."
    for pid in "${CHILD_PIDS[@]}"; do
        kill "$pid" 2>/dev/null
    done
    pkill -P $$ 2>/dev/null || true
    wait
    exit 0
}
trap cleanup SIGTERM SIGINT

# 古いログを削除（.log と .log.gz の両方を対象とする）
cleanup_old_logs() {
    find "$LOG_DIR" -name '*.log.gz' -mtime +"$RETENTION_DAYS" -delete 2>/dev/null
    find "$LOG_DIR" -name '*.log'    -mtime +"$RETENTION_DAYS" -delete 2>/dev/null
}

# 前日以前の .log ファイルを gzip 圧縮する
# 日付ローテーション時およびサービス起動時（停止中に溜まった未圧縮ログを救済）に実行する
compress_rotated_logs() {
    find "$LOG_DIR" -name '*.log' -not -name "*$(today)*" \
        -exec gzip -f {} \; 2>/dev/null
}

# 日付サフィックスを返す
today() {
    date +%Y%m%d
}

# vmstat 収集（タイムスタンプ付与、起動時平均を除外、ヘッダーを出力）
start_vmstat() {
    local date_suffix=$1
    vmstat -n "$INTERVAL" | gawk '
        /^ r  b/ {
            print strftime("%Y-%m-%d %H:%M:%S"), $0
            fflush()
            next
        }
        /^ *[0-9]/ {
            count++
            if (count == 1) next
            print strftime("%Y-%m-%d %H:%M:%S"), $0
            fflush()
        }
    ' >> "${LOG_DIR}/vmstat_${date_suffix}.log" &
    CHILD_PIDS+=($!)
}

# iostat 収集（タイムスタンプ付与、起動時平均を除外）
start_iostat() {
    local date_suffix=$1
    iostat -dxkt "$INTERVAL" | gawk '
        /^[A-Z]/ && !/^Linux/ && !/^Device/ { next }
        /^Device/ {
            section++
            if (section == 1) { in_first = 1; next }
            in_first = 0
            print strftime("%Y-%m-%d %H:%M:%S"), $0
            fflush()
            next
        }
        /^ *[a-z]/ {
            if (in_first) next
            print strftime("%Y-%m-%d %H:%M:%S"), $0
            fflush()
        }
    ' >> "${LOG_DIR}/iostat_${date_suffix}.log" &
    CHILD_PIDS+=($!)
}

# pidstat 収集（タイムスタンプ付与、起動時平均を除外）
# ヘッダーと各データ行の pidstat 内部タイムスタンプを比較し、
# 一致する間（起動時平均）はスキップし、差異が生じた時点から記録する
start_pidstat() {
    local date_suffix=$1
    pidstat -u -r -d "$INTERVAL" | gawk '
        BEGIN { pending_hdr = ""; hdr_ts = ""; boot_avg = 1 }
        /^#/ || /^$/ { next }
        /^ *[0-9]/ {
            ts = $1
            if ($2 == "UID") {
                pending_hdr = $0
                hdr_ts = ts
                next
            }
            if (boot_avg) {
                if (ts != hdr_ts) {
                    boot_avg = 0
                    if (pending_hdr != "") {
                        print strftime("%Y-%m-%d %H:%M:%S"), pending_hdr
                        fflush()
                        pending_hdr = ""
                    }
                    print strftime("%Y-%m-%d %H:%M:%S"), $0
                    fflush()
                }
                next
            }
            if (pending_hdr != "") {
                print strftime("%Y-%m-%d %H:%M:%S"), pending_hdr
                fflush()
                pending_hdr = ""
            }
            print strftime("%Y-%m-%d %H:%M:%S"), $0
            fflush()
            next
        }
        /^Linux/ { next }
        /Average/ { next }
        {
            if (boot_avg) next
            print strftime("%Y-%m-%d %H:%M:%S"), $0
            fflush()
        }
    ' >> "${LOG_DIR}/pidstat_${date_suffix}.log" &
    CHILD_PIDS+=($!)
}

# mpstat 収集（CPU別使用率、起動時平均を除外）
start_mpstat() {
    local date_suffix=$1
    mpstat -P ALL "$INTERVAL" | gawk '
        /^Linux/ { next }
        /^$/ { next }
        /[[:space:]]CPU[[:space:]]/ {
            section++
            if (section == 1) { in_first = 1; next }
            in_first = 0
            print strftime("%Y-%m-%d %H:%M:%S"), $0
            fflush()
            next
        }
        {
            if (in_first) next
            print strftime("%Y-%m-%d %H:%M:%S"), $0
            fflush()
        }
    ' >> "${LOG_DIR}/mpstat_${date_suffix}.log" &
    CHILD_PIDS+=($!)
}

# sar 収集（ネットワーク統計、起動時平均を除外）
start_sar() {
    local date_suffix=$1
    sar -n DEV "$INTERVAL" | gawk '
        /^Linux/ { next }
        /^$/ { next }
        /[[:space:]]IFACE[[:space:]]/ {
            section++
            if (section == 1) { in_first = 1; next }
            in_first = 0
            print strftime("%Y-%m-%d %H:%M:%S"), $0
            fflush()
            next
        }
        {
            if (in_first) next
            print strftime("%Y-%m-%d %H:%M:%S"), $0
            fflush()
        }
    ' >> "${LOG_DIR}/sar_net_${date_suffix}.log" &
    CHILD_PIDS+=($!)
}

# top 収集（バッチモード、各行にタイムスタンプを付与）
start_top() {
    local date_suffix=$1
    top -b -d "$INTERVAL" | gawk '
        /^top - / {
            if (NR > 1) print ""
            ts = strftime("%Y-%m-%d %H:%M:%S")
            print ts, $0
            fflush()
            next
        }
        /^$/ { next }
        {
            if (ts != "") print ts, $0
            else print $0
            fflush()
        }
    ' >> "${LOG_DIR}/top_${date_suffix}.log" &
    CHILD_PIDS+=($!)
}

# meminfo 収集（詳細メモリ情報：Slab/HugePages/Dirty/CommitLimit等）
# vmstat では取得できない詳細項目を補完する
start_meminfo() {
    local date_suffix=$1
    while true; do
        gawk -v ts="$(date '+%Y-%m-%d %H:%M:%S')" \
            '{print ts, $0; fflush()}' /proc/meminfo
        echo ""
        sleep "$INTERVAL"
    done >> "${LOG_DIR}/meminfo_${date_suffix}.log" &
    CHILD_PIDS+=($!)
}

# netstat 収集（TCP接続状態サマリ：TIME_WAIT爆発・再送増加等の検知）
# sar -n DEV では帯域のみのため ss -s で接続状態を補完する
start_netstat() {
    local date_suffix=$1
    while true; do
        ss -s | gawk -v ts="$(date '+%Y-%m-%d %H:%M:%S')" \
            'NF > 0 {print ts, $0; fflush()}'
        echo ""
        sleep "$INTERVAL"
    done >> "${LOG_DIR}/netstat_${date_suffix}.log" &
    CHILD_PIDS+=($!)
}

# df 収集（ディスク容量・inode使用率：枯渇障害の事前検知）
start_df() {
    local date_suffix=$1
    while true; do
        local ts
        ts=$(date '+%Y-%m-%d %H:%M:%S')
        df -hP | gawk -v ts="$ts" '{print ts, $0; fflush()}'
        echo "$ts --- inode ---"
        df -iP | gawk -v ts="$ts" 'NR > 1 {print ts, $0; fflush()}'
        echo ""
        sleep "$INTERVAL"
    done >> "${LOG_DIR}/df_${date_suffix}.log" &
    CHILD_PIDS+=($!)
}

# fdcount 収集（システム全体のファイルディスクリプタ数）
# "too many open files" 障害の事前検知に使用する
start_fdcount() {
    local date_suffix=$1
    # ヘッダー行（列名）を先頭に出力
    echo "$(date '+%Y-%m-%d %H:%M:%S') allocated unused max_open" \
        >> "${LOG_DIR}/fdcount_${date_suffix}.log"
    while true; do
        gawk -v ts="$(date '+%Y-%m-%d %H:%M:%S')" \
            '{print ts, $0; fflush()}' /proc/sys/fs/file-nr
        sleep "$INTERVAL"
    done >> "${LOG_DIR}/fdcount_${date_suffix}.log" &
    CHILD_PIDS+=($!)
}

# dstate 収集（D状態プロセス：I/O待ちハングの検出）
# top と同じ60秒間隔のスナップショットだが、D状態プロセスのみを抽出して専用ファイルに
# 記録することで障害調査時に即座に参照できる。また wchan（待機中のカーネル関数）を
# 付記することで、top では得られない「何を待っているか」まで記録する。
start_dstate() {
    local date_suffix=$1
    # ヘッダー行（列名）を先頭に出力
    echo "$(date '+%Y-%m-%d %H:%M:%S') PID PPID STAT WCHAN               COMMAND" \
        >> "${LOG_DIR}/dstate_${date_suffix}.log"
    while true; do
        ps -eo pid,ppid,stat,wchan:20,comm 2>/dev/null | \
            gawk -v ts="$(date '+%Y-%m-%d %H:%M:%S')" \
            'NR > 1 && $3 ~ /^D/ {print ts, $0; fflush()}'
        sleep "$INTERVAL"
    done >> "${LOG_DIR}/dstate_${date_suffix}.log" &
    CHILD_PIDS+=($!)
}

# dmesg 収集（カーネルメッセージ：OOM/ディスクエラー/ハードウェア障害の記録）
# dmesg -w でリングバッファの新着メッセージをリアルタイムに追跡する
# -T で人間が読めるカーネルイベント時刻を付与し、行頭に収集時刻も追加する
start_dmesg() {
    local date_suffix=$1
    dmesg -w -T 2>/dev/null | gawk '{
        print strftime("%Y-%m-%d %H:%M:%S"), $0
        fflush()
    }' >> "${LOG_DIR}/dmesg_${date_suffix}.log" &
    CHILD_PIDS+=($!)
}

# 全収集プロセスを停止
stop_collectors() {
    for pid in "${CHILD_PIDS[@]}"; do
        kill "$pid" 2>/dev/null
    done
    # gawk を kill しても親シェルがパイプの read 端を保持しているため
    # vmstat 等に SIGPIPE が届かず wait がブロックされる場合がある。
    # pkill -P $$ で直接の子プロセス（vmstat/iostat 等）を明示的に終了させる。
    pkill -P $$ 2>/dev/null || true
    wait 2>/dev/null
    CHILD_PIDS=()
}

# 全収集プロセスを起動
start_collectors() {
    local date_suffix=$1
    echo "$(date '+%Y-%m-%d %H:%M:%S') Starting collectors for $date_suffix"
    start_vmstat   "$date_suffix"
    start_iostat   "$date_suffix"
    start_pidstat  "$date_suffix"
    start_mpstat   "$date_suffix"
    start_sar      "$date_suffix"
    start_top      "$date_suffix"
    start_meminfo  "$date_suffix"
    start_netstat  "$date_suffix"
    start_df       "$date_suffix"
    start_fdcount  "$date_suffix"
    start_dstate   "$date_suffix"
    start_dmesg    "$date_suffix"
}

# --- メインループ ---
CURRENT_DATE=$(today)
compress_rotated_logs  # 停止中に溜まった前日以前の未圧縮ログを救済
cleanup_old_logs
start_collectors "$CURRENT_DATE"

while true; do
    sleep 60 &
    wait $!

    NEW_DATE=$(today)
    if [[ "$NEW_DATE" != "$CURRENT_DATE" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') Date changed: $CURRENT_DATE -> $NEW_DATE"
        stop_collectors
        compress_rotated_logs  # 前日ログを圧縮してから新しい日付で再起動
        cleanup_old_logs
        CURRENT_DATE="$NEW_DATE"
        start_collectors "$CURRENT_DATE"
    fi
done
