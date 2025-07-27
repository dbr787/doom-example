# Docker container for running interactive DOOM game in Buildkite pipelines
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install required packages for running DOOM and capturing gameplay
RUN apt-get update && apt-get install -y --no-install-recommends \
    ruby \
    xvfb \
    xdotool \
    ffmpeg \
    chocolate-doom \
    curl \
    unzip \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI for AI integration
RUN npm install -g @anthropic-ai/claude-code

# Download DOOM shareware WAD file (free to use)
RUN mkdir -p /usr/share/games/doom \
    && curl -L -o /tmp/doom.zip "https://www.doomworld.com/3ddownloads/ports/shareware_doom_iwad.zip" \
    && unzip -j /tmp/doom.zip -d /usr/share/games/doom/ \
    && rm /tmp/doom.zip

# Create non-root user for security
RUN useradd --create-home doom
ENV DISPLAY=:1
USER doom
WORKDIR /home/doom

# Copy game orchestration script (cache busted by file hash)
ARG DOOM_HASH
RUN echo "Cache bust: $DOOM_HASH"
COPY doom.rb .
RUN chmod 755 doom.rb && chown doom:doom doom.rb

CMD ["./doom.rb"]
