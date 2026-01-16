#!/bin/bash

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run as root (use sudo)"
    exit 1
fi

# Check if domain file argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <domain-config-file.yml>"
    echo ""
    echo "Example:"
    echo "  $0 configs/example.com.yml"
    exit 1
fi

DOMAIN_CONFIG="$1"

# Check if domain config file exists
if [ ! -f "$DOMAIN_CONFIG" ]; then
    echo "Error: Domain configuration file not found: $DOMAIN_CONFIG"
    exit 1
fi

# Initialize tput colors
if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    RED=""
    GREEN=""
    YELLOW=""
    BOLD=""
    RESET=""
fi

# Function to print colored output
print_success() {
    echo "${GREEN}✓${RESET} $1"
}

print_error() {
    echo "${RED}✗${RESET} $1"
}

print_warning() {
    echo "${YELLOW}⚠${RESET} $1"
}

print_info() {
    echo "${BOLD}ℹ${RESET} $1"
}

# Read configuration from YAML
DOMAIN_NAME=$(yq eval '.domain_name' "$DOMAIN_CONFIG")
LISTEN_PORT=$(yq eval '.listen_port // "80"' "$DOMAIN_CONFIG")
HTTPS_ENABLED=$(yq eval '.https.enabled // "false"' "$DOMAIN_CONFIG")
HTTPS_EMAIL=$(yq eval '.https.email // ""' "$DOMAIN_CONFIG")
HTTPS_WWW=$(yq eval '.https.www_domain // "true"' "$DOMAIN_CONFIG")
HTTPS_FORCE_RENEW=$(yq eval '.https.force_renew // "false"' "$DOMAIN_CONFIG")

# Validate required fields
if [ -z "$DOMAIN_NAME" ] || [ "$DOMAIN_NAME" = "null" ]; then
    print_error "domain_name is required in configuration file"
    exit 1
fi

# Display configuration
if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
    echo "${BOLD}==========================================${RESET}"
    echo "${BOLD}Domain Configuration${RESET}"
    echo "${BOLD}==========================================${RESET}"
else
    echo "=========================================="
    echo "Domain Configuration"
    echo "=========================================="
fi
echo "Domain: $DOMAIN_NAME"
echo "Listen Port: $LISTEN_PORT"
echo "HTTPS: $HTTPS_ENABLED"
if [ "$HTTPS_ENABLED" = "true" ]; then
    echo "Email: ${HTTPS_EMAIL:-not set}"
    echo "WWW Domain: $HTTPS_WWW"
fi
echo "Config File: $DOMAIN_CONFIG"
echo ""

SITES_AVAILABLE="/etc/nginx/sites-available"
SITES_ENABLED="/etc/nginx/sites-enabled"
SITES_AVAILABLE_FILE="$SITES_AVAILABLE/$DOMAIN_NAME"
SITES_ENABLED_FILE="$SITES_ENABLED/$DOMAIN_NAME"

# Check if nginx is installed
if ! command -v nginx &> /dev/null; then
    print_error "Nginx is not installed"
    echo "Please run './init.sh' first to initialize the server"
    exit 1
fi

# Generate nginx config
echo "Generating nginx configuration..."
NGINX_CONFIG=$(mktemp)

{
    echo "server {"
    echo "    listen $LISTEN_PORT;"
    echo "    server_name $DOMAIN_NAME;"
    echo ""

    # Read locations from YAML and generate location blocks
    LOCATION_COUNT=$(yq eval '.locations | length' "$DOMAIN_CONFIG")
    if [ "$LOCATION_COUNT" -gt 0 ] && [ "$LOCATION_COUNT" != "null" ]; then
        yq eval '.locations | to_entries[] | "\(.key)|\(.value.path)|\(.value.backend_port)"' "$DOMAIN_CONFIG" | while IFS='|' read -r name path port; do
            echo "    # Location: $name"
            echo "    location $path {"
            echo "        proxy_pass http://localhost:$port;"
            echo "        proxy_set_header Host \$host;"
            echo "        proxy_set_header X-Real-IP \$remote_addr;"
            echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;"
            echo "        proxy_set_header X-Forwarded-Proto \$scheme;"
            echo "    }"
            echo ""
        done
    fi

    echo "}"
} > "$NGINX_CONFIG"

