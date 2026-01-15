# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Docker-based reverse SSH tunnel solution that exposes local services through a remote server with automatic nginx configuration and HTTPS support. It uses `autossh` for persistent, self-healing SSH tunnels.

## Architecture

```
┌─────────────────┐     SSH Reverse Tunnel      ┌─────────────────┐
│  Local Machine  │◄────────────────────────────│  Remote Server  │
│                 │    (local_port → remote_port)│                 │
│  ┌───────────┐  │                              │  ┌───────────┐  │
│  │   Docker  │  │                              │  │   nginx   │  │
│  │ Container │──┼──────────────────────────────┼──▶│   Proxy   │  │
│  │           │  │   Copies nginx config        │  │           │  │
│  │ autossh x N│  │   via SSH                   │  └───────────┘  │
│  └───────────┘  │                              └─────────────────┘
└─────────────────┘                                    ▲
                                                       │
                                                   Users
```

**Flow:**
1. `entrypoint.sh` reads `tunnel.yml` configuration
2. Generates nginx config (if enabled) and copies to remote server via SSH
3. Starts multiple `autossh` processes (one per tunnel) for reverse port forwarding
4. Each tunnel forwards `remote_port` on remote server to `local_port` on local machine

## Key Files

| File | Purpose |
|------|---------|
| `entrypoint.sh` | Main entrypoint - parses YAML, generates nginx config, starts autossh processes |
| `Dockerfile` | Alpine-based image with autossh, openssh-client, yq for YAML parsing |
| `docker-compose.yml` | Orchestrates container build/run with SSH key embedded |
| `set-server.sh` | One-time server setup script - configures SSH GatewayPorts, installs nginx/certbot |
| `tunnel.yml` | Main configuration file for server, nginx, and tunnel definitions |
| `nginx.example` | Legacy nginx template (not used at runtime) |

## Common Commands

**Development:**
```bash
# Build container with SSH key
docker compose build

# Start tunnels
docker compose up -d

# View logs
docker compose logs -f
tail -f logs/tunnel_app1.log

# Stop
docker compose down
```

**Server Setup (one-time, on remote server):**
```bash
scp set-server.sh user@remote:/tmp/
ssh user@remote
sudo bash /tmp/set-server.sh
```

**Testing SSH Connection:**
```bash
# Test SSH key and connectivity
ssh -i ec2.pem -o StrictHostKeyChecking=no user@host "echo 'Connected'"
```

## Configuration Details

**`tunnel.yml` Structure:**
- `server.REMOTE_HOST`: Remote server hostname/IP (required)
- `server.REMOTE_USER`: SSH username (default: ubuntu)
- `nginx.site_config_file_name`: Nginx config filename (optional, enables nginx integration)
- `nginx.server_name`: Domain for nginx (defaults to REMOTE_HOST)
- `nginx.https`: Enable HTTPS with certbot (requires custom domain)
- `nginx.certbot.*`: Certbot configuration (email, domains, renew_days)
- `tunnels`: Map of tunnel name → {local_port, remote_port}

**SSH Key Management:**
- Keys are embedded in Docker image at build time
- Key file must be in build context (e.g., `ec2.pem`)
- Container expects key at `/app/ssh/ec2.pem` by default

**Target Host:**
- Default: `localhost` (for host network mode)
- Use `host.docker.internal` to access services on host machine from container

## Important Implementation Notes

- **Host network mode**: Container runs with `network_mode: host` to access local services
- **Autossh monitoring**: Each tunnel runs as a separate autossh process with individual log file
- **Nginx config generated dynamically**: Uses `yy` tool to parse YAML and generate nginx location blocks
- **SSH GatewayPorts required**: Remote server must have `GatewayPorts yes` in sshd_config
- **server_names_hash_bucket_size**: Set to 64 in nginx to avoid config errors with long domain names
- **Non-destructive nginx updates**: Container continues running even if nginx config deployment fails
- **HTTPS with certbot**: Automatic certificate generation/renewal when `nginx.https: true`
