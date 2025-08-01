FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    ruby xvfb xdotool ffmpeg chocolate-doom curl unzip nodejs npm wget \
    && rm -rf /var/lib/apt/lists/*

RUN wget -O /tmp/buildkite-agent.tar.gz https://github.com/buildkite/agent/releases/latest/download/buildkite-agent-linux-amd64.tar.gz \
    && tar -xzf /tmp/buildkite-agent.tar.gz -C /tmp \
    && mv /tmp/buildkite-agent /usr/local/bin/ \
    && chmod +x /usr/local/bin/buildkite-agent \
    && rm /tmp/buildkite-agent.tar.gz

RUN npm install -g @anthropic-ai/claude-code

RUN mkdir -p /usr/share/games/doom \
    && curl -L -o /tmp/doom.zip https://www.doomworld.com/3ddownloads/ports/shareware_doom_iwad.zip \
    && unzip -j /tmp/doom.zip -d /usr/share/games/doom/ \
    && rm /tmp/doom.zip

ENV DISPLAY=:1
COPY doom.rb /doom.rb
CMD ["ruby", "/doom.rb"]