echo "Generated nginx configuration:"
cat "$NGINX_CONFIG"
echo ""

# Install config
print_info "Installing nginx configuration..."
sudo cp "$NGINX_CONFIG" "$SITES_AVAILABLE_FILE"

# Create symlink in sites-enabled
print_info "Creating symbolic link..."
sudo ln -sf "$SITES_AVAILABLE_FILE" "$SITES_ENABLED_FILE"

# Test and reload nginx
print_info "Testing nginx configuration..."
if sudo nginx -t; then
    print_success "Nginx configuration test passed"
    print_info "Reloading nginx..."
    sudo systemctl reload nginx
    print_success "Nginx reloaded successfully"
else
    print_error "Nginx configuration test failed"
    rm -f "$NGINX_CONFIG"
    exit 1
fi

# Clean up temp file
rm -f "$NGINX_CONFIG"

# Handle HTTPS with certbot
if [ "$HTTPS_ENABLED" = "true" ]; then
    echo ""
    if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
        echo "${BOLD}==========================================${RESET}"
        echo "${BOLD}Configuring HTTPS${RESET}"
        echo "${BOLD}==========================================${RESET}"
    else
        echo "=========================================="
        echo "Configuring HTTPS"
        echo "=========================================="
    fi

    # Check if certbot is installed
    if ! command -v certbot &> /dev/null; then
        print_error "Certbot is not installed"
        echo "Please run './init.sh' first to install certbot"
        exit 1
    fi

    # Build domain list
    CERTBOT_DOMAINS="$DOMAIN_NAME"
    if [ "$HTTPS_WWW" = "true" ]; then
        CERTBOT_DOMAINS="$CERTBOT_DOMAINS www.$DOMAIN_NAME"
    fi

    echo "Domains: $CERTBOT_DOMAINS"
    echo ""

    # Build certbot command
    CERTBOT_ARGS="--nginx --non-interactive --agree-tos --redirect"

    if [ -n "$HTTPS_EMAIL" ] && [ "$HTTPS_EMAIL" != "null" ]; then
        CERTBOT_ARGS="$CERTBOT_ARGS --email $HTTPS_EMAIL"
    else
        CERTBOT_ARGS="$CERTBOT_ARGS --register-unsafely-without-email"
    fi

    # Add force-renew option if specified
    if [ "$HTTPS_FORCE_RENEW" = "true" ]; then
        CERTBOT_ARGS="$CERTBOT_ARGS --force-renewal"
    fi

    # Run certbot
    print_info "Running certbot..."
    DOMAIN_ARGS=""
    for domain in $CERTBOT_DOMAINS; do
        DOMAIN_ARGS="$DOMAIN_ARGS -d $domain"
    done

    sudo certbot $CERTBOT_ARGS $DOMAIN_ARGS

    if [ $? -eq 0 ]; then
        print_success "HTTPS configured successfully"
        print_info "Reloading nginx..."
        sudo systemctl reload nginx
        print_success "Nginx reloaded successfully"
    else
        print_warning "Certbot configuration failed or certificate already exists"
        print_info "Continuing anyway..."
    fi
fi

echo ""
if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
    echo "${BOLD}==========================================${RESET}"
    echo "${GREEN}${BOLD}Domain configuration completed!${RESET}"
    echo "${BOLD}==========================================${RESET}"
else
    echo "=========================================="
    echo "Domain configuration completed!"
    echo "=========================================="
fi
echo ""
echo "Summary:"
print_success "Nginx config: $SITES_AVAILABLE_FILE"
print_success "Symlink: $SITES_ENABLED_FILE"
if [ "$HTTPS_ENABLED" = "true" ]; then
    PROTOCOL="https"
else
    PROTOCOL="http"
fi
echo ""
echo "Your domain is configured at:"
echo "  $PROTOCOL://$DOMAIN_NAME/"
