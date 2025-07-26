FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install minimal dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ruby xvfb xdotool ffmpeg chocolate-doom curl unzip \
    && rm -rf /var/lib/apt/lists/*

# Get DOOM WAD
RUN mkdir -p /usr/share/games/doom \
    && curl -L -o /tmp/doom.zip "https://www.doomworld.com/3ddownloads/ports/shareware_doom_iwad.zip" \
    && unzip -j /tmp/doom.zip -d /usr/share/games/doom/ \
    && rm /tmp/doom.zip

# Setup user and environment
RUN useradd --create-home doom
ENV DISPLAY=:1
USER doom
WORKDIR /home/doom

# Copy script
COPY --chown=doom:doom doom.rb .
RUN chmod +x doom.rb

CMD ["./doom.rb"]
