#!/usr/bin/env bash
set -e
SCRIPT_DIR=$(dirname $(readlink -f ${BASH_SOURCE[0]}))
BUILD_DIR=${SCRIPT_DIR}/build
source ${SCRIPT_DIR}/builds

KAFKA_GIT_REPO=${KAFKA_GIT_REPO:-https://github.com/apache/kafka.git}

function usage () {
    echo "$0: $1" >&2
    echo
    echo "Usage: MAVEN_USERNAME=user MAVEN_PASSWORD=password SHOULD_PUBLISH=true $0"
    echo
    return 1
}

function resolve_build_dir () {
    local kafka_git_refspec=${1:?"Missing Kafka Git refspec as first parameter!"}
    echo "${BUILD_DIR}/kafka-${kafka_git_refspec//\//-}"
}

function resolveKafkaVersion () {
    local kafka_git_refspec=${1:?"Missing Kafka Git refspec as first parameter!"}
    (
        cd "$(resolve_build_dir ${kafka_git_refspec})"
        local gradle_version=$(cat gradle.properties | sed -n 's/^version=\(.\+\)$/\1/p')
        if [[ ${gradle_version} == *-SNAPSHOT ]]; then
            echo ${gradle_version}
        else
            git fetch origin
            git describe --abbrev=7
        fi
    )
}

function cleanup_kafka_build () {
    local kafka_git_refspec=${1:?"Missing Kafka Git refspec as first parameter!"}
    echo "Removing Kafka build dir for ${kafka_git_refspec}"
    if [ -d "$(resolve_build_dir ${kafka_git_refspec})" ]; then
        rm -rf "$(resolve_build_dir ${kafka_git_refspec})"
    fi
}

function clone_kafka () {  
    local kafka_git_refspec=${1:?"Missing Kafka Git refspec as first parameter!"}
    echo "Cloning Kafka ${kafka_git_refspec}"
    (
        mkdir -p "$(resolve_build_dir ${kafka_git_refspec})"
        cd "$(resolve_build_dir ${kafka_git_refspec})"
        git init
        git remote add origin ${KAFKA_GIT_REPO}
        git fetch --depth 1 origin ${kafka_git_refspec}
        git reset --hard FETCH_HEAD
    )
}

function build_kafka () {
    local kafka_git_refspec=${1:?"Missing Kafka Git refspec as first parameter!"}
    echo "Building Kafka ${kafka_git_refspec}"
    (
        cd "$(resolve_build_dir ${kafka_git_refspec})"
        cat ${SCRIPT_DIR}/manifest.extension >> build.gradle
        ./gradlew jar \
            -Pversion=$(resolveKafkaVersion ${kafka_git_refspec}) \
            -PgitRepo=${KAFKA_GIT_REPO} -PgitCommitSha=$(git rev-parse HEAD) \
            --profile --no-daemon
    )
}

function publish_kafka () {
    local kafka_git_refspec=${1:?"Missing Kafka Git refspec as first parameter!"}
    echo "Publishing Kafka ${kafka_git_refspec} to ${MAVEN_URL}"
    (
        cd "$(resolve_build_dir ${kafka_git_refspec})"
        ./gradlew publish \
            -Pversion=$(resolveKafkaVersion ${kafka_git_refspec}) \
            -PskipSigning=true -PmavenUrl=${MAVEN_URL} -PmavenUsername=${MAVEN_USERNAME} -PmavenPassword=${MAVEN_PASSWORD} \
            --profile --no-daemon
    )
}

function build_and_publish () {
    for build in "${BUILDS[@]}"; do
        local kafka_git_refspec=$(git ls-remote ${KAFKA_GIT_REPO} ${build} | awk '{ print $1}')
        cleanup_kafka_build ${kafka_git_refspec}
        clone_kafka ${kafka_git_refspec}
        build_kafka ${kafka_git_refspec}
        if [ "${SHOULD_PUBLISH}" == "true" ]; then
            publish_kafka ${kafka_git_refspec}
        fi
    done
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
    if [ -z "${MAVEN_URL}" ] && [ "${SHOULD_PUBLISH}" == "true" ]; then
        usage "Missing env var MAVEN_URL: $1"
        return $?
    fi
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

    build_and_publish
}

main "$@"