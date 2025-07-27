#!/bin/bash
set -euo pipefail

echo "Starting interactive DOOM game via Buildkite pipeline..."

# Create temporary directory for host-container communication
SHARED_DIR=$(mktemp -d)
trap "rm -rf $SHARED_DIR" EXIT

# Build and start the DOOM container
echo "Building Docker image..."
# Use doom.rb file hash to bust cache only when it changes
if command -v sha256sum >/dev/null; then
  DOOM_HASH=$(sha256sum doom.rb | cut -d' ' -f1 | head -c8)
else
  DOOM_HASH=$(shasum -a 256 doom.rb | cut -d' ' -f1 | head -c8)
fi
if docker build --build-arg DOOM_HASH="$DOOM_HASH" -t doom-game .; then
  echo "✅ Built successfully"
elif docker buildx build --load --build-arg DOOM_HASH="$DOOM_HASH" -t doom-game .; then
  echo "✅ Built successfully"
else
  echo "❌ Docker build failed"
  exit 1
fi

echo "Starting DOOM container..."
docker run --rm \
  -v "$SHARED_DIR:/shared" \
  -e ANTHROPIC_API_KEY \
  --user "$(id -u):$(id -g)" \
  doom-game &

DOCKER_PID=$!
echo "Container started with PID: $DOCKER_PID"

# Host-side handling of container requests via shared files
while kill -0 $DOCKER_PID 2>/dev/null; do
  # Handle dynamic pipeline creation requests from container
  if [[ -f "$SHARED_DIR/upload_pipeline" ]]; then
    echo "Uploading pipeline..."
    buildkite-agent pipeline upload --replace < "$SHARED_DIR/upload_pipeline"
    rm "$SHARED_DIR/upload_pipeline"
    touch "$SHARED_DIR/pipeline_uploaded"
  fi
  
  # Handle game screenshot uploads from container
  if [[ -f "$SHARED_DIR/upload_artifact" ]]; then
    file=$(cat "$SHARED_DIR/upload_artifact")
    if [[ -f "$SHARED_DIR/$file" ]]; then
      echo "Uploading artifact: $file"
      cd "$SHARED_DIR" && buildkite-agent artifact upload "$file" && cd -
    fi
    rm "$SHARED_DIR/upload_artifact"
    touch "$SHARED_DIR/artifact_uploaded"
  fi
  
  # Handle annotation requests from container  
  if [[ -f "$SHARED_DIR/create_annotation" ]]; then
    echo "Creating annotation..."
    buildkite-agent annotate < "$SHARED_DIR/create_annotation"
    rm "$SHARED_DIR/create_annotation"
    touch "$SHARED_DIR/annotation_created"
  fi
  
  # Handle metadata requests from container (user input from Buildkite UI)
  if [[ -f "$SHARED_DIR/get_metadata" ]]; then
    key=$(cat "$SHARED_DIR/get_metadata")
    echo "Getting metadata for key: $key"
    
    # Try to get metadata (single attempt since container will retry)
    value=$(buildkite-agent meta-data get "$key" 2>/dev/null) || value=""
    
    # Send response back to container
    echo "$value" > "$SHARED_DIR/metadata_response.tmp"
    mv "$SHARED_DIR/metadata_response.tmp" "$SHARED_DIR/metadata_response"
    rm "$SHARED_DIR/get_metadata"
    echo "Responded with value: '$value'"
  fi
  
  sleep 0.2
done

wait $DOCKER_PID
