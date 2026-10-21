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
# their reference as ${HASHTOPOLIS_BACKEND_IMAGE}, ${FRONTEND_IMAGE} and
# ${MYSQL_IMAGE} (basename uppercased, non-alphanumeric -> underscore).
#
# Hashtopolis release: the official frontend image and the backend source
# follow the same upstream tag.
frontend_image="docker.io/hashtopolis/frontend:v1.0.1"
hashtopolis_version="${frontend_image##*:}"
# The backend is built by this script from the upstream Dockerfile of that
# release, on a pinned PHP release instead of the floating php:8.5-apache the
# upstream image was built on: the published hashtopolis/backend images are
# only rebuilt with a Hashtopolis release, so they keep a vulnerable PHP for
# weeks (v1.0.1 runs PHP 8.5.10, affected by CVE-2026-109618/109619).
php_image="docker.io/library/php:8.5.12-apache"
php_version="${php_image##*:}"; php_version="${php_version%-apache}"
backend_image="${repobase,,}/hashtopolis-backend:${hashtopolis_version#v}-php${php_version}"
# MySQL 8.4 LTS (8.0 reached its end of life in April 2026). A data directory
# of 8.0 is upgraded in place on the first start of 8.4.
mysql_image="docker.io/library/mysql:8.4.11"

# Runtime images built here and still to be published (CI output below)
runtime_images=()

#
# 1) The backend image. A published tag is never rebuilt (the module label of
#    released versions points to it); BUILD_BACKEND=1 forces a local build,
#    PHP_IMAGE overrides the base for a local test (the version check below
#    still applies).
#
if [[ -n "${BUILD_BACKEND}" ]] || ! skopeo inspect --raw "docker://${backend_image}" >/dev/null 2>&1; then
    echo "Build ${backend_image}..."
    src=$(mktemp -d)
    trap 'rm -rf "${src}" "${src}.registries.conf"' EXIT
    git clone --quiet --depth 1 --branch "${hashtopolis_version}" https://github.com/hashtopolis/server.git "${src}"
    # Upstream pins the PHP minor release only; refuse to build when it has
    # moved on to another one than the pinned base.
    upstream_php=$(sed -n 's/^FROM php:\([0-9.]*\)-apache AS hashtopolis-server-base$/\1/p' "${src}/Dockerfile")
    if [[ -z "${upstream_php}" || "${php_version}" != "${upstream_php}".* ]]; then
        echo "Upstream Dockerfile base php:${upstream_php:-?}-apache does not match ${php_image}" >&2
        exit 1
    fi
    sed -i "s|^FROM php:${upstream_php}-apache AS hashtopolis-server-base$|FROM ${PHP_IMAGE:-${php_image}} AS hashtopolis-server-base|" "${src}/Dockerfile"
    # The upstream Dockerfile uses short image names (rust, alpine/git, php):
    # resolve them on Docker Hub without depending on the host's registries.conf
    printf 'unqualified-search-registries = ["docker.io"]\nshort-name-mode = "permissive"\n' > "${src}.registries.conf"
    CONTAINERS_REGISTRIES_CONF="${src}.registries.conf" \
    podman build --target hashtopolis-server-prod \
        --label="org.opencontainers.image.source=https://github.com/tebbiworld/ns8-hashtopolis" \
        --label="org.opencontainers.image.description=Hashtopolis ${hashtopolis_version} backend on PHP ${php_version}" \
        --label="org.opencontainers.image.version=${hashtopolis_version#v}-php${php_version}" \
        --label="org.opencontainers.image.revision=$(git -C "${src}" rev-parse HEAD)" \
        -t "${backend_image}" "${src}"
    built_php=$(podman run --rm --entrypoint php "${backend_image}" -r 'echo PHP_VERSION;')
    if [[ "${built_php}" != "${php_version}" ]]; then
        echo "Backend image runs PHP ${built_php}, expected ${php_version}" >&2
        exit 1
    fi
    echo "Backend image runs PHP ${built_php}"
    runtime_images+=("${backend_image}")
fi

#
# 2) The module image
#
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
# The bulk-data volumes can be placed on an additional disk at install time.
buildah config --entrypoint=/ \
    --label="org.nethserver.authorizations=traefik@node:routeadm" \
    --label="org.nethserver.tcp-ports-demand=1" \
    --label="org.nethserver.rootfull=0" \
    --label="org.nethserver.images=${backend_image} ${frontend_image} ${mysql_image}" \
    --label="org.nethserver.volumes=hashtopolis-data" \
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
    # runtime images are published under exactly their pinned tag
    printf "runtime_images=%s\n" "${runtime_images[*]}" >> "${GITHUB_OUTPUT}"
else
    # Just print info for manual push
    printf "Publish the images with:\n\n"
    for image in "${runtime_images[@]}"; do printf "  buildah push %s docker://%s\n" "${image}" "${image}" ; done
    for image in "${images[@],,}"; do printf "  buildah push %s docker://%s:%s\n" "${image}" "${image}" "${IMAGETAG:-latest}" ; done
    printf "\n"
fi
