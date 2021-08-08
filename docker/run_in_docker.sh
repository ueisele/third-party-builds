#!/usr/bin/env bash
set -e
SCRIPT_DIR=$(dirname $(readlink -f ${BASH_SOURCE[0]}))
source ${SCRIPT_DIR}/env

IMAGE_NAME="openjdk${ZULU_OPENJDK_RELEASE}-jdk:${ZULU_OPENJDK_VERSION}-zulu-ubi${UBI8_VERSION}"

function usage () {
    echo "$0: $1" >&2
    echo
    echo "Usage: BUILD=3.0 $0 apache/build.sh"
    echo
    return 1
}

function build_image () {  
    docker build \
        -t ${IMAGE_NAME} \
        --rm \
        --build-arg UBI8_VERSION=${UBI8_VERSION} \
        --build-arg ZULU_OPENJDK_RELEASE=${ZULU_OPENJDK_RELEASE} \
        --build-arg ZULU_OPENJDK_VERSION=${ZULU_OPENJDK_VERSION} \
        ${SCRIPT_DIR}
}

function run_in_image () {
    docker run --rm \
        -v "${SCRIPT_DIR}/..:/home/appuser/workspace" \
        --env CONFLUENT_GIT_REPO=${CONFLUENT_GIT_REPO} \
        --env BUILD=${BUILD} \
        --env MAVEN_REPO_ID=${MAVEN_REPO_ID} \
        --env MAVEN_URL=${MAVEN_URL} \
        --env MAVEN_USERNAME=${MAVEN_USERNAME} \
        --env MAVEN_PASSWORD=${MAVEN_PASSWORD} \
        --env SHOULD_PUBLISH=${SHOULD_PUBLISH} \
        ${IMAGE_NAME} workspace/$@
}

function main () {
    build_image
    run_in_image "$@"
}

main "$@"