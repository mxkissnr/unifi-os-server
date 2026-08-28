# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A fork of [lemker/unifi-os-server](https://github.com/lemker/unifi-os-server) (Docker/Kubernetes
packaging for self-hosted UniFi OS Server). No app source lives here — this only repackages the
official, proprietary UniFi OS Server binary into a container. `README.md` is mostly unchanged
from upstream (Docker/K8s usage, env vars, ports are the same); treat `Dockerfile`,
`uos-entrypoint.sh`, `docker-compose.yaml`, and the workflows below as the source of truth for
what this fork actually builds and runs.

## Build: self-contained image extraction

`Dockerfile` builds the final image from scratch, with no dependency on a pre-built upstream base
image:

1. **Stage `extractor`** (`ubuntu:22.04`): downloads the official UOS Server installer binary for
   the target arch from Ubiquiti's firmware CDN (`fw-download.ubnt.com`), verifies it against the
   `sha256_checksum` published by Ubiquiti's firmware API (`ARG INSTALLER_SHA256_AMD64/ARM64`),
   then uses `binwalk` to carve the embedded OCI image out of the installer, unpacks its layers
   into `/rootfs`, and copies `uos-entrypoint.sh` in.
2. **Stage `scratch`**: just `COPY --from=extractor /rootfs /` plus version/label metadata and the
   entrypoint. No podman/systemd install step in the Dockerfile itself — systemd et al. already
   ship inside the extracted UniFi rootfs; the container's PID 1 execs into it directly
   (`exec /sbin/init`) at runtime.

`ARG UOS_SERVER_VERSION`, `ARG INSTALLER_URL_AMD64/ARM64`, and `ARG INSTALLER_SHA256_AMD64/ARM64`
are the four values that change on every UOS release — they're kept in lockstep by
`scripts/check-update.sh` (see below), which pulls all four from Ubiquiti's
`fw-update.ubnt.com/api/firmware-latest` in one shot. Do not bump the version ARG without also
updating the URL and checksum ARGs, or the build's `sha256sum -c` step will fail (by design).

## Release pipeline

Two independent GitHub Actions flows, chained by a PR:

1. **`check-update.yaml`** (daily cron) runs `scripts/check-update.sh`, which compares the
   `ARG UOS_SERVER_VERSION` in `Dockerfile` against Ubiquiti's firmware API and, if newer,
   patches the four ARGs in place and opens a PR (branch `update-uos/<version>`, label
   `uos-update`).
2. **`release-on-merge.yaml`** fires when that PR merges (or via manual `workflow_dispatch`):
   extracts the version from `Dockerfile`, creates a git tag + GitHub Release. It does **not**
   build/push the image itself — publishing the Release fires a `release: published` event,
   which `build-image.yaml` picks up to actually build and push
   `ghcr.io/mxkissnr/unifi-os-server` (multi-arch, semver + `latest` tags). Keep it that way —
   duplicating the `docker/build-push-action` step in both workflows means two redundant builds
   racing to push the same tags.

`build-image.yaml` also builds (but doesn't push a versioned/`latest` tag for) any push to a
non-`main` branch, so feature/fix branches get their own preview image tagged by branch name.

There used to be a third, older pipeline (`extract-linux-amd64/arm64.yaml` → `build-uosserver.yaml`
→ a separate `create-pr` job in `release-check.yaml`) built around a two-image design where a
`uosserver` base image was extracted via `podman` on the runner and referenced from a
`FROM ghcr.io/.../uosserver:TAG-multiarch` line in `Dockerfile`. That line no longer exists — the
current `Dockerfile` extracts everything itself — so that pipeline was dead weight (and its
`create-pr` step would have corrupted the multi-line `ENV` block in `Dockerfile` with a blind
`sed` if it had ever actually run). It was removed; if you find yourself wanting to resurrect a
runner-side `podman extract` step, don't — extend the `extractor` stage in `Dockerfile` instead so
there's exactly one place that knows how to unpack the installer.

## Runtime (`uos-entrypoint.sh`)

Bootstraps a few things systemd/UniFi expect before `exec /sbin/init`: a stable `UOS_UUID` in
`/data/uos_uuid` (persisted across restarts), version/platform files under `/usr/lib`, log dirs
for nginx/mongodb/rabbitmq, and `system.properties` (`system_ip`, optionally external MongoDB
settings via `MONGO_INTERNAL=false`). `UOS_SYSTEM_IP` is required and the container exits if it's
unset. Journald output is piped to stdout so `docker logs` shows the actual UniFi service logs,
not just the entrypoint's own lines.

## docker-compose.yaml

`UOS_SYSTEM_IP=127.0.0.1` and the local bind mounts (`./uosserver`, `./var-lib-unifi`, `./data`)
are placeholders — a real deployment needs the host's actual reachable IP/hostname so devices can
be adopted. `privileged: true` + `cgroup: host` are required because UniFi OS Server runs its
components as systemd services needing host cgroup access (see README FAQ) — don't try to narrow
this to specific capabilities without confirming systemd still starts cleanly in the container,
since that hasn't been verified end-to-end against real UniFi hardware/adoption from this
environment.

## Upstream sync

There is no tracked upstream remote configured — `git remote -v` shows only `origin` (this fork).
`build-image.yaml`, `kubernetes/`, `LICENSE`, and most of `README.md` still match upstream;
`Dockerfile`, `uos-entrypoint.sh`, `check-update.yaml`/`check-update.sh`, and
`release-on-merge.yaml` are this fork's own build/release design and diverge substantially.
