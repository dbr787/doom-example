FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    ruby \
    curl \
    unzip \
    xvfb \
    xdotool \
    ffmpeg \
    chocolate-doom \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# Install Buildkite agent for container use
RUN curl -fsSL https://keys.openpgp.org/vks/v1/by-fingerprint/32A37959C2FA5C3C99EFBC32A79206696452D198 | gpg --dearmor -o /usr/share/keyrings/buildkite-agent-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/buildkite-agent-archive-keyring.gpg] https://apt.buildkite.com/buildkite-agent stable main" | tee /etc/apt/sources.list.d/buildkite-agent.list \
    && apt-get update \
    && apt-get install -y buildkite-agent \
    && rm -rf /var/lib/apt/lists/*

# Download DOOM shareware WAD
RUN mkdir -p /usr/share/games/doom \
    && curl -L -o /tmp/doom.zip "https://www.doomworld.com/3ddownloads/ports/shareware_doom_iwad.zip" \
    && unzip -j /tmp/doom.zip -d /usr/share/games/doom/ \
    && rm /tmp/doom.zip

# Create non-root user for security  
RUN useradd --create-home --shell /bin/bash doom \
    && chown -R doom:doom /usr/share/games/doom

# Set working directory
WORKDIR /app

# Set environment variables
ENV DISPLAY=:1

# Copy application files (do this late to maximize cache hits)
COPY --chown=doom:doom doom.rb .
COPY --chown=doom:doom .buildkite/ .buildkite/

# Make doom.rb executable
RUN chmod +x doom.rb

# Switch to non-root user
USER doom

# Set runtime working directory to writable location
WORKDIR /tmp

# Copy fresh code at runtime and execute
ENTRYPOINT ["sh", "-c", "cp /app/doom.rb /app/.buildkite -r . && exec ./doom.rb"]
