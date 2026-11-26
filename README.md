# Kubernetes Container

This project provides a unified container image that bundles the core Kubernetes control plane components (kube-apiserver, kube-controller-manager, and kube-scheduler) into a single, lightweight Alpine-based image.

## Overview

The Kubernetes Control Plane Container offers:

- **Unified packaging**: All core control plane components in one container
- **Multi-architecture support**: Built for both `linux/amd64` and `linux/arm64`
- **Version tracking**: Automated daily builds for all stable Kubernetes releases
- **Minimal footprint**: Based on Alpine Linux for a smaller image size
- **Non-root execution**: Runs as a non-privileged user for enhanced security

## Available Images

Images are published to the GitHub Container Registry:

```
ghcr.io/loft-sh/kubernetes:v1.x.y
```

Where `v1.x.y` corresponds to the Kubernetes version.

## Usage

You can pull the image using:

```bash
docker pull ghcr.io/loft-sh/kubernetes:v1.28.0
```

## Building Locally

### Prerequisites

- Docker with buildx support
- Make

### Build Commands

Build the image locally:

```bash
make build
```

Build for a specific Kubernetes version:

```bash
make build K8S_VERSION=v1.29.0
```

Push to a registry:

```bash
make push REGISTRY=myregistry.io/ IMAGE_NAME=kubernetes
```

## Configuration Options

The build process can be customized with the following variables:

| Variable | Description | Default |
|----------|-------------|---------|
| K8S_VERSION | Kubernetes version to build | v1.28.0 |
| PLATFORMS | Target architectures | linux/amd64,linux/arm64 |
| IMAGE_NAME | Name of the container image | kubernetes-control-plane |
| REGISTRY | Container registry prefix | (empty) |

## Automated Builds

A GitHub Actions workflow runs daily to:

1. Identify all stable Kubernetes releases
2. Check for missing versions in the container registry
3. Automatically build and push images for any missing versions

## Go Dependency Pins (CVE Fixes)

When a scan reports a CVE in a Go dependency of the Kubernetes binaries that upstream has not fixed yet, pin the fixed version in the overlay for that minor version, `hack/kubernetes-v1.X`. The pins are a bash array, one `<module>@<version>` per line, with the CVE as a comment:

```bash
K8S_GO_DEP_PINS=(
  golang.org/x/net@v0.47.0        # CVE-2025-22872
  google.golang.org/grpc@v1.72.1  # CVE-2025-XXXX
)
```

Most overlays end without a trailing newline, so start the pins on a new line rather than appending them to the last one.

- When a pin raises a dependency of the Kubernetes version being built, the regular build compiles kube-apiserver, kube-controller-manager, kube-scheduler, kubelet, kubeadm and kubectl from source (`hack/Dockerfile.k8s-src`) instead of downloading them from dl.k8s.io; a version that already ships every pinned version keeps the dl.k8s.io binaries. The FIPS build always compiles from source and applies the same pins.
- A pin is a minimum version: `hack/pin-go-deps.sh` skips it when upstream already ships the same or a newer version, so a pin never downgrades. Remove the pin once the build log says it was skipped. A pin must name a module the Kubernetes version depends on and a release version (`vX.Y.Z`, not a pre-release or pseudo-version); otherwise the build fails.
- Pins cover only the Kubernetes binaries. For containerd, runc, etcd, helm and the rest, bump their version in the overlay.
- A pull request that changes the pins runs `.github/workflows/test-go-dep-pins.yaml` before anything is published: for each changed minor version, its latest patch release is built from source with the pins and must pass the Kubernetes unit tests (`make test`) and the full conformance suite on kind (`hack/run-conformance.sh`), which run in parallel. Expect about 2 to 3 hours. Run it manually for a minor version with `gh workflow run test-go-dep-pins.yaml -f k8s-minor-version=v1.35`.
- Existing releases are not rebuilt automatically. Run the `Kubernetes` and `Kubernetes FIPS` workflows with `force` set to `true`.

## Maintainer

This project is maintained by [Loft Labs Inc](https://loft.sh)
