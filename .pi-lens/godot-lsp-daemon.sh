#!/usr/bin/env bash
# Godot LSP Daemon – keeps Godot headless editor running for LSP
# Starts on first use, stays alive, auto-exits after 10min idle.

GODOT_BIN="${GODOT_PATH:-/usr/local/bin/godot}"
LSP_PORT="${GODOT_LSP_PORT:-6005}"
PROJECT_DIR="${GODOT_PROJECT_DIR:-$PWD}"
PIDFILE="/tmp/godot-lsp-${LSP_PORT}.pid"
LOGFILE="/tmp/godot-lsp-${LSP_PORT}.log"

# Find project.godot root if not set
if [ ! -f "$PROJECT_DIR/project.godot" ]; then
    CANDIDATE="$PROJECT_DIR"
    while [ "$CANDIDATE" != "/" ]; do
        if [ -f "$CANDIDATE/project.godot" ]; then
            PROJECT_DIR="$CANDIDATE"
            break
        fi
        CANDIDATE="$(dirname "$CANDIDATE")"
    done
fi

# Check if already running
is_running() {
    if [ -f "$PIDFILE" ]; then
        local pid
        pid=$(cat "$PIDFILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
        rm -f "$PIDFILE"
    fi
    # Check if port is in use by Godot
    if command -v ss &>/dev/null; then
        ss -tlnp 2>/dev/null | grep -q ":$LSP_PORT " && return 0
    fi
    return 1
}

# Check if port is listening
port_ready() {
    if command -v ss &>/dev/null; then
        ss -tlnp 2>/dev/null | grep -q ":$LSP_PORT "
    else
        (echo > "/dev/tcp/127.0.0.1/$LSP_PORT") 2>/dev/null
    fi
}

start_godot() {
    echo "Starting Godot LSP daemon (port $LSP_PORT, project $PROJECT_DIR)..."
    "$GODOT_BIN" --headless --editor --lsp-port "$LSP_PORT" --path "$PROJECT_DIR" \
        >> "$LOGFILE" 2>&1 &
    local pid=$!
    echo "$pid" > "$PIDFILE"
    
    # Wait for port
    for i in $(seq 1 20); do
        if port_ready; then
            echo "Godot LSP ready on port $LSP_PORT (PID: $pid)"
            return 0
        fi
        sleep 1
    done
    
    echo "Timed out waiting for Godot LSP" >&2
    kill "$pid" 2>/dev/null
    rm -f "$PIDFILE"
    return 1
}

stop_godot() {
    if [ -f "$PIDFILE" ]; then
        local pid
        pid=$(cat "$PIDFILE" 2>/dev/null)
        if [ -n "$pid" ]; then
            kill "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            rm -f "$PIDFILE"
        fi
    fi
}

case "${1:-status}" in
    start)
        if is_running; then
            echo "Godot LSP already running"
            exit 0
        fi
        start_godot
        ;;
    stop)
        stop_godot
        echo "Godot LSP stopped"
        ;;
    restart)
        stop_godot
        sleep 1
        start_godot
        ;;
    status)
        if is_running; then
            echo "Godot LSP running on port $LSP_PORT (PID: $(cat "$PIDFILE" 2>/dev/null || echo 'unknown'))"
            exit 0
        else
            echo "Godot LSP not running"
            exit 1
        fi
        ;;
    ensure)
        if ! is_running; then
            start_godot
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|ensure}"
        exit 1
        ;;
esac
