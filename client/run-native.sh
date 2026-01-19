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
    # Change to script directory and run - this ensures relative paths work correctly
    # Use a subshell to not affect the parent's working directory
    (cd "$SCRIPT_DIR" && nohup "$ENTRYPOINT_SCRIPT" >> "$LOG_FILE" 2>&1 &
     echo $! > "$PID_FILE")
    
    sleep 3
    
    # Verify by checking if autossh process exists
    if is_running; then
        PID=$(cat "$PID_FILE")
        
        # Also verify autossh is running
        sleep 2
        AUTOSSH_COUNT=$(pgrep -f "autossh.*-R" 2>/dev/null | wc -l | tr -d ' ')
        
        if [ "$AUTOSSH_COUNT" -gt 0 ]; then
            echo "Tunnel started successfully (PID: $PID, autossh processes: $AUTOSSH_COUNT)"
            echo "Logs: $LOG_FILE"
            return 0
        else
            echo "Warning: Main process started (PID: $PID) but no autossh tunnels detected"
            echo "Check logs: $LOG_FILE"
            return 0
        fi
    else
        echo "Failed to start tunnel. Check logs: $LOG_FILE"
        rm -f "$PID_FILE"
        return 1
    fi
}

# Function to stop tunnel
stop() {
    # Read remote host from config to identify tunnel processes
    REMOTE_HOST=""
    if [ -f "$SCRIPT_DIR/client.yml" ] && command -v yq >/dev/null 2>&1; then
        REMOTE_HOST=$(yq eval '.ssh.remote_host' "$SCRIPT_DIR/client.yml" 2>/dev/null || echo "")
    fi
    
    PID=""
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
    fi
    
    echo "Stopping tunnel..."
    
    # Kill the main entrypoint process if PID file exists and process is running
    if [ -n "$PID" ] && ps -p "$PID" > /dev/null 2>&1; then
        echo "  Killing main process (PID: $PID)..."
        kill "$PID" 2>/dev/null || true
        sleep 1
        if ps -p "$PID" > /dev/null 2>&1; then
            kill -9 "$PID" 2>/dev/null || true
        fi
    fi
    
    # Kill all autossh processes (they don't have entrypoint-native in their cmdline)
    AUTOSSH_PIDS=$(pgrep -f "autossh.*-R" 2>/dev/null || true)
    if [ -n "$AUTOSSH_PIDS" ]; then
        echo "  Killing autossh processes..."
        echo "$AUTOSSH_PIDS" | xargs kill 2>/dev/null || true
        sleep 1
        # Force kill any remaining
        echo "$AUTOSSH_PIDS" | xargs kill -9 2>/dev/null || true
    fi
    
    # Kill autossh processes by remote host if we have it
    if [ -n "$REMOTE_HOST" ]; then
        AUTOSSH_BY_HOST=$(pgrep -f "autossh.*${REMOTE_HOST}" 2>/dev/null || true)
        if [ -n "$AUTOSSH_BY_HOST" ]; then
            echo "  Killing autossh processes for $REMOTE_HOST..."
            echo "$AUTOSSH_BY_HOST" | xargs kill 2>/dev/null || true
            sleep 1
            echo "$AUTOSSH_BY_HOST" | xargs kill -9 2>/dev/null || true
        fi
    fi
    
    # Kill any SSH processes spawned by autossh (they have -R in their command)
    SSH_PIDS=$(pgrep -f "ssh.*-R.*:.*:" 2>/dev/null || true)
    if [ -n "$SSH_PIDS" ]; then
        echo "  Killing SSH tunnel processes..."
        echo "$SSH_PIDS" | xargs kill 2>/dev/null || true
        sleep 1
        echo "$SSH_PIDS" | xargs kill -9 2>/dev/null || true
    fi
    
    # Clean up PID file
    rm -f "$PID_FILE"
    
    # Verify all processes are stopped
    sleep 1
    REMAINING=$(pgrep -f "autossh.*-R\|ssh.*-R.*:" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$REMAINING" -gt 0 ]; then
        echo "  Warning: $REMAINING tunnel process(es) may still be running"
        echo "  Remaining processes:"
        pgrep -f "autossh.*-R\|ssh.*-R.*:" 2>/dev/null | xargs ps -p 2>/dev/null || true
    else
        echo "Tunnel stopped successfully"
    fi
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
