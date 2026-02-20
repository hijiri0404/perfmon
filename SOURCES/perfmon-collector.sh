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

# vmstat 収集（タイムスタンプ付与）
start_vmstat() {
    local date_suffix=$1
    vmstat -n "$INTERVAL" | gawk '
        /^ *[0-9]/ {
            print strftime("%Y-%m-%d %H:%M:%S"), $0
            fflush()
        }
    ' >> "${LOG_DIR}/vmstat_${date_suffix}.log" &
    CHILD_PIDS+=($!)
}

# iostat 収集（タイムスタンプ付与）
start_iostat() {
    local date_suffix=$1
    iostat -dxkt "$INTERVAL" | gawk '
        /^[A-Z]/ && !/^Linux/ && !/^Device/ { next }
        /^Device/ {
            print strftime("%Y-%m-%d %H:%M:%S"), $0
            fflush()
            next
        }
        /^ *[a-z]/ {
            print strftime("%Y-%m-%d %H:%M:%S"), $0
            fflush()
        }
    ' >> "${LOG_DIR}/iostat_${date_suffix}.log" &
    CHILD_PIDS+=($!)
}

# pidstat 収集（タイムスタンプ付与）
start_pidstat() {
    local date_suffix=$1
    pidstat -u -r -d "$INTERVAL" | gawk '
        /^#/ || /^$/ { next }
        /^ *[0-9]/ {
            print strftime("%Y-%m-%d %H:%M:%S"), $0
            fflush()
            next
        }
        /^Linux/ { next }
        /Average/ { next }
        {
            print strftime("%Y-%m-%d %H:%M:%S"), $0
            fflush()
        }
    ' >> "${LOG_DIR}/pidstat_${date_suffix}.log" &
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
