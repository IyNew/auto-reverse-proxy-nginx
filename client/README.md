# SSH Tunnel Client

Client that establishes reverse SSH tunnels to a remote server using `autossh`. Can run natively or in Docker.

## Features

- **Multiple tunnels**: Configure multiple SSH tunnels in a single YAML file
- **Automatic reconnection**: Uses `autossh` to automatically reconnect if connection drops
- **Health monitoring**: Continuously monitors tunnel health and restarts failed tunnels
- **Individual logging**: Each tunnel has its own log file for easier debugging
- **Persistent**: Runs continuously and restarts automatically
- **Native or Docker**: Run natively on your system or in a Docker container

## Prerequisites

- SSH private key for accessing the remote server
- Remote server must be configured (see [Server Documentation](../server/README.md))
- For Docker: Docker and Docker Compose installed
- For Native: `autossh` and `yq` installed (see Native Installation below)

## Installation Methods

### Option 1: Native Installation (No Docker)

1. **Install dependencies:**
   ```bash
   ./setup-native.sh
   ```
   
   Or install manually:
   - **macOS**: `brew install autossh yq`
   - **Ubuntu/Debian**: `sudo apt-get install autossh && sudo snap install yq`
   - **Alpine**: `apk add autossh yq`

2. **Configure `client.yml`:**
   ```yaml
   ssh:
     remote_host: your-host.com
     remote_user: ubuntu
     private_key: ~/.ssh/id_rsa     # Full path to your SSH key

   tunnels:
     app1:
       local_port: 5000
       remote_port: 8000
     app2:
       local_port: 4999
       remote_port: 8090
   ```

3. **Run the tunnel:**
   ```bash
   # Run directly
   ./entrypoint-native.sh

   # Or use the wrapper script
   ./run-native.sh start

   # Check status
   ./run-native.sh status

   # View logs
   ./run-native.sh logs
   ```

4. **Run as a systemd service (Linux):**
   ```bash
   # Copy files to user config directory
   mkdir -p ~/.config/reverse-tunnel
   cp entrypoint-native.sh client.yml ~/.config/reverse-tunnel/
   cp reverse-tunnel.service ~/.config/systemd/user/

   # Edit the service file to match your user
   # Then enable and start
   systemctl --user enable reverse-tunnel.service
   systemctl --user start reverse-tunnel.service
   ```

### Option 2: Docker Installation

1. **Configure SSH key path in `client.yml`:**
   ```yaml
   ssh:
     remote_host: your-host.com
     remote_user: ubuntu
     private_key: ~/.ssh/id_rsa     # Full path to your SSH key

   tunnels:
     app1:
       local_port: 5000
       remote_port: 8000
     app2:
       local_port: 4999
       remote_port: 8090
   ```

2. **Prepare and build:**
   ```bash
   # Run prepare script to copy SSH key from client.yml path
   ./prepare.sh

   # Build and start container
   docker compose build
   docker compose up -d
   ```

3. **View logs:**
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
  private_key: ~/.ssh/id_rsa     # Full path to SSH private key (supports ~ expansion)

tunnels:
  tunnel_name:                   # Unique identifier for the tunnel
    local_port: 5000             # Port on local machine to forward from
    remote_port: 8000            # Port on remote server to forward to
```

**Note:** The `prepare.sh` script reads the `ssh.private_key` path and copies the key to `private.key` before building the Docker image.

### Environment Variables

| Variable | Default (Docker) | Default (Native) | Description |
|----------|------------------|------------------|-------------|
| `CLIENT_CONFIG` | `/app/client.yml` | `./client.yml` or `~/.config/reverse-tunnel/client.yml` | Path to client configuration file |
| `TARGET_HOST` | `localhost` | `localhost` | Target host for port forwarding |
| `LOG_DIR` | `/app/logs` | `./logs` or `~/.config/reverse-tunnel/logs` | Directory for tunnel logs |
| `SSH_KEY_PATH` | `/app/ssh/private.key` | Read from `client.yml` or `~/.ssh/id_rsa` | Path to SSH private key (native only) |

## Accessing Services

Once tunnels are established, services are accessible via:

- **Direct port**: `http://your-host.com:remote_port`
- **Via nginx** (if configured on server): `http://your-host.com/tunnel_name/`

## Network Configuration

### Docker Mode
The container uses `host` network mode to access services running on the host machine.

To access a service in another Docker container:
- Use `host.docker.internal` (already configured in docker-compose.yml)
- Or change `network_mode` to `bridge` and use the service's container name

### Native Mode
By default, `TARGET_HOST` is set to `localhost`. To forward to a different host:
- Set `TARGET_HOST` environment variable: `TARGET_HOST=192.168.1.100 ./entrypoint-native.sh`
- Or modify the script to use a different default

## Troubleshooting

### Tunnel fails to establish

- Verify SSH key permissions: `chmod 600 ~/.ssh/id_rsa` (or your key file)
- Check remote server is accessible: `ssh -i ~/.ssh/id_rsa user@host`
- Ensure remote server has been set up with `setup-server.sh`
- Verify `remote_port` is not already in use on remote server

### Container exits immediately

- Check logs: `docker compose logs`
- Verify `remote_host` is set correctly in `client.yml`
- Ensure you ran `./prepare.sh` before building (copies SSH key to `private.key`)
- Verify the `ssh.private_key` path in `client.yml` points to a valid SSH key file

### Connection drops frequently

- Check network connectivity
- Verify remote server SSH configuration allows port forwarding
- Review logs for specific error messages

## Security Notes

- **SSH keys are copied into the Docker image** - the `prepare.sh` script copies your key to `private.key` which is embedded in the image
- `private.key` is excluded from version control via `.gitignore`
- Consider using Docker secrets or mounted volumes for production deployments if security is a concern

## Stopping the Service

### Docker Mode
```bash
docker compose down
```

### Native Mode
```bash
# Using the wrapper script
./run-native.sh stop

# Or manually kill the process
pkill -f "entrypoint-native.sh"
pkill -f "autossh.*-R"
```

## Native vs Docker: Which Should I Use?

**Use Native if:**
- You prefer not to use Docker
- You want lower resource usage
- You need direct access to system services
- You're running on a system without Docker

**Use Docker if:**
- You want containerized isolation
- You're already using Docker in your workflow
- You need consistent environment across different systems
- You prefer container-based deployment
