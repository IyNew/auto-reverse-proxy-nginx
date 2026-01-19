#!/bin/bash

# Wrapper script to run the native tunnel client
# This script can be used to start/stop/restart the tunnel service

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTRYPOINT_SCRIPT="$SCRIPT_DIR/entrypoint-native.sh"
PID_FILE="$SCRIPT_DIR/.tunnel.pid"
LOG_FILE="$SCRIPT_DIR/logs/tunnel.log"

# Create logs directory if it doesn't exist
mkdir -p "$SCRIPT_DIR/logs"

# Function to check if tunnel is running
is_running() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            return 0
        else
            rm -f "$PID_FILE"
            return 1
        fi
    fi
    return 1
}

# Function to start tunnel
start() {
    if is_running; then
        echo "Tunnel is already running (PID: $(cat "$PID_FILE"))"
        return 1
    fi
    
    if [ ! -f "$ENTRYPOINT_SCRIPT" ]; then
        echo "Error: entrypoint-native.sh not found"
        return 1
    fi
    
    if [ ! -x "$ENTRYPOINT_SCRIPT" ]; then
        chmod +x "$ENTRYPOINT_SCRIPT"
    fi
    
    echo "Starting reverse tunnel client..."
    nohup "$ENTRYPOINT_SCRIPT" >> "$LOG_FILE" 2>&1 &
    PID=$!
    echo $PID > "$PID_FILE"
    
    sleep 2
    
    if is_running; then
        echo "Tunnel started successfully (PID: $PID)"
        echo "Logs: $LOG_FILE"
        return 0
    else
        echo "Failed to start tunnel. Check logs: $LOG_FILE"
        rm -f "$PID_FILE"
        return 1
    fi
}

# Function to stop tunnel
stop() {
    if ! is_running; then
        echo "Tunnel is not running"
        return 1
    fi
    
    PID=$(cat "$PID_FILE")
    echo "Stopping tunnel (PID: $PID)..."
    
    # Kill the main process and all autossh processes
    kill "$PID" 2>/dev/null || true
    
    # Also kill any autossh processes
    pkill -f "autossh.*entrypoint-native" 2>/dev/null || true
    
    # Wait a bit for processes to terminate
    sleep 2
    
    # Force kill if still running
    if ps -p "$PID" > /dev/null 2>&1; then
        kill -9 "$PID" 2>/dev/null || true
    fi
    
    rm -f "$PID_FILE"
    echo "Tunnel stopped"
}

# Function to restart tunnel
restart() {
    stop
    sleep 1
    start
}

# Function to show status
status() {
    if is_running; then
        PID=$(cat "$PID_FILE")
        echo "Tunnel is running (PID: $PID)"
        
        # Count autossh processes
        AUTOSSH_COUNT=$(pgrep -f "autossh.*-R" | wc -l | tr -d ' ')
        echo "Active tunnels: $AUTOSSH_COUNT"
        
        # Show recent log entries
        if [ -f "$LOG_FILE" ]; then
            echo ""
            echo "Recent log entries:"
            tail -n 5 "$LOG_FILE"
        fi
    else
        echo "Tunnel is not running"
    fi
}

# Function to show logs
logs() {
    if [ -f "$LOG_FILE" ]; then
        tail -f "$LOG_FILE"
    else
        echo "Log file not found: $LOG_FILE"
    fi
}

# Main command handler
case "${1:-}" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    status)
        status
        ;;
    logs)
        logs
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs}"
        echo ""
        echo "Commands:"
        echo "  start   - Start the reverse tunnel client"
        echo "  stop    - Stop the reverse tunnel client"
        echo "  restart - Restart the reverse tunnel client"
        echo "  status  - Show tunnel status"
        echo "  logs    - Show and follow tunnel logs"
        exit 1
        ;;
esac
