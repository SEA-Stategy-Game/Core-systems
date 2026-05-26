# ==========================================
# STAGE 1: Build Environment (Intel Emulation on Mac, Native on Server)
# ==========================================
FROM --platform=linux/amd64 ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    unzip \
    wget \
    && rm -rf /var/lib/apt/lists/*

ENV GODOT_VERSION="4.3"

# Download standard x86_64 (Intel/AMD) Linux binaries
RUN wget -q https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip \
    && wget -q https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz

RUN unzip -q Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip \
    && mv Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot

RUN unzip -q Godot_v${GODOT_VERSION}-stable_export_templates.tpz \
    && mkdir -p /root/.local/share/godot/export_templates/${GODOT_VERSION}.stable \
    && mv templates/* /root/.local/share/godot/export_templates/${GODOT_VERSION}.stable/ \
    && rm -rf Godot_v* templates

WORKDIR /src
COPY . .

RUN rm -f /src/.godot/editor/editor_layout.cfg /src/.godot/editor/project_metadata.cfg
# This boots the editor to generate the UID file-path cache
# natively inside Linux, fixing the "invalid UID" errors
RUN godot --headless --verbose --quit
# Compile the project using your "Linux" preset
RUN mkdir -p /build \
    && godot --headless --export-release "Linux" /build/server.x86_64

# ==========================================
# STAGE 2: Lightweight Production Runtime (Intel/AMD)
# ==========================================
FROM --platform=linux/amd64 ubuntu:22.04

WORKDIR /app
COPY --from=builder /build/ /app/

EXPOSE 4242/udp

CMD ["./server.x86_64", "--headless"]