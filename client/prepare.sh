#!/bin/bash

set -e

CLIENT_CONFIG="client.yml"
OUTPUT_KEY="private.key"

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
