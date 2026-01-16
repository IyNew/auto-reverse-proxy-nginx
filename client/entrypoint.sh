#!/bin/sh

set -e

# Configuration file path
CLIENT_CONFIG=${CLIENT_CONFIG:-/app/client.yml}
TARGET_HOST=${TARGET_HOST:-localhost}
LOG_DIR=${LOG_DIR:-/app/logs}

# SSH key is copied to a fixed location by prepare.sh
SSH_KEY_PATH=/app/ssh/private.key

# Check if client config file exists
if [ ! -f "$CLIENT_CONFIG" ]; then
    echo "Error: Client configuration file not found at $CLIENT_CONFIG"
    exit 1
fi

# Check if SSH key exists
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "Error: SSH key not found at $SSH_KEY_PATH"
    echo "The SSH key should have been copied into the image during build"
    echo "Run './prepare.sh' to copy the key to the build context"
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
echo "Use 'docker compose logs -f' or check logs in $LOG_DIR"
echo ""

# Keep container running and monitor tunnel health
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
