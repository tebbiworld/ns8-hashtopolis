#!/bin/bash

#
# Copyright (C) 2026 tebbi
# SPDX-License-Identifier: GPL-3.0-or-later
#

# Terminate on error
set -e

# Prepare variables for later use
images=()
# The image will be pushed to the GitHub container registry
repobase="${REPOBASE:-ghcr.io/tebbiworld}"
# Configure the image name
reponame="hashtopolis"

# Pin the application images used at runtime. They are declared in the
# org.nethserver.images label so the node agent pre-pulls them and exposes
# their reference as ${BACKEND_IMAGE}, ${FRONTEND_IMAGE} and ${MYSQL_IMAGE}.
backend_image="docker.io/hashtopolis/backend:latest"
frontend_image="docker.io/hashtopolis/frontend:latest"
mysql_image="docker.io/library/mysql:8.0"

# Create a new empty container image
container=$(buildah from scratch)

# Reuse existing nodebuilder-hashtopolis container, to speed up builds
if ! buildah containers --format "{{.ContainerName}}" | grep -q nodebuilder-hashtopolis; then
    echo "Pulling NodeJS runtime..."
    buildah from --name nodebuilder-hashtopolis -v "${PWD}:/usr/src:Z" docker.io/library/node:24.16.0-slim
fi

echo "Build static UI files with node..."
buildah run \
    --workingdir=/usr/src/ui \
    --env="NODE_OPTIONS=--openssl-legacy-provider" \
    nodebuilder-hashtopolis \
    sh -c "yarn install && yarn build"

# Add imageroot and the compiled UI to the container image
buildah add "${container}" imageroot /imageroot
buildah add "${container}" ui/dist /ui
# Setup the entrypoint, reserve one TCP port (the module's own nginx is the only
# entry point), declare the runtime images and mark the module as rootless.
buildah config --entrypoint=/ \
    --label="org.nethserver.authorizations=traefik@node:routeadm" \
    --label="org.nethserver.tcp-ports-demand=1" \
    --label="org.nethserver.rootfull=0" \
    --label="org.nethserver.images=${backend_image} ${frontend_image} ${mysql_image}" \
    "${container}"
# Commit the image
buildah commit "${container}" "${repobase}/${reponame}"

# Append the image URL to the images array
images+=("${repobase}/${reponame}")

#
# Setup CI when pushing to Github.
# Warning! docker::// protocol expects lowercase letters (,,)
if [[ -n "${CI}" ]]; then
    # Set output value for Github Actions
    printf "images=%s\n" "${images[*],,}" >> "${GITHUB_OUTPUT}"
else
    # Just print info for manual push
    printf "Publish the images with:\n\n"
    for image in "${images[@],,}"; do printf "  buildah push %s docker://%s:%s\n" "${image}" "${image}" "${IMAGETAG:-latest}" ; done
    printf "\n"
fi
