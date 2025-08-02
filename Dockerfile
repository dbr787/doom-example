FROM ubuntu:22.04

# Install system dependencies (least likely to change)
RUN apt-get update && apt-get install -y \
    ruby xvfb xdotool ffmpeg chocolate-doom curl unzip nodejs npm wget gpg \
    && rm -rf /var/lib/apt/lists/*

# Install Claude CLI (changes when we update it)
RUN npm install -g @anthropic-ai/claude-code

# Install Buildkite agent (changes when agent updates)
RUN curl -fsSL https://keys.openpgp.org/vks/v1/by-fingerprint/32A37959C2FA5C3C99EFBC32A79206696452D198 | gpg --dearmor -o /usr/share/keyrings/buildkite-agent-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/buildkite-agent-archive-keyring.gpg] https://apt.buildkite.com/buildkite-agent stable main" > /etc/apt/sources.list.d/buildkite-agent.list \
    && apt-get update && apt-get install -y buildkite-agent \
    && rm -rf /var/lib/apt/lists/*

# Download DOOM shareware (rarely changes)
RUN mkdir -p /usr/share/games/doom \
    && curl -L -o /tmp/doom.zip https://www.doomworld.com/3ddownloads/ports/shareware_doom_iwad.zip \
    && unzip -j /tmp/doom.zip -d /usr/share/games/doom/ \
    && rm /tmp/doom.zip

# App code (changes most frequently)
ENV DISPLAY=:1
COPY doom.rb /doom.rb
CMD ["ruby", "/doom.rb"]
