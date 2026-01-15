# SSH Tunnel Client

Docker container that establishes reverse SSH tunnels to a remote server using `autossh`.

## Features

- **Multiple tunnels**: Configure multiple SSH tunnels in a single YAML file
- **Automatic reconnection**: Uses `autossh` to automatically reconnect if connection drops
- **Health monitoring**: Continuously monitors tunnel health and restarts failed tunnels
- **Individual logging**: Each tunnel has its own log file for easier debugging
- **Persistent**: Container runs continuously and restarts automatically

## Prerequisites

- Docker and Docker Compose installed
- SSH private key for accessing the remote server
- Remote server must be configured (see [Server Documentation](../server/README.md))

## Quick Start

1. **Copy your SSH key:**
   ```bash
   cp ~/.ssh/ec2.pem ./ec2.pem
   chmod 600 ./ec2.pem
   ```

2. **Configure tunnels in `client.yml`:**
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

3. **Build and start:**
   ```bash
   docker compose build
   docker compose up -d
   ```

4. **View logs:**
   ```bash
   # All container logs
   docker compose logs -f

   # Individual tunnel logs
   tail -f logs/tunnel_app1.log
   tail -f logs/tunnel_app2.log
   ```

## Configuration

### `client.yml`

```yaml
ssh:
  remote_host: your-host.com     # Remote server hostname or IP (required)
  remote_user: ubuntu            # SSH username (default: ubuntu)

tunnels:
  tunnel_name:                   # Unique identifier for the tunnel
    local_port: 5000             # Port on local machine to forward from
    remote_port: 8000            # Port on remote server to forward to
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLIENT_CONFIG` | `/app/client.yml` | Path to client configuration file |
| `SSH_KEY_PATH` | `/app/ssh/ec2.pem` | Path to SSH private key in container |
| `TARGET_HOST` | `localhost` | Target host for port forwarding |
| `LOG_DIR` | `/app/logs` | Directory for tunnel logs |

### Build Arguments

- **SSH_KEY_FILE**: Filename of the SSH key in the build context (default: `ec2.pem`)

## Accessing Services

Once tunnels are established, services are accessible via:

- **Direct port**: `http://your-host.com:remote_port`
- **Via nginx** (if configured on server): `http://your-host.com/tunnel_name/`

## Network Configuration

The container uses `host` network mode to access services running on the host machine.

To access a service in another Docker container:
- Use `host.docker.internal` (already configured in docker-compose.yml)
- Or change `network_mode` to `bridge` and use the service's container name

## Troubleshooting

### Tunnel fails to establish

- Verify SSH key permissions: `chmod 600 ./ec2.pem`
- Check remote server is accessible: `ssh -i ec2.pem user@host`
- Ensure remote server has been set up with `setup-server.sh`
- Verify `remote_port` is not already in use on remote server

### Container exits immediately

- Check logs: `docker compose logs`
- Verify `remote_host` is set correctly in `client.yml`
- Ensure SSH key is mounted correctly

### Connection drops frequently

- Check network connectivity
- Verify remote server SSH configuration allows port forwarding
- Review logs for specific error messages

## Security Notes

- **SSH keys are copied into the Docker image** - be aware that keys are embedded in the image
- Consider using Docker secrets or mounted volumes for production deployments
- **Never commit SSH keys to version control** - they are excluded via `.gitignore`

## Stopping the Container

```bash
docker compose down
```
