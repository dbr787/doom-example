FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    ruby xvfb xdotool ffmpeg chocolate-doom curl unzip nodejs npm wget gpg \
    && curl -fsSL https://keys.openpgp.org/vks/v1/by-fingerprint/32A37959C2FA5C3C99EFBC32A79206696452D198 | gpg --dearmor -o /usr/share/keyrings/buildkite-agent-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/buildkite-agent-archive-keyring.gpg] https://apt.buildkite.com/buildkite-agent stable main" > /etc/apt/sources.list.d/buildkite-agent.list \
    && apt-get update && apt-get install -y buildkite-agent \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

RUN mkdir -p /usr/share/games/doom \
    && curl -L -o /tmp/doom.zip https://www.doomworld.com/3ddownloads/ports/shareware_doom_iwad.zip \
    && unzip -j /tmp/doom.zip -d /usr/share/games/doom/ \
    && rm /tmp/doom.zip

ENV DISPLAY=:1
# Clear any old files and copy new one with different name
RUN rm -f /doom.rb /doom-game.rb
COPY doom-game.rb /game.rb
CMD ["ruby", "/game.rb"]
