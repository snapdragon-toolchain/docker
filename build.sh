#!/bin/bash
#

REGISTRY_URL="ghcr.io/snapdragon-toolchain"

VERSION=$1; shift
[ "$VERSION" = "" ] && VERSION=$(./generate-version.sh)

TARGETS="$@"
[ "$TARGETS" = "" ] && TARGETS="arm64-android"

set -x

for T in $TARGETS; do
    docker buildx build --platform linux/amd64 --network=host --target $T --tag $REGISTRY_URL/$T:$VERSION . || exit 1
done
