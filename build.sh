#!/usr/bin/env bash
# Build and push the multi-arch cueBreaker production image from the pinned
# submodules. Build context is this repo root (see Dockerfile).
#
# Shared by the local `make release` AND by both CI pipelines (GitHub Actions →
# Docker Hub + GHCR; Forgejo Actions → git.horn). The caller picks the targets:
#
#   CUEBREAKER_IMAGES   space/newline-separated list of image refs WITHOUT tag
#                       (default: semsemyonoff/cuebreaker). Every image is tagged
#                       with every CUEBREAKER_TAGS value in a single buildx --push,
#                       so the image is built ONCE and fanned out to all targets.
#   CUEBREAKER_TAGS     space-separated list of tags (default: latest)
#   CUEBREAKER_VERSION  product version baked into the image as APP_VERSION (the
#                       backend reports it at GET /api/version). Defaults to the
#                       first non-"latest" tag, then to ./VERSION, then 0.0.0 — so
#                       CI needs no extra wiring (the release version is already
#                       the first CUEBREAKER_TAGS value).
#   CUEBREAKER_PLATFORMS  buildx platforms (default: linux/amd64,linux/arm64)
#
# `docker login` to each target registry must already be done by the caller.
set -euo pipefail
cd "$(dirname "$0")"

IMAGES="${CUEBREAKER_IMAGES:-semsemyonoff/cuebreaker}"
TAGS="${CUEBREAKER_TAGS:-latest}"
PLATFORMS="${CUEBREAKER_PLATFORMS:-linux/amd64,linux/arm64}"

# Product version baked into the image (APP_VERSION). Prefer an explicit
# CUEBREAKER_VERSION; otherwise take the first tag that isn't "latest" (CI passes
# "$version latest"), then fall back to ./VERSION, then 0.0.0.
VERSION="${CUEBREAKER_VERSION:-}"
if [ -z "$VERSION" ]; then
    for t in $TAGS; do
        if [ "$t" != latest ]; then VERSION="$t"; break; fi
    done
fi
VERSION="${VERSION:-$(cat VERSION 2>/dev/null || echo 0.0.0)}"

for sub in backend frontend; do
    if [ ! -e "$sub/.git" ]; then
        echo "ERROR: submodule '$sub' not initialized — run 'git submodule update --init'." >&2
        exit 1
    fi
done

# Fan out: one --tag per (image, tag) pair → built once, pushed everywhere.
tag_args=()
refs=()
for img in $IMAGES; do
    for t in $TAGS; do
        tag_args+=( --tag "${img}:${t}" )
        refs+=( "${img}:${t}" )
    done
done
echo ">> building ${PLATFORMS} (APP_VERSION=${VERSION}) and pushing:"
printf '   %s\n' "${refs[@]}"

# Pick the buildx builder.
#   CUEBREAKER_BUILDER set  -> use it as-is (e.g. "default" on a daemon with the
#                              containerd image store, which multi-arch-builds and
#                              pushes through the daemon itself — so it inherits the
#                              daemon's DNS and registry CA trust; needed for the
#                              internal git.horn push from the Forgejo dind runner).
#   unset                   -> manage a docker-container builder, required where the
#                              default builder can't do multi-arch (GitHub runners,
#                              local Docker without the containerd store).
if [ -n "${CUEBREAKER_BUILDER:-}" ]; then
    docker buildx use "$CUEBREAKER_BUILDER"
else
    BUILDER="cueBreaker-multiarch"
    if ! docker buildx inspect "$BUILDER" &>/dev/null; then
        docker buildx create --name "$BUILDER" --use
    else
        docker buildx use "$BUILDER"
    fi
fi

docker buildx build \
    --platform "$PLATFORMS" \
    --build-arg "APP_VERSION=${VERSION}" \
    "${tag_args[@]}" \
    --push .
