FROM alpine:latest

# Install autossh, openssh-client, procps (for pgrep), and yq (for YAML parsing)
RUN apk add --no-cache autossh openssh-client procps yq

# Create directory for SSH keys and logs
RUN mkdir -p /app/ssh /app/logs

# SSH key is copied by prepare.sh script before build
# prepare.sh reads the path from client.yml and copies to client/private.key
COPY private.key /app/ssh/private.key
RUN chmod 600 /app/ssh/private.key

# Copy entrypoint script and client configuration
COPY entrypoint.sh /app/entrypoint.sh
COPY client.yml /app/client.yml
RUN chmod +x /app/entrypoint.sh

WORKDIR /app

# Set environment variables with defaults
ENV CLIENT_CONFIG=/app/client.yml
ENV LOG_DIR=/app/logs
ENV TARGET_HOST=localhost

ENTRYPOINT ["/app/entrypoint.sh"]

