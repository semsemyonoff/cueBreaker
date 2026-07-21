# syntax=docker/dockerfile:1
#
# Production image for cueBreaker — the Go API with the pre-built SPA embedded in
# the same static binary, plus the external splitter tools it shells out to. The
# build context is THIS deploy repo root, so both pinned submodules are visible:
#   frontend/ — React/Vite/TS SPA, built to static assets in stage 1
#   backend/  — Go server; embeds those assets and serves API + UI on :5000
#
# Build with ./build.sh (multi-arch, pushes) or `make release` / `make release-local`.
# This is fully self-contained: it does NOT depend on the dev stack.

# ---- Stage 1: build the SPA ----
FROM node:22-slim AS spa
WORKDIR /app
# Manifests first for layer caching. The committed frontend/.npmrc (registry
# concurrency cap) is brought in with the full source copy below before build.
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
# vite.config.ts pins base=/ — the backend serves the SPA from the site root.
RUN npm run build

# ---- Stage 2: build the Go binary with the SPA embedded ----
FROM golang:1.26-alpine AS build
WORKDIR /src
COPY backend/go.mod backend/go.sum ./
RUN go mod download
COPY backend/ ./
# web/dist is //go:embed'ed into the binary. The submodule ships only a
# placeholder there (and .dockerignore strips it), so drop the real bundle in
# before compiling.
COPY --from=spa /app/dist ./web/dist

# Product release version, baked at build time (build.sh passes the release tag,
# e.g. 1.2.3). The backend reports it at GET /api/version. No git history is
# needed in the image — .dockerignore strips .git — so the version is injected
# here instead of derived from a tag at runtime. Defaults to 0.0.0 for a plain
# `docker build` without --build-arg.
ARG APP_VERSION=0.0.0
# CGO off: a fully static binary, so the runtime stage needs no Go toolchain and
# no libc coupling to the builder image.
ENV CGO_ENABLED=0
RUN go build -trimpath -ldflags "-s -w -X main.version=${APP_VERSION}" \
      -o /out/cuebreaker ./cmd/cuebreaker

# ---- Stage 3: runtime ----
# Debian, not Alpine: shntool is packaged for Debian but not for Alpine, where it
# would have to be compiled from source on every build (and for every arch).
FROM debian:trixie-slim

# The splitter toolchain the backend shells out to:
#   shntool   — shnsplit (the actual split)
#   cuetools  — cuebreakpoints, cueprint (breakpoints + tag values from the CUE)
#   flac      — metaflac (writing tags and cover art into the output files)
# curl is only here for the container healthcheck.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        shntool cuetools flac curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /out/cuebreaker /usr/local/bin/cuebreaker

# Defaults matching the compose file's mounts. /input is the library of unsplit
# FLAC+CUE albums (mounted read-only); /output receives the split tracks.
ENV CUEBREAKER_INPUT_DIR=/input \
    CUEBREAKER_OUTPUT_DIR=/output \
    CUEBREAKER_PORT=5000 \
    TMPDIR=/tmp

# Created so a bind mount inherits a sane mode, and so the container starts even
# with nothing mounted. World-writable: self-hosters run this image under their
# own UID (compose `user:`) to get output files they own, and that UID has no
# passwd entry.
RUN mkdir -p /input /output && chmod 1777 /output

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=5 \
    CMD curl -fsS http://localhost:5000/api/version || exit 1

ENTRYPOINT ["/usr/local/bin/cuebreaker"]
