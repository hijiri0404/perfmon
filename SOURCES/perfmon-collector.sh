#!/bin/bash
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
    wait
    exit 0
}
trap cleanup SIGTERM SIGINT

# 古いログを削除
cleanup_old_logs() {
    find "$LOG_DIR" -name '*.log' -mtime +"$RETENTION_DAYS" -delete 2>/dev/null
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

# top 収集（バッチモード、スナップショット区切りを付与）
start_top() {
    local date_suffix=$1
    top -b -d "$INTERVAL" | gawk '
        /^top - / {
            if (NR > 1) print ""
            print "=== " strftime("%Y-%m-%d %H:%M:%S") " ==="
            fflush()
        }
        { print $0; fflush() }
    ' >> "${LOG_DIR}/top_${date_suffix}.log" &
    CHILD_PIDS+=($!)
}

# 全収集プロセスを停止
stop_collectors() {
    for pid in "${CHILD_PIDS[@]}"; do
        kill "$pid" 2>/dev/null
    done
    wait 2>/dev/null
    CHILD_PIDS=()
}

# 全収集プロセスを起動
start_collectors() {
    local date_suffix=$1
    echo "$(date '+%Y-%m-%d %H:%M:%S') Starting collectors for $date_suffix"
    start_vmstat "$date_suffix"
    start_iostat "$date_suffix"
    start_pidstat "$date_suffix"
    start_mpstat "$date_suffix"
    start_sar "$date_suffix"
    start_top "$date_suffix"
}

# --- メインループ ---
CURRENT_DATE=$(today)
cleanup_old_logs
start_collectors "$CURRENT_DATE"

while true; do
    sleep 60 &
    wait $!

    NEW_DATE=$(today)
    if [[ "$NEW_DATE" != "$CURRENT_DATE" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') Date changed: $CURRENT_DATE -> $NEW_DATE"
        stop_collectors
        cleanup_old_logs
        CURRENT_DATE="$NEW_DATE"
        start_collectors "$CURRENT_DATE"
    fi
done
