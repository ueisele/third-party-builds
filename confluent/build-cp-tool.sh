#!/usr/bin/env bash
set -e
SCRIPT_DIR=$(dirname $(readlink -f ${BASH_SOURCE[0]}))
BUILD_DIR=${SCRIPT_DIR}/build

MAVEN_URL=${MAVEN_URL:-https://packages.confluent.io/maven/}

function usage () {
    echo "$0: $1" >&2
    echo
    echo "Usage: CONFLUENT_GIT_REPO=https://github.com/confluentinc/rest-utils.git BUILD=7.0.0 MAVEN_REPO_ID=confluent-snapshots::default::\${MAVEN_URL} SHOULD_PUBLISH=true $0"
    echo
    return 1
}

function resolve_confluent_main_version () {
    local confluent_git_refspec=${1:?"Missing Confluent Git refspec as first parameter!"}
    (
        cd "$(resolve_build_dir ${confluent_git_refspec})"
        local maven_version="$(cat pom.xml | head -n50 | grep "<version>" | sed 's/.*>\([^<]*\)<.*/\1/')"
        echo ${maven_version} | sed 's/^\([0-9]\+\.[0-9]\+\.[0-9]\+\).*$/\1/'
    )
}

function resolve_confluent_version () {
    local confluent_git_refspec=${1:?"Missing Confluent Git refspec as first parameter!"}
    echo "$(resolve_confluent_main_version ${confluent_git_refspec})-SNAPSHOT"
}

function replace_value_in_pom () {
    local file=${1:?"Missing file as first parameter!"}
    local attribute=${2:?"Missing attribute as second parameter!"}
    local new_value=${3:?"Missing new value as third parameter!"}
    sed -i "s/<${attribute}>[^<]*<\/${attribute}>/<${attribute}>${new_value}<\/${attribute}>/" ${file}
}

function resolve_build_dir () {
    local confluent_git_refspec=${1:?"Missing Confluent Git refspec as first parameter!"}
    local repo_short_name=$(sed 's/^.*\/\([^.]\+\)\.git/\1/' <<<$CONFLUENT_GIT_REPO)
    echo "${BUILD_DIR}/cp-${repo_short_name}-${confluent_git_refspec//\//-}"
}

function cleanup_confluent_build () {
    local confluent_git_refspec=${1:?"Missing Confluent Git refspec as first parameter!"}
    echo "Removing Confluent build dir for ${confluent_git_refspec}"
    if [ -d "$(resolve_build_dir ${confluent_git_refspec})" ]; then
        rm -rf "$(resolve_build_dir ${confluent_git_refspec})"
    fi
}

function clone_confluent () {  
    local confluent_git_refspec=${1:?"Missing Confluent Git refspec as first parameter!"}
    echo "Cloning Confluent ${confluent_git_refspec}"
    (
        mkdir -p "$(resolve_build_dir ${confluent_git_refspec})"
        cd "$(resolve_build_dir ${confluent_git_refspec})"
        git init
        git remote add origin ${CONFLUENT_GIT_REPO}
        git fetch --depth 1 origin ${confluent_git_refspec}
        git reset --hard FETCH_HEAD
    )
}

function build_confluent () {
    local confluent_git_refspec=${1:?"Missing Confluent Git refspec as first parameter!"}
    echo "Building Confluent ${confluent_git_refspec}"
    local version=$(resolve_confluent_version ${confluent_git_refspec})
    (
        cd "$(resolve_build_dir ${confluent_git_refspec})"
        # replace parent version
        sed -i "0,/<version>/{s/<version>[^<]*<\/version>/<version>${version}<\/version>/}" pom.xml
        # replace tool versions
        for pom in $(find . -name pom.xml); do
            replace_value_in_pom ${pom} io.confluent.rest-utils.version ${version}
            replace_value_in_pom ${pom} io.confluent.schema-registry.version ${version}
            replace_value_in_pom ${pom} io.confluent.kafka-rest.version ${version}
            replace_value_in_pom ${pom} io.confluent.ksql.version ${version}
        done
        # replace confluent repository
        sed -i "s/http:\/\/packages.confluent.io\/maven\//${MAVEN_URL//\//\\\/}/" pom.xml
        sed -i "s/https:\/\/packages.confluent.io\/maven\//${MAVEN_URL//\//\\\/}/" pom.xml
        sed -i "s/\${confluent.maven.repo}/${MAVEN_URL//\//\\\/}/" pom.xml
        # set project version
        mvn --batch-mode versions:set -DnewVersion=${version}
        mvn --batch-mode versions:update-child-modules
        # install
        mvn --batch-mode install --update-snapshots -DskipTests=true -Dspotbugs.skip=true -Dcheckstyle.skip=true \
            -DgitRepo=${CONFLUENT_GIT_REPO} -DgitRef=${confluent_git_refspec} -DbuildTimestamp=$(date -Iseconds --utc)
    )
}

function publish_confluent () {
    local confluent_git_refspec=${1:?"Missing Confluent Git refspec as first parameter!"}
    echo "Publishing Confluent ${confluent_git_refspec} to ${MAVEN_REPO_ID}"
    (
        cd "$(resolve_build_dir ${confluent_git_refspec})"
        mvn --batch-mode deploy -DaltDeploymentRepository=${MAVEN_REPO_ID} \
            -DskipTests=true -Dspotbugs.skip=true -Dcheckstyle.skip=true \
            -DgitRepo=${CONFLUENT_GIT_REPO} -DgitRef=${confluent_git_refspec} -DbuildTimestamp=$(date -Iseconds --utc)
    )
}

function build_and_publish () {
    for build in "${BUILDS[@]}"; do
        local confluent_git_refspec=$(git ls-remote ${CONFLUENT_GIT_REPO} --tags "**/v${build}-[0-9]*" | awk '{ print $2}' | sort -V | tail -n1)
        cleanup_confluent_build ${confluent_git_refspec}
        clone_confluent ${confluent_git_refspec}
        build_confluent ${confluent_git_refspec}
        if [ "${SHOULD_PUBLISH}" == "true" ]; then
            publish_confluent ${confluent_git_refspec}
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
    if [ -z "${CONFLUENT_GIT_REPO}" ]; then
        usage "Missing env var CONFLUENT_GIT_REPO: $1"
        return $?
    fi
    if [ -z "${BUILD}" ]; then
        usage "Missing env var BUILD: $1"
        return $?
    fi
    BUILDS=(${BUILD})
    if [ -z "${MAVEN_REPO_ID}" ] && [ "${SHOULD_PUBLISH}" == "true" ]; then
        usage "Missing env var MAVEN_REPO_ID: $1"
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