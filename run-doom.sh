#!/bin/bash
set -euo pipefail

# Mode will be determined by polling inside the container
echo "Starting game - mode will be determined via polling"

# Create shared directory for communication
SHARED_DIR=$(mktemp -d)
trap "rm -rf $SHARED_DIR" EXIT

echo "Starting DOOM container..."

# Log Docker configuration for debugging
echo "=== Docker Configuration ==="
echo "Docker version:"
docker version --format '{{.Server.Version}}' 2>/dev/null || echo "N/A"
echo "Buildx version:"
docker buildx version 2>/dev/null || echo "N/A"
echo "Current builder (full details):"
docker buildx inspect 2>/dev/null || echo "N/A"
echo "Available builders:"
docker buildx ls 2>/dev/null || echo "N/A"
echo "Docker daemon info:"
docker info --format 'Driver: {{.Driver}}
CgroupDriver: {{.CgroupDriver}}
Registry Mirrors: {{.RegistryConfig.Mirrors}}
Images: {{.Images}}
Containers: {{.Containers}}' 2>/dev/null || echo "N/A"
echo "Build cache info:"
docker system df --format 'table {{.Type}}\t{{.Total}}\t{{.Size}}\t{{.Reclaimable}}' 2>/dev/null || echo "N/A"
echo "============================"

# Build Docker image using default Docker configuration
echo "Building Docker image..."
if docker build -t doom-game . >/dev/null 2>&1; then
  echo "✅ Built successfully"
elif docker buildx build --load -t doom-game . >/dev/null 2>&1; then
  echo "✅ Built with buildx fallback" 
else
  echo "❌ Docker build failed"
  exit 1
fi

# Run container with shared volume and host user permissions
echo "Starting DOOM container..."
docker run --rm \
  -v "$SHARED_DIR:/shared" \
  -e ANTHROPIC_API_KEY \
  --user "$(id -u):$(id -g)" \
  doom-game &

DOCKER_PID=$!
echo "Container started with PID: $DOCKER_PID"

# Handle container requests
while kill -0 $DOCKER_PID 2>/dev/null; do
  # Upload pipeline requests
  if [[ -f "$SHARED_DIR/upload_pipeline" ]]; then
    echo "Uploading pipeline..."
    buildkite-agent pipeline upload --replace < "$SHARED_DIR/upload_pipeline"
    rm "$SHARED_DIR/upload_pipeline"
    touch "$SHARED_DIR/pipeline_uploaded"
  fi
  
  # Upload artifact requests  
  if [[ -f "$SHARED_DIR/upload_artifact" ]]; then
    file=$(cat "$SHARED_DIR/upload_artifact")
    if [[ -f "$SHARED_DIR/$file" ]]; then
      echo "Uploading artifact: $file"
      # Upload from shared directory but preserve filename
      cd "$SHARED_DIR" && buildkite-agent artifact upload "$file" && cd -
    fi
    rm "$SHARED_DIR/upload_artifact"
    touch "$SHARED_DIR/artifact_uploaded"
  fi
  
  # Annotation requests
  if [[ -f "$SHARED_DIR/create_annotation" ]]; then
    echo "Creating annotation..."
    buildkite-agent annotate < "$SHARED_DIR/create_annotation"
    rm "$SHARED_DIR/create_annotation"
    touch "$SHARED_DIR/annotation_created"
  fi
  
  # Metadata get requests
  if [[ -f "$SHARED_DIR/get_metadata" ]]; then
    key=$(cat "$SHARED_DIR/get_metadata")
    echo "Host: Getting metadata for key: $key"
    
    # Get metadata with retry logic
    value=""
    for attempt in {1..3}; do
      if value=$(buildkite-agent meta-data get "$key" 2>/dev/null); then
        break
      else
        echo "Host: Metadata get attempt $attempt failed for key: $key"
        sleep 0.5
      fi
    done
    
    # Write response atomically
    echo "$value" > "$SHARED_DIR/metadata_response.tmp"
    mv "$SHARED_DIR/metadata_response.tmp" "$SHARED_DIR/metadata_response"
    rm "$SHARED_DIR/get_metadata"
    echo "Host: Responded with value: '$value'"
  fi
  
  sleep 0.1
done

wait $DOCKER_PID
