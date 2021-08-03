#!/usr/bin/env bash
set -e
SCRIPT_DIR=$(dirname $(readlink -f ${BASH_SOURCE[0]}))
source ${SCRIPT_DIR}/env

IMAGE_NAME="openjdk${ZULU_OPENJDK_RELEASE}-jdk:${ZULU_OPENJDK_VERSION}-zulu-ubi${UBI8_VERSION}"

function usage () {
    echo "$0: $1" >&2
    echo
    echo "Usage: MAVEN_USERNAME=user MAVEN_PASSWORD=password SHOULD_PUBLISH=true $0"
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
        -v "${SCRIPT_DIR}:/home/appuser/workspace" \
        --env MAVEN_URL=${MAVEN_URL} \
        --env MAVEN_USERNAME=${MAVEN_USERNAME} \
        --env MAVEN_PASSWORD=${MAVEN_PASSWORD} \
        --env SHOULD_PUBLISH=${SHOULD_PUBLISH} \
        ${IMAGE_NAME} workspace/$@
}

function parseCmd () {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --publish)
                SHOULD_PUBLISH=true
                shift
                ;;
            *)
                usage "Unknown option: $1"
                return $?
                ;;
        esac
    done
    if [ -z "${MAVEN_USERNAME}" ] && [ "${SHOULD_PUBLISH}" == "true" ]; then
        usage "Missing env var MAVEN_USERNAME: $1"
        return $?
    fi
    if [ -z "${MAVEN_PASSWORD}" ] && [ "${SHOULD_PUBLISH}" == "true" ]; then
        usage "Missing env var MAVEN_PASSWORD: $1"
        return $?
    fi
    return 0
}
function main () {
    parseCmd "$@"
    local retval=$?
    if [ $retval != 0 ]; then
        exit $retval
    fi

    build_image
    run_in_image build.sh
}

main "$@"