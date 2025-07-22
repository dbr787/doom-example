FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages (use --no-install-recommends to keep image smaller)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ruby \
    ruby-dev \
    curl \
    wget \
    unzip \
    xvfb \
    xdotool \
    ffmpeg \
    chocolate-doom \
    build-essential \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Download DOOM shareware WAD
RUN mkdir -p /usr/share/games/doom \
    && curl -L --retry 3 --retry-delay 2 \
           -o /tmp/doom19s.zip \
           "https://www.doomworld.com/3ddownloads/ports/shareware_doom_iwad.zip" \
    && cd /tmp \
    && unzip -j doom19s.zip \
    && mv DOOM1.WAD /usr/share/games/doom/ \
    && ls -la /usr/share/games/doom/ \
    && file /usr/share/games/doom/DOOM1.WAD \
    || (echo "Primary download failed, trying alternative..." \
        && curl -L --retry 3 --retry-delay 2 \
               -o /tmp/dooms_19.zip \
               "https://archive.org/download/DoomsharewareEpisode/doom_shareware_episode.zip" \
        && cd /tmp \
        && unzip -j dooms_19.zip \
        && mv DOOM1.WAD /usr/share/games/doom/ 2>/dev/null || mv doom1.wad /usr/share/games/doom/DOOM1.WAD \
        && ls -la /usr/share/games/doom/ \
        && file /usr/share/games/doom/DOOM1.WAD \
        || echo "DOOM1.WAD download failed - needs to be provided manually")

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
