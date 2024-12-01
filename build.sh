#!/bin/bash
VERSION=$1

if [ -z "$VERSION" ]; then echo "Version please."; exit; fi

echo "Building default/small:$VERSION"
docker buildx build --push --tag pannal/obs-hw-offload:latest --tag pannal/obs-hw-offload:latest-small --tag pannal/obs-hw-offload:$VERSION-small --platform linux/amd64 .

echo "Building stock:$VERSION"
docker buildx build --push --tag pannal/obs-hw-offload:latest-stock --tag pannal/obs-hw-offload:$VERSION-stock --platform linux/amd64 --build-arg FF_BUILD=stock .

echo "Building big:$VERSION"
docker buildx build --push --tag pannal/obs-hw-offload:latest-big --tag pannal/obs-hw-offload:$VERSION-big --platform linux/amd64 --build-arg FF_BUILD=big .

