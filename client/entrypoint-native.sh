#!/bin/sh

set -e

# Detect if running in Docker or natively
# Default paths for native execution
if [ -z "$CLIENT_CONFIG" ]; then
    # Try to find config in common locations
    if [ -f "./client.yml" ]; then
        CLIENT_CONFIG="./client.yml"
    elif [ -f "$HOME/.config/reverse-tunnel/client.yml" ]; then
        CLIENT_CONFIG="$HOME/.config/reverse-tunnel/client.yml"
    elif [ -f "/etc/reverse-tunnel/client.yml" ]; then
        CLIENT_CONFIG="/etc/reverse-tunnel/client.yml"
    else
        CLIENT_CONFIG="./client.yml"
    fi
fi

TARGET_HOST=${TARGET_HOST:-localhost}

# Default log directory for native execution
if [ -z "$LOG_DIR" ]; then
    if [ -d "./logs" ]; then
        LOG_DIR="./logs"
    elif [ -d "$HOME/.config/reverse-tunnel/logs" ]; then
        LOG_DIR="$HOME/.config/reverse-tunnel/logs"
    elif [ -d "/var/log/reverse-tunnel" ]; then
        LOG_DIR="/var/log/reverse-tunnel"
    else
        LOG_DIR="./logs"
    fi
fi

# SSH key path - read from config file
if [ -z "$SSH_KEY_PATH" ]; then
    # Try to read from config file
    if command -v yq >/dev/null 2>&1 && [ -f "$CLIENT_CONFIG" ]; then
        SSH_KEY_PATH=$(yq eval '.ssh.private_key' "$CLIENT_CONFIG" 2>/dev/null || echo "")
        # Expand tilde if present
        SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"
    fi
    
    # Fallback to common locations
    if [ -z "$SSH_KEY_PATH" ] || [ "$SSH_KEY_PATH" = "null" ] || [ ! -f "$SSH_KEY_PATH" ]; then
        if [ -f "$HOME/.ssh/id_rsa" ]; then
            SSH_KEY_PATH="$HOME/.ssh/id_rsa"
        elif [ -f "$HOME/.ssh/id_ed25519" ]; then
            SSH_KEY_PATH="$HOME/.ssh/id_ed25519"
        else
            SSH_KEY_PATH=""
        fi
    fi
fi

# Check if client config file exists
if [ ! -f "$CLIENT_CONFIG" ]; then
    echo "Error: Client configuration file not found at $CLIENT_CONFIG"
    echo "Please create a client.yml file or set CLIENT_CONFIG environment variable"
    exit 1
fi

# Check if SSH key exists
if [ -z "$SSH_KEY_PATH" ] || [ ! -f "$SSH_KEY_PATH" ]; then
    echo "Error: SSH key not found at $SSH_KEY_PATH"
    echo "Please set ssh.private_key in $CLIENT_CONFIG or set SSH_KEY_PATH environment variable"
    exit 1
fi

# Verify SSH key permissions
if [ -f "$SSH_KEY_PATH" ]; then
    PERMS=$(stat -c "%a" "$SSH_KEY_PATH" 2>/dev/null || stat -f "%OLp" "$SSH_KEY_PATH" 2>/dev/null || echo "unknown")
    if [ "$PERMS" != "600" ] && [ "$PERMS" != "unknown" ]; then
        echo "Warning: SSH key permissions are $PERMS, should be 600"
        chmod 600 "$SSH_KEY_PATH" 2>/dev/null || echo "Could not fix permissions"
    fi
fi

# Create logs directory
mkdir -p "$LOG_DIR"

# Check for required commands
if ! command -v autossh >/dev/null 2>&1; then
    echo "Error: autossh is not installed"
    echo "Please install autossh:"
    echo "  macOS: brew install autossh"
    echo "  Ubuntu/Debian: sudo apt-get install autossh"
    echo "  Alpine: apk add autossh"
    exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
    echo "Error: yq is not installed"
    echo "Please install yq:"
    echo "  macOS: brew install yq"
    echo "  Ubuntu/Debian: sudo snap install yq"
    echo "  Or download from: https://github.com/mikefarah/yq/releases"
    exit 1
fi

# Read SSH configuration from YAML
REMOTE_HOST=$(yq eval '.ssh.remote_host' "$CLIENT_CONFIG")
REMOTE_USER=$(yq eval '.ssh.remote_user' "$CLIENT_CONFIG")

if [ -z "$REMOTE_HOST" ] || [ "$REMOTE_HOST" = "null" ]; then
    echo "Error: remote_host not found in client configuration"
    exit 1
fi

if [ -z "$REMOTE_USER" ] || [ "$REMOTE_USER" = "null" ]; then
    REMOTE_USER="ubuntu"
fi

