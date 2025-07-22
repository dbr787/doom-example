FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages (use --no-install-recommends to keep image smaller)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ruby \
    ruby-dev \
    curl \
    wget \
    xvfb \
    xdotool \
    ffmpeg \
    chocolate-doom \
    build-essential \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Download DOOM1.WAD (do this early since it rarely changes)
RUN mkdir -p /usr/share/games/doom \
    && wget --retry-connrefused --waitretry=1 --read-timeout=20 --timeout=15 -t 3 \
           -O /tmp/doom1.wad \
           "https://archive.org/download/DoomsharewareEpisode/doom1.wad" \
    && mv /tmp/doom1.wad /usr/share/games/doom/DOOM1.WAD \
    || echo "DOOM1.WAD download failed - needs to be provided manually"

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

# Default command - run the doom game
CMD ["./doom.rb"]
