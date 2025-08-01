FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    ruby xvfb xdotool ffmpeg chocolate-doom curl unzip nodejs npm wget \
    && wget -qO- https://github.com/buildkite/agent/releases/latest/download/buildkite-agent-linux-amd64.tar.gz | tar -xz \
    && mv buildkite-agent /usr/local/bin/ \
    && npm install -g @anthropic-ai/claude-code \
    && mkdir -p /usr/share/games/doom \
    && curl -sL https://www.doomworld.com/3ddownloads/ports/shareware_doom_iwad.zip | unzip -j - -d /usr/share/games/doom/ \
    && rm -rf /var/lib/apt/lists/*

ENV DISPLAY=:1
COPY doom.rb /doom.rb
CMD ["ruby", "/doom.rb"]
