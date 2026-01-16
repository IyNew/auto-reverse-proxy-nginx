#!/bin/bash

set -e

CLIENT_CONFIG="client.yml"
OUTPUT_KEY="private.key"

# Check if yq is installed
if ! command -v yq &> /dev/null; then
    echo "yq not found. Installing yq..."

    # Detect OS and architecture
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    case $ARCH in
        x86_64|amd64)
            YQ_ARCH="amd64"
            ;;
        aarch64|arm64)
            YQ_ARCH="arm64"
            ;;
        armv7l|armv6l)
            YQ_ARCH="arm"
            ;;
        *)
            echo "Error: Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    YQ_VERSION="v4.44.3"
    YQ_BINARY="yq_${OS}_${YQ_ARCH}"

    # Download yq
    if curl -sL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" -o /usr/local/bin/yq 2>/dev/null; then
        chmod +x /usr/local/bin/yq
        echo "yq installed successfully"
    elif wget -q "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" -O /usr/local/bin/yq 2>/dev/null; then
        chmod +x /usr/local/bin/yq
        echo "yq installed successfully"
    else
        echo "Error: Failed to download yq"
        echo "Please install yq manually:"
        echo "  brew install yq  # macOS"
        echo "  or download from https://github.com/mikefarah/yq/releases"
        exit 1
    fi
fi

# Read SSH key path from client.yml
KEY_PATH=$(yq eval '.ssh.private_key' "$CLIENT_CONFIG")

if [ -z "$KEY_PATH" ] || [ "$KEY_PATH" = "null" ]; then
    echo "Error: ssh.private_key not found in $CLIENT_CONFIG"
    exit 1
fi

# Expand tilde if present
KEY_PATH="${KEY_PATH/#\~/$HOME}"

# Check if source key exists
if [ ! -f "$KEY_PATH" ]; then
    echo "Error: SSH key not found at $KEY_PATH"
    exit 1
fi

# Copy key to build location
echo "Copying SSH key from $KEY_PATH to $OUTPUT_KEY"
cp "$KEY_PATH" "$OUTPUT_KEY"
chmod 600 "$OUTPUT_KEY"
echo "SSH key prepared successfully: $OUTPUT_KEY"
