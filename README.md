# Colmap/Glomap Distrobox

## Rationale

Ubuntu ships with outdated, CPU-only Colmap which is also extremely slow for
large image collections. This Distrobox container packages recent builds of
Colmap and Glomap, built for CUDA 12.9.1 (so your host should have at least
12.9.1 for this to work).

## Prerequisites

This container is intended to be used with Distrobox, so install that first:

```bash
sudo apt install distrobox
```

Also, update Distrobox to use Docker (which should be installed as well) like
so:

```bash
mkdir -p ~/.config/distrobox
echo "container_manager='docker'" > ~/.config/distrobox
```

By default it uses Podman, which does not have some of the docker build
features that this container uses.

## Build

The build is the usual Docker build.

```bash
docker build -t photogrammetry:latest .
```

Enter the resulting container via distrobox, and export the tools:

```bash
distrobox enter photogrammetry
distrobox-export --bin /usr/local/bin/glomap
distrobox-export --bin /usr/local/bin/colmap
```

You can now exit the container - fresh build of glomap and colmap are available
directly on the host.
