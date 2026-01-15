# Domain Configurations

This directory contains per-domain YAML configuration files. Each file defines nginx locations and HTTPS settings for a single domain.

## File Structure

Each YAML file represents one domain configuration:

```yaml
# Domain name - used as nginx server_name and config filename
domain_name: example.com

# HTTP port (default: 80)
listen_port: 80

# Location blocks - map URL paths to backend ports
locations:
  app1:
    path: /app1/
    backend_port: 8000

# HTTPS configuration
https:
  enabled: true
  email: admin@example.com
  www_domain: true
  force_renew: false
```

## Usage

### 1. Create a domain configuration file

Copy `example.com.yml` and rename it to your domain:

```bash
cp example.com.yml your-domain.com.yml
```

### 2. Edit the configuration

```yaml
domain_name: your-domain.com
listen_port: 80

locations:
  myapp:
    path: /myapp/
    backend_port: 9000

https:
  enabled: true
  email: you@example.com
  www_domain: true
  force_renew: false
```

### 3. Apply the configuration

Run the setup script from the server directory:

```bash
cd ..
sudo ./setup-server.sh servers/your-domain.com.yml
```

This will:
- Generate nginx configuration for `your-domain.com`
- Install it to `/etc/nginx/sites-available/your-domain.com`
- Create symlink in `/etc/nginx/sites-enabled/`
- If HTTPS is enabled, obtain SSL certificates via certbot
- Test and reload nginx

## Configuration Reference

### Required Fields

| Field | Description |
|-------|-------------|
| `domain_name` | Domain name (used for nginx server_name and config filename) |

### Optional Fields

| Field | Default | Description |
|-------|---------|-------------|
| `listen_port` | `80` | HTTP port for nginx to listen on |
| `locations` | `{}` | Map of location blocks (path → backend_port) |

### HTTPS Settings (`https`)

| Field | Default | Description |
|-------|---------|-------------|
| `enabled` | `false` | Enable HTTPS with Let's Encrypt |
| `email` | - | Email for certificate notifications |
| `www_domain` | `true` | Include www subdomain in certificate |
| `force_renew` | `false` | Force certificate renewal |

### Locations (`locations`)

Each location block maps a URL path to a backend port:

```yaml
locations:
  # Location identifier (for documentation only)
  myapp:
    path: /myapp/           # URL path prefix
    backend_port: 9000      # Port to forward to
```

## Multiple Domains

You can have multiple domain configuration files:

```
servers/
├── example.com.yml
├── another-domain.com.yml
└── third-domain.com.yml
```

Each domain will get its own nginx configuration file and SSL certificate.

## Updating a Domain

To update an existing domain configuration:

1. Edit the YAML file
2. Re-run the setup script:
   ```bash
   sudo ./setup-server.sh servers/example.com.yml
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
rm servers/example.com.yml
```

## Port Mapping

The `backend_port` in the domain YAML must match the `remote_port` in your client configuration.

**Client (`client/client.yml`):**
```yaml
tunnels:
  myapp:
    local_port: 5000
    remote_port: 9000  # Must match backend_port in domain YAML
```

**Domain (`servers/example.com.yml`):**
```yaml
locations:
  myapp:
    path: /myapp/
    backend_port: 9000  # Must match remote_port in client YAML
```