# Display configuration
echo "=========================================="
echo "SSH Tunnel Client Configuration"
echo "=========================================="
echo "Remote Host: $REMOTE_HOST"
echo "Remote User: $REMOTE_USER"
echo "Target Host: $TARGET_HOST"
echo "Config File: $CLIENT_CONFIG"
echo "SSH Key: $SSH_KEY_PATH"
echo "Log Directory: $LOG_DIR"
echo "=========================================="
echo ""

# Get list of tunnel names
TUNNEL_NAMES=$(yq eval '.tunnels | keys | .[]' "$CLIENT_CONFIG")

if [ -z "$TUNNEL_NAMES" ]; then
    echo "Error: No tunnels defined in configuration"
    exit 1
fi

# Start tunnels
TUNNEL_COUNT=0
FAILED_TUNNELS=""

for TUNNEL_NAME in $TUNNEL_NAMES; do
    LOCAL_PORT=$(yq eval ".tunnels.$TUNNEL_NAME.local_port" "$CLIENT_CONFIG")
    REMOTE_PORT=$(yq eval ".tunnels.$TUNNEL_NAME.remote_port" "$CLIENT_CONFIG")

    if [ -z "$LOCAL_PORT" ] || [ "$LOCAL_PORT" = "null" ] || [ -z "$REMOTE_PORT" ] || [ "$REMOTE_PORT" = "null" ]; then
        echo "Warning: Skipping tunnel '$TUNNEL_NAME' - missing local_port or remote_port"
        continue
    fi

    TUNNEL_LOG="$LOG_DIR/tunnel_${TUNNEL_NAME}.log"

    echo "Starting tunnel '$TUNNEL_NAME': $REMOTE_HOST:$REMOTE_PORT -> $TARGET_HOST:$LOCAL_PORT"

    # Start autossh tunnel for this port pair
    autossh -M 0 \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -o ExitOnForwardFailure=yes \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o IdentitiesOnly=yes \
        -R ${REMOTE_PORT}:${TARGET_HOST}:${LOCAL_PORT} \
        -i "$SSH_KEY_PATH" \
        -N \
        -f \
        -E "$TUNNEL_LOG" \
        ${REMOTE_USER}@${REMOTE_HOST}

    # Wait a moment for autossh to start
    sleep 1

    # Check if tunnel started successfully
    if pgrep -f "autossh.*-R.*${REMOTE_PORT}:${TARGET_HOST}:${LOCAL_PORT}.*${REMOTE_HOST}" > /dev/null; then
        echo "  ✓ Tunnel '$TUNNEL_NAME' established successfully"
        TUNNEL_COUNT=$((TUNNEL_COUNT + 1))
    else
        echo "  ✗ Failed to start tunnel '$TUNNEL_NAME'"
        FAILED_TUNNELS="$FAILED_TUNNELS $TUNNEL_NAME"
        echo "  Check log: $TUNNEL_LOG"
    fi
done

echo ""
echo "=========================================="
echo "Started $TUNNEL_COUNT tunnel(s)"
if [ -n "$FAILED_TUNNELS" ]; then
    echo "Failed tunnels:$FAILED_TUNNELS"
    echo "=========================================="
    exit 1
fi
echo "=========================================="
echo ""

# Print service URLs (direct port access)
echo "=========================================="
echo "Services are available at:"
echo "=========================================="
for TUNNEL_NAME in $TUNNEL_NAMES; do
    REMOTE_PORT=$(yq eval ".tunnels.$TUNNEL_NAME.remote_port" "$CLIENT_CONFIG")
    if [ -n "$REMOTE_PORT" ] && [ "$REMOTE_PORT" != "null" ]; then
        echo "  http://${REMOTE_HOST}:${REMOTE_PORT}"
    fi
done
echo "=========================================="
echo ""

# Monitor tunnel health
echo "Monitoring tunnel health..."
echo "Logs directory: $LOG_DIR"
echo "Individual tunnel logs:"
for TUNNEL_NAME in $TUNNEL_NAMES; do
    echo "  - tunnel_${TUNNEL_NAME}.log"
done
echo ""
echo "Check logs in $LOG_DIR or use 'tail -f $LOG_DIR/tunnel_*.log'"
echo ""

# Keep running and monitor tunnel health
while true; do
    sleep 30
    RUNNING_TUNNELS=$(pgrep -f "autossh.*${REMOTE_HOST}" | wc -l)
    if [ "$RUNNING_TUNNELS" -lt "$TUNNEL_COUNT" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Warning: Only $RUNNING_TUNNELS out of $TUNNEL_COUNT tunnels are running"
    fi
    # Exit if all tunnels die
    if [ "$RUNNING_TUNNELS" -eq 0 ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Error: No autossh processes found for $REMOTE_HOST"
        echo "All tunnels have stopped. Exiting..."
        exit 1
    fi
done
