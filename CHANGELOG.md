# Changelog

All notable changes to the cueBreaker release are documented here. cueBreaker
ships as a single product version — each entry corresponds to one published
`semsemyonoff/cuebreaker` image tag built from the pinned `backend`/`frontend`
submodule commits.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

<!-- Write notes for the next release here. "Cut release" promotes this
     section to ## [X.Y.Z] - <date> and uses it as the release body. -->

## [0.1.0] - 2026-07-21

First release of **cueBreaker** — a web UI for splitting single-file FLAC albums
into tagged per-track files using their CUE sheets. Point it at a folder of CD
images (one big `.flac` plus a `.cue`), pick an album, and split it; the source
files are never modified.

Ships as a single image for linux/amd64 and linux/arm64, with the splitter
toolchain (shntool 3.0.10, cuetools, FLAC) already inside — nothing to install
on the host.

### Added
- **Library browser** — scans the input directory for albums that are still a
  single file plus a CUE sheet, and presents them as an artist/album tree with
  full-text search. Albums that are already split, or whose CUE points at a
  missing or multi-file source, are filtered out rather than offered as broken
  entries.
- **Album view** — cover art, album metadata, source file and total duration,
  and the complete track list read from the CUE with each track's start time.
  Albums shipping more than one CUE sheet let you choose which to split by.
- **Waveform with cut lines** — the track boundaries from the CUE's `INDEX`
  values drawn over the album's timeline, with a timecode axis, so you can see
  where the splits will land before running one.
- **Splitting** — one click writes the tracks to the output directory: split with
  `shnsplit`, tagged from the CUE (artist, album, title, track number, year,
  genre), pregap removed, and the album cover copied alongside. Splits are
  serialized — one at a time — and report live per-track progress.
- **Process logs** — a collapsible log under the split button streams the whole
  pipeline (CUE parsed, source resolved, breakpoints, each track, tagging, cover,
  done) and opens itself when a split fails, showing the underlying tool's own
  error. A second log in the library sidebar explains every directory the scan
  skipped and why.
- **Resumable splits** — reloading the page mid-split re-attaches to the running
  job and its log; album URLs are shareable and open in a new tab.
- **CUE sheets in any encoding** — UTF-8 (with or without a BOM), Windows-1251,
  Windows-1252, Shift-JIS, EUC-KR and Latin-1 are detected and read, so non-Latin
  artist and track names survive the split.
- **Runs as your user** — the library is mounted read-only and the split tracks
  are written under your own UID/GID, not root's.

