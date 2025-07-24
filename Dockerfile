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
    && rm -rf /var/lib/apt/lists/*

# Container only needs DOOM dependencies, no buildkite-agent

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

# Copy container script (do this late to maximize cache hits)
COPY --chown=doom:doom doom_container.rb .

# Make container script executable
RUN chmod +x doom_container.rb

# Switch to non-root user
USER doom

# Set runtime working directory to writable location
WORKDIR /tmp

# Container script will be called by host with arguments
ENTRYPOINT ["./doom_container.rb"]
