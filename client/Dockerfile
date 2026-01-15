FROM alpine:latest

# Install autossh, openssh-client, procps (for pgrep), and yq (for YAML parsing)
RUN apk add --no-cache autossh openssh-client procps yq

# Create directory for SSH keys and logs
RUN mkdir -p /app/ssh /app/logs

# Build argument for SSH key filename (key should be copied to build context)
# Default: ec2.pem (expects file to be in build context root)
ARG SSH_KEY_FILE=ec2.pem

# Copy SSH key into image
# The key file should be placed in the build context directory before building
COPY ${SSH_KEY_FILE} /app/ssh/ec2.pem
RUN chmod 600 /app/ssh/ec2.pem

# Copy entrypoint script and client configuration
COPY entrypoint.sh /app/entrypoint.sh
COPY client.yml /app/client.yml
RUN chmod +x /app/entrypoint.sh

WORKDIR /app

# Set environment variables with defaults
ENV SSH_KEY_PATH=/app/ssh/ec2.pem
ENV CLIENT_CONFIG=/app/client.yml
ENV LOG_DIR=/app/logs
ENV TARGET_HOST=localhost

ENTRYPOINT ["/app/entrypoint.sh"]

