#!/bin/bash

set -e

echo "=========================================="
echo "Native Reverse Tunnel Client Setup"
echo "=========================================="
echo ""

# Detect OS
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

echo "Detected OS: $OS"
echo "Detected Architecture: $ARCH"
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install on macOS
install_macos() {
    echo "Installing dependencies for macOS..."
    
    if ! command_exists brew; then
        echo "Error: Homebrew is not installed"
        echo "Please install Homebrew first: https://brew.sh"
        exit 1
    fi
    
    if ! command_exists autossh; then
        echo "Installing autossh..."
        brew install autossh
    else
        echo "✓ autossh is already installed"
    fi
    
    if ! command_exists yq; then
        echo "Installing yq..."
        brew install yq
    else
        echo "✓ yq is already installed"
    fi
}

# Function to install on Linux (Debian/Ubuntu)
install_debian() {
    echo "Installing dependencies for Debian/Ubuntu..."
    
    if [ "$EUID" -ne 0 ]; then
        echo "This script requires sudo privileges to install packages"
        exit 1
    fi
    
    if ! command_exists autossh; then
        echo "Installing autossh..."
        apt-get update
        apt-get install -y autossh openssh-client procps
    else
        echo "✓ autossh is already installed"
    fi
    
    if ! command_exists yq; then
        echo "Installing yq..."
        # Try snap first
        if command_exists snap; then
            snap install yq
        else
            # Download binary
            YQ_VERSION="v4.44.3"
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
            
            YQ_BINARY="yq_linux_${YQ_ARCH}"
            curl -sL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" -o /usr/local/bin/yq
            chmod +x /usr/local/bin/yq
        fi
    else
        echo "✓ yq is already installed"
    fi
}

# Function to install on Alpine Linux
install_alpine() {
    echo "Installing dependencies for Alpine Linux..."
    
    if [ "$EUID" -ne 0 ]; then
        echo "This script requires root privileges to install packages"
        exit 1
    fi
    
    if ! command_exists autossh; then
        echo "Installing autossh..."
        apk add --no-cache autossh openssh-client procps
    else
        echo "✓ autossh is already installed"
    fi
    
    if ! command_exists yq; then
        echo "Installing yq..."
        apk add --no-cache yq
    else
        echo "✓ yq is already installed"
    fi
}

# Function to install on other Linux distributions
install_linux_generic() {
    echo "Installing dependencies for Linux (generic)..."
    echo ""
    echo "Please install the following packages manually:"
    echo "  - autossh"
    echo "  - openssh-client"
    echo "  - yq (from https://github.com/mikefarah/yq/releases)"
    echo ""
    echo "Common package managers:"
    echo "  - Fedora/RHEL: sudo dnf install autossh openssh-clients"
    echo "  - Arch: sudo pacman -S autossh openssh yq"
    echo "  - openSUSE: sudo zypper install autossh openssh yq"
    echo ""
    
    # Check if dependencies are installed
    if ! command_exists autossh; then
        echo "✗ autossh is not installed"
        exit 1
    fi
    
    if ! command_exists yq; then
        echo "✗ yq is not installed"
        exit 1
    fi
    
    echo "✓ All dependencies are installed"
}

# Install based on OS
case $OS in
    darwin)
        install_macos
        ;;
    linux)
        # Detect Linux distribution
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            case $ID in
                debian|ubuntu)
                    install_debian
                    ;;
                alpine)
                    install_alpine
                    ;;
                *)
                    install_linux_generic
                    ;;
            esac
        else
            install_linux_generic
        fi
        ;;
    *)
        echo "Unsupported OS: $OS"
        echo "Please install dependencies manually:"
        echo "  - autossh"
        echo "  - yq"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "Dependencies installed successfully!"
echo "=========================================="
echo ""

# Make entrypoint script executable
if [ -f "./entrypoint-native.sh" ]; then
    chmod +x ./entrypoint-native.sh
    echo "✓ Made entrypoint-native.sh executable"
fi

# Check if client.yml exists
if [ ! -f "./client.yml" ]; then
    echo ""
    echo "⚠ Warning: client.yml not found in current directory"
    echo "Please create a client.yml file with your configuration"
    echo ""
    echo "Example client.yml:"
    echo "---"
    echo "ssh:"
    echo "  remote_host: your-host.com"
    echo "  remote_user: ubuntu"
    echo "  private_key: ~/.ssh/id_rsa"
    echo ""
    echo "tunnels:"
    echo "  app1:"
    echo "    local_port: 5000"
    echo "    remote_port: 8000"
    echo ""
else
    echo "✓ Found client.yml"
fi

echo ""
echo "Setup complete! You can now run:"
echo "  ./entrypoint-native.sh"
echo ""
echo "Or run in the background:"
echo "  nohup ./entrypoint-native.sh > /dev/null 2>&1 &"
echo ""
