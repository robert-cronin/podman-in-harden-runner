#!/usr/bin/env bash

set -eu -o pipefail

# Start Podman buildkit container with systemd-resolve for reliable DNS
CONTAINER_NAME="copa-buildkitd-$(date +%s)"
echo "Starting Podman buildkit container: ${CONTAINER_NAME}" >&2

# Start buildkit with slirp4netns networking and copy host resolv.conf
# This approach should work better in GitHub Actions environments
podman run -d --rm --name "${CONTAINER_NAME}" \
    --privileged \
    --network=host \
    --dns=8.8.8.8 \
    --dns=8.8.4.4 \
    --dns=1.1.1.1 \
    --dns=1.0.0.1 \
    docker.io/moby/buildkit:latest \
    --oci-worker-snapshotter=native >/dev/null

# Wait for container to be ready
echo "Waiting for buildkit container to be ready..." >&2
for i in {1..30}; do
    if podman inspect --format "{{.State.Status}}" "${CONTAINER_NAME}" 2>/dev/null | grep -q "running"; then
        echo "Container ${CONTAINER_NAME} is running" >&2
        break
    fi
    if [ $i -eq 30 ]; then
        echo "Container ${CONTAINER_NAME} failed to start" >&2
        exit 1
    fi
    sleep 1
done

# Test DNS resolution inside the container
echo "Testing DNS resolution in buildkit container..." >&2
if podman exec "${CONTAINER_NAME}" nslookup google.com >/dev/null 2>&1; then
    echo "DNS resolution working in container" >&2
else
    echo "WARNING: DNS resolution may not be working properly" >&2
fi

# Set buildkit address for copa to use
export COPA_BUILDKIT_ADDR="podman-container://${CONTAINER_NAME}"

# Function to cleanup container on exit
cleanup() {
    echo "Cleaning up Podman buildkit container: ${CONTAINER_NAME}" >&2
    podman kill "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    podman rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
}

# Set trap to cleanup on exit
trap cleanup EXIT INT TERM

echo "Started Podman buildkit container: ${CONTAINER_NAME}" >&2
echo "COPA_BUILDKIT_ADDR=${COPA_BUILDKIT_ADDR}" >&2