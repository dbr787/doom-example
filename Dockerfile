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

# Default command - run the doom game
CMD ["./doom.rb"]
