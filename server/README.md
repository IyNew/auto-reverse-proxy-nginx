# Nginx & HTTPS Management Server

Native bash scripts for managing nginx reverse proxy configuration and HTTPS certificates on the remote server.

## Features

- **Per-domain configuration**: Each domain has its own YAML file
- **Dynamic nginx configuration**: Generate nginx config from YAML
- **HTTPS support**: Automatic SSL certificate management via certbot
- **Location blocks**: Map URL paths to backend ports
- **Easy deployment**: One script per domain

## Prerequisites

- Ubuntu/Debian based server with sudo access
- SSH access allowed
- Ports 80 and/or 443 open in firewall

## Quick Start

### 1. Copy server directory to remote server

```bash
scp -r server/ user@your-host.com:/opt/
```

### 2. SSH into server and initialize

```bash
ssh user@your-host.com
cd /opt/server

# Run one-time initialization (installs nginx, certbot, configures SSH)
sudo ./init.sh
```

### 3. Configure domains

Each domain gets its own configuration file in `configs/`:

```bash
# Copy the example configuration
cp configs/example.com.yml configs/your-domain.com.yml

# Edit the configuration
vim configs/your-domain.com.yml

# Apply the configuration
sudo ./setup-server.sh configs/your-domain.com.yml
```

## Scripts

### `init.sh`

One-time server initialization. Run this **once** when setting up a new server.

```bash
sudo ./init.sh
```

This script:
- Configures SSH GatewayPorts for reverse port forwarding
- Installs nginx
- Installs certbot
- Sets `server_names_hash_bucket_size` in nginx config
- Starts nginx service

### `setup-server.sh`

Configure a single domain. Run this for each domain you want to host.

```bash
sudo ./setup-server.sh configs/example.com.yml
```

This script:
- Reads the domain YAML file
- Generates nginx config with location blocks
- Installs config to `/etc/nginx/sites-available/{domain_name}`
- Creates symlink in `/etc/nginx/sites-enabled/`
- If HTTPS is enabled, obtains SSL certificates via certbot
- Tests and reloads nginx

## Domain Configuration

Domain configuration files are stored in `configs/` directory.

### Example (`configs/example.com.yml`)

```yaml
# Domain name - used as nginx server_name and config filename
domain_name: example.com

# HTTP port (default: 80)
listen_port: 80

# Define location blocks that map URL paths to backend ports
locations:
  app1:
    path: /app1/
    backend_port: 8000

  app2:
    path: /app2/
    backend_port: 8090

# HTTPS/SSL configuration
https:
  enabled: true
  email: admin@example.com
  www_domain: true
  force_renew: false
```

### Configuration Fields

| Field | Required | Description |
|-------|----------|-------------|
| `domain_name` | Yes | Domain name (used for nginx server_name and config filename) |
| `listen_port` | No | HTTP port (default: 80) |
| `locations` | No | Map of location blocks (path → backend_port) |
| `https.enabled` | No | Enable HTTPS with Let's Encrypt (default: false) |
| `https.email` | No | Email for certificate notifications |
| `https.www_domain` | No | Include www subdomain (default: true) |
| `https.force_renew` | No | Force certificate renewal (default: false) |

## Multiple Domains

You can host multiple domains on the same server:

```bash
# Setup first domain
sudo ./setup-server.sh configs/example.com.yml

# Setup second domain
sudo ./setup-server.sh configs/another-domain.com.yml

# Setup third domain
sudo ./setup-server.sh configs/third-domain.com.yml
```

Each domain gets:
- Its own nginx configuration file
- Its own SSL certificate (if HTTPS enabled)
- Independent location blocks

## Updating a Domain

To update an existing domain configuration:

1. Edit the YAML file:
   ```bash
   vim configs/example.com.yml
   ```

2. Re-run the setup script:
   ```bash
   sudo ./setup-server.sh configs/example.com.yml
   ```

The script will update the nginx configuration and reload nginx.

## Removing a Domain

To remove a domain configuration:

```bash
# Remove nginx configuration
sudo rm /etc/nginx/sites-available/example.com
sudo rm /etc/nginx/sites-enabled/example.com

# Remove SSL certificate (optional)
sudo certbot delete --cert-name example.com

# Reload nginx
sudo systemctl reload nginx

# Remove the YAML file
rm configs/example.com.yml
```

## Port Mapping

The `backend_port` in the domain YAML must match the `remote_port` in your client configuration.

**Client (`client/client.yml`):**
```yaml
tunnels:
  myapp:
    local_port: 5000
    remote_port: 9000
```

**Domain (`configs/example.com.yml`):**
```yaml
locations:
  myapp:
    path: /myapp/
    backend_port: 9000  # Must match remote_port
```

## Troubleshooting

### Nginx configuration fails

- Ensure `init.sh` has been run
- Verify nginx is installed: `nginx -v`
- Check nginx config syntax: `sudo nginx -t`
- Review logs: `sudo journalctl -u nginx`

### Certbot fails

- Ensure domain DNS is correctly configured
- Verify port 80 is open in firewall
- Check certbot logs: `sudo journalctl -u certbot`
- Ensure `domain_name` matches your domain

### Port already in use

- Check what's using the port: `sudo lsof -i :80`
- Stop conflicting services
- Choose a different port in the domain YAML

### "domain_name is required" error

- Ensure the YAML file has a `domain_name` field
- Check for proper YAML syntax

## Security Notes

- Server scripts require **sudo access** for nginx/certbot management
- Certbot requires root privileges for certificate management
- Ensure SSH keys are properly secured
- Keep certbot and nginx updated

## Manual Nginx Management

```bash
# Test configuration
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx

# Restart nginx
sudo systemctl restart nginx

# View nginx logs
sudo journalctl -u nginx -f

# List all configured sites
ls -la /etc/nginx/sites-available/
ls -la /etc/nginx/sites-enabled/
```

## Certificate Renewal

Certbot automatically sets up a systemd timer for certificate renewal.

```bash
# Check certbot timer
sudo systemctl status certbot.timer

# Manual renewal test
sudo certbot renew --dry-run

# View all certificates
sudo certbot certificates
```

## See Also

- [Domain Configurations Documentation](configs/README.md)
- [Client Documentation](../client/README.md)
