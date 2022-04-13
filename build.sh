#!/bin/bash

# Exit on command failure / unset variable
set -eu

function build_wal_g {
    local readonly no_cache_flag=${1}
	local readonly package_version=${2}
    local readonly package_is_latest=${3:-}

    # Initialise docker passwords
    use_docker

    local readonly build_container_image="registry.projectcatalysts.com/procat/docker/alpine-golang:latest"

    # Docker parameters: 
    # --attach  : Attach to STDIN, STDOUT or STDERR
    # --rm      : Automatically remove the container when it exits
    # --workdir : Specified working directory
    mkdir -p out
    local readonly container_option_array=(
        "-t"
        "--workdir /src"
        "-v ${PROCAT_BUILD_DOWNLOAD_PATH}:/downloads"
        "-v ${PROCAT_BUILD_SCRIPT_PATH}:/src/wal-g"
        "-e PROCAT_BUILD_DOWNLOAD_PATH=/downloads"
    )
    local readonly container_options="${container_option_array[*]}"

    # No longer required now that we are using a volume to pass the source to the container
    # (this is required in order to get the build artefacts)
    local readonly container_commands_array=(
        "cd /src"
        "echo Installing packages..."
		"apk update"
		"apk add make cmake lzo-dev libsodium"
        "echo Cloning modules..."
        "cd /src/wal-g"
        "git clone --depth 1 --recurse-submodules --branch v${package_version} https://github.com/wal-g/wal-g.git /src/v${package_version}"
        "echo Building wal-g... "
        "cd /src/v${package_version}"
		"GOBIN=/go/bin GOOS=linux GOARCH=amd64 CGO_ENABLED=1 USE_LIBSODIUM=1 USE_LZO=1 make install_and_build_pg"
		"mkdir -p /src/wal-g/bin"
		"cp main/pg/wal-g /src/wal-g/bin/wal-g"
    )
    container_commands=$( _TMP=$(IFS=$'\n' ; echo "${container_commands_array[*]}"); echo ${_TMP//$'\n'/' && '})

    log "Container Image   : ${build_container_image}"
    echo "--------------------"
    echo "Container Options :"
    echo "--------------------"
    echo "$(IFS=$'\n' ; echo "${container_option_array[*]}")"
    echo "--------------------"
    echo "Container Commands :"
    echo "--------------------"
    echo "$(IFS=$'\n' ; echo "${container_commands_array[*]}")"
    echo "--------------------"

    log "Executing docker run....."
    docker run ${container_options} ${build_container_image} /bin/bash -c "${container_commands}"
    local readonly docker_return_code=$?

    if [ ${docker_return_code} -eq 0 ]; then
        log "SUCCESS : Docker run completed successfully"
    else
        log "ERROR : Docker run returned an error: ${docker_return_code}"
        exit ${docker_return_code}
    fi
}

function build {

    # Check the pre-requisite environment variables have been set
    if [ -z ${PROCAT_BUILD_LIBRARY_PATH+x} ]; then
        echo "ERROR: PROCAT_BUILD_LIBRARY_PATH has not been set!"
        exit 1
    fi

    # Set the script name and path
    PROCAT_BUILD_SCRIPT_NAME="${BASH_SOURCE[0]##*/}"
    PROCAT_BUILD_SCRIPT_PATH="$(dirname "$(realpath "${PROCAT_BUILD_SCRIPT_NAME}")" )"

    # Configure the build environment if it hasn't been configured already
    source "${PROCAT_BUILD_LIBRARY_PATH}/set_build_env.sh"

    # For testing purposes, default the package version
	if [ -z "${1-}" ]; then
        local package_version=1.1
        log "package_version : Not specified, defaulting to $package_version"
	else
		local package_version=${1}
        log "package_version : $package_version"
    fi

	# Determine whether the --no-cache command line option has been specified.
	# If it has, attempts to download files from the internet are always made.
	if [ -z "${2-}" ]; then
		local no_cache_flag="false"
	else
		local no_cache_flag=$([ "$2" == "--no-cache" ] && echo "true" || echo "false")
	fi

	build_wal_g ${no_cache_flag} ${package_version} latest
}

# $1 : (Mandatory) Package Version (e.g. 1.1)
# $2 : (Optional) --no-cache
build ${1:-} ${2:-}
