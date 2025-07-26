#!/bin/bash
set -euo pipefail

# Mode will be determined by polling inside the container
echo "Starting game - mode will be determined via polling"

# Create shared directory for communication
SHARED_DIR=$(mktemp -d)
trap "rm -rf $SHARED_DIR" EXIT

echo "Starting DOOM container..."

# Run DOOM container with shared volume
docker run --rm \
  -v "$SHARED_DIR:/shared" \
  -e ANTHROPIC_API_KEY \
  -e BUILDKITE_BUILD_NUMBER \
  -e BUILDKITE_ORGANIZATION_SLUG \
  -e BUILDKITE_PIPELINE_SLUG \
  $(docker build -q .) &

DOCKER_PID=$!

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
    value=$(buildkite-agent meta-data get "$key" 2>/dev/null || echo "")
    echo "$value" > "$SHARED_DIR/metadata_response"
    rm "$SHARED_DIR/get_metadata"
  fi
  
  sleep 0.1
done

wait $DOCKER_PID
