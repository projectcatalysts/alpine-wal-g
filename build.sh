#!/bin/bash -eu

function build_wal_g {
    local readonly no_cache_flag=${1}
	local readonly package_version=${2}
    local readonly package_is_latest=${3:-}

    # Initialise docker passwords
    procat_ci_docker_init

    local readonly build_container_image="${PROCAT_CI_REGISTRY_SERVER}/procat/docker/alpine-golang:latest"

    # Docker parameters: 
    # --attach  : Attach to STDIN, STDOUT or STDERR
    # --rm      : Automatically remove the container when it exits
    # --workdir : Specified working directory
    mkdir -p out
    local readonly container_option_array=(
        "-t"
        "--workdir /src"
        "-v ${PROCAT_CI_DOWNLOAD_PATH}:/downloads"
        "-v ${EXEC_CI_SCRIPT_PATH}:/src/wal-g"
        "-e PROCAT_CI_DOWNLOAD_PATH=/downloads"
    )
    local readonly container_options="${container_option_array[*]}"

    # No longer required now that we are using a volume to pass the source to the container
    # (this is required in order to get the build artefacts)
    local readonly container_commands_array=(
        "cd /src"
        "echo Installing packages..."
		"apk update"
		"apk add alpine-sdk make cmake lzo-dev libsodium"
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

    pc_log "Container Image   : ${build_container_image}"
    echo "--------------------"
    echo "Container Options :"
    echo "--------------------"
    echo "$(IFS=$'\n' ; echo "${container_option_array[*]}")"
    echo "--------------------"
    echo "Container Commands :"
    echo "--------------------"
    echo "$(IFS=$'\n' ; echo "${container_commands_array[*]}")"
    echo "--------------------"

    pc_log "Executing docker run....."
    docker run ${container_options} ${build_container_image} /bin/bash -c "${container_commands}"
    local readonly docker_return_code=$?

    if [ ${docker_return_code} -eq 0 ]; then
        pc_log "SUCCESS : Docker run completed successfully"
    else
        pc_log "ERROR : Docker run returned an error: ${docker_return_code}"
        exit ${docker_return_code}
    fi
}

# configure_ci_environment is used to configure the CI environment variables
function configure_ci_environment {
    #
    # Check the pre-requisite environment variables have been set
    # PROCAT_CI_SCRIPTS_PATH would typically be set in .bashrc or .profile
    # 
    if [ -z ${PROCAT_CI_SCRIPTS_PATH+x} ]; then
        echo "ERROR: A required CI environment variable has not been set : PROCAT_CI_SCRIPTS_PATH"
        echo "       Has '~/.procat_ci_env.sh' been sourced into ~/.bashrc or ~/.profile?"
        env | grep "PROCAT_CI"
        return 1
    fi

    # Configure the build environment if it hasn't been configured already
    source "${PROCAT_CI_SCRIPTS_PATH}/set_ci_env.sh"
}

function build {
    #
    # configure_ci_environment is used to configure the CI environment variables
    # and load the CI common functions
    #
    configure_ci_environment || return $?

    # For testing purposes, default the package name
	if [ -z "${1-}" ]; then
        local package_name=${PROCAT_CI_REGISTRY_SERVER}/procat/docker/wal-g
        pc_log "package_name (default)           : $package_name"
	else
		local package_name=${1}
        pc_log "package_name                     : $package_name"
    fi

    # For testing purposes, default the package version
	if [ -z "${2-}" ]; then
        local package_version="2.0.1"
        pc_log "package_version (default)        : $package_version"
	else
		local package_version=${2}
        pc_log "package_version                  : $package_version"
    fi
    pc_log ""

	# Determine whether the --no-cache command line option has been specified.
	# If it has, attempts to download files from the internet are always made.
	if [ -z "${2-}" ]; then
		local no_cache_flag="false"
	else
		local no_cache_flag=$([ "$2" == "--no-cache" ] && echo "true" || echo "false")
	fi

	build_wal_g ${no_cache_flag} ${package_version} latest
}

# $1 : (Mandatory) Package Name (registry.projectcatalysts.com/procat/wal-g)
# $2 : (Mandatory) Package Version (e.g. 1.1)
# $3 : (Optional) --no-cache
build ${1:-} ${2:-} ${3:-}
