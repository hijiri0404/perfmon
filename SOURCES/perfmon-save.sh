#!/bin/bash
# perfmon-save.sh — ログファイルをzip圧縮して /tmp に保存する

CONF=/etc/perfmon/perfmon.conf
if [[ -f "$CONF" ]]; then
    . "$CONF"
fi
LOG_DIR="${LOG_DIR:-/opt/perfmon/log}"

if [[ ! -d "$LOG_DIR" ]]; then
    echo "ERROR: Log directory not found: $LOG_DIR" >&2
    exit 1
fi

HOSTNAME_SHORT=$(hostname -s)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTFILE="/tmp/perfmon_${HOSTNAME_SHORT}_${TIMESTAMP}.zip"

# .log（当日収集中）と .log.gz（ローテート済み圧縮）の両方を収集する
shopt -s nullglob
logs=("$LOG_DIR"/*.log "$LOG_DIR"/*.log.gz)
shopt -u nullglob

if [[ ${#logs[@]} -eq 0 ]]; then
    echo "ERROR: No log files found in $LOG_DIR" >&2
    exit 1
fi

zip -j "$OUTFILE" "${logs[@]}"
echo "Saved: $OUTFILE"
