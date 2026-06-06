ARG TARGETPLATFORM=linux/amd64
FROM --platform=$TARGETPLATFORM ubuntu:22.04

# Install any essential runtime dependencies for Godot headless
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user for security
RUN useradd -m -s /bin/bash godot
USER godot

WORKDIR /app

# Copy the pre-built Linux exports
COPY --chown=godot:godot gameroom.x86_64 /app/
COPY --chown=godot:godot gameroom.pck /app/

# Make the binary executable
RUN chmod +x /app/gameroom.x86_64

# ENet uses UDP, default port is 12345
EXPOSE 12345/udp

# Entrypoint allowing arguments to be passed (e.g. --port)
ENTRYPOINT ["/app/gameroom.x86_64", "--headless"]
