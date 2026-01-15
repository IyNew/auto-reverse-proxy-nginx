# Reverse SSH Tunnel - Client/Server Architecture

A Docker-based reverse SSH tunnel solution split into client and server components for better separation of concerns.

## Architecture

```
┌─────────────────┐     SSH Reverse Tunnel      ┌─────────────────┐
│  Local Machine  │◄────────────────────────────│  Remote Server  │
│                 │    (local_port → remote_port)│                 │
│  ┌───────────┐  │                              │  ┌───────────┐  │
│  │   Client  │  │                              │  │   Server  │  │
│  │  Docker   │  │                              │  │  Scripts  │  │
│  │ Container │──┼──────────────────────────────┼──▶│ (native)  │  │
│  │           │  │                              │  │           │  │
│  │  autossh  │  │                              │  │   nginx   │  │
│  └───────────┘  │                              │  │  certbot  │  │
└─────────────────┘                              │  └───────────┘  │
                                                 └─────────────────┘
```

## Components

### **Client** (`client/`)
- Docker container that runs `autossh` for reverse SSH tunnels
- Manages tunnel configuration and health monitoring
- Forwards local ports to remote server ports

### **Server** (`server/`)
- Native bash scripts for nginx and HTTPS management
- Configures reverse proxy routing
- Manages SSL certificates via certbot

## Quick Start

### 1. Server Setup (run on remote server)

```bash
# Copy server directory to remote server
scp -r server/ user@your-host.com:/opt/

# SSH into server and setup
ssh user@your-host.com
cd /opt/server

# Run one-time setup
sudo ./setup-server.sh

# Configure nginx
sudo ./configure-nginx.sh

# Optionally enable HTTPS
sudo ./setup-certbot.sh
```

### 2. Client Setup (run on local machine)

```bash
cd client/

# Copy SSH key
cp ~/.ssh/ec2.pem ./ec2.pem
chmod 600 ./ec2.pem

# Edit client.yml with your configuration
vim client.yml

# Build and start
docker compose build
docker compose up -d

# View logs
docker compose logs -f
```

## Configuration

### Client Configuration (`client/client.yml`)

```yaml
ssh:
  remote_host: your-host.com
  remote_user: ubuntu

tunnels:
  app1:
    local_port: 5000
    remote_port: 8000
  app2:
    local_port: 4999
    remote_port: 8090
```

### Server Configuration (`server/server.yml`)

```yaml
nginx:
  site_config_file_name: reverse_proxy
  server_name: your-custom-domain.com
  listen_port: 80

  locations:
    app1:
      path: /app1/
      backend_port: 8000
    app2:
      path: /app2/
      backend_port: 8090

certbot:
  enabled: false
  email: your-email@example.com
  domains:
    - your-custom-domain.com
```

## Important Notes

- **Manual sync required**: When adding tunnels, update both `client/client.yml` (tunnels) and `server/server.yml` (locations) to keep ports in sync
- **Port mapping**: The `remote_port` in client.yml must match the `backend_port` in server.yml for each service
- **Client doesn't configure server**: The client container only establishes SSH tunnels - it does not remotely configure nginx anymore
- **Server scripts run natively**: No Docker required on the server side

## Documentation

- [Client Documentation](client/README.md)
- [Server Documentation](server/README.md)

## Security Notes

- SSH keys are embedded in the Docker image - consider using Docker secrets for production
- Server scripts require sudo access for nginx/certbot management
- Never commit SSH keys to version control
