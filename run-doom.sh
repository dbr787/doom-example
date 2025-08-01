#!/bin/bash

set -euo pipefail

# Build and run DOOM container with direct Buildkite agent access
docker build --no-cache -t doom-game .

exec docker run --rm \
  -v "${BUILDKITE_AGENT_JOB_API_SOCKET}:${BUILDKITE_AGENT_JOB_API_SOCKET}" \
  -e BUILDKITE_AGENT_JOB_API_SOCKET \
  -e BUILDKITE_AGENT_JOB_API_TOKEN \
  -e ANTHROPIC_API_KEY \
  doom-game
