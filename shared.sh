#!/bin/bash
# shellcheck disable=SC2034
set -euo pipefail

# Force UTF-8 for all commands, for Git-Bash on Windows compatibility
export LC_ALL=C.UTF-8

##==----------------------------------------------------------------------------
##  SemVer regexes
##  see: https://semver.org/spec/v2.0.0.html#is-there-a-suggested-regular-expression-regex-to-check-a-semver-string

pcre_semver='^(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)(?:-(?P<prerelease>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+(?P<buildmetadata>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$'
pcre_master_ver='^(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)$'
pcre_allow_vprefix="^v{0,1}${pcre_master_ver:1}"
pcre_zero_padded_calver='^(?P<major>\d{4})\.(?P<minor>\d{2})\.(?P<patch>\d{2,})$'
pcre_zero_padded_calver_version='^(?P<major>\d{4})\.(?P<minor>\d{2})\.(?P<patch>\d{2,})(?:[-+][0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*)?$'
pcre_allow_vprefix_zero_padded_calver="^v{0,1}${pcre_zero_padded_calver:1}"
pcre_old_calver='^(?P<major>0|[1-9]\d*)-0{0,1}(?P<minor>0|[0-9]\d*)-R(?P<patch>0|[1-9]\d*)$'

##==----------------------------------------------------------------------------
##  Utility function for removing tag_prefix if present

remove_prefix() {
    local tag="$1"
    if [[ -n "${tag_prefix:-}" ]]; then
        if [[ "${tag}" == "${tag_prefix}"* ]]; then
            printf '%s\n' "${tag:${#tag_prefix}}"
        else
            printf '\n'
        fi
    else
        printf '%s\n' "${tag}"
    fi
}

##==----------------------------------------------------------------------------
## Conventional commit regexes
## see: https://www.conventionalcommits.org/en/v1.0.0/

pcre_conventional_commit_patch='^(build|chore|ci|docs|fix|perf|refactor|revert|style|test)(\([a-zA-Z0-9-]+\))?:\s.*'
pcre_conventional_commit_minor='^(feat)(\([a-zA-Z0-9-]+\))?:\s.*'
pcre_conventional_commit_breaking='^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([a-zA-Z0-9-]+\))?!:.*|BREAKING CHANGE:'

##==----------------------------------------------------------------------------
##  Input validation

input_errors='false'
scheme="${scheme:-semver}"
if [[ "${scheme}" != 'semver' && "${scheme}" != 'calver' && "${scheme}" != 'conventional_commits' ]] ; then
    echo "🛑 Value of 'scheme' is not valid, choose from 'semver', 'calver' or 'conventional_commits" 1>&2
    input_errors='true'
fi

pep440="${pep440:-false}"
if [[ "${pep440}" != 'false' && "${pep440}" != 'true' ]] ; then
    echo "🛑 Value of 'pep440' is not valid, choose from 'false' or 'true'" 1>&2
    input_errors='true'
fi

zero_pad="${zero_pad:-false}"
if [[ "${zero_pad}" != 'false' && "${zero_pad}" != 'true' ]] ; then
    echo "🛑 Value of 'zero_pad' is not valid, choose from 'false' or 'true'" 1>&2
    input_errors='true'
elif [[ "${zero_pad}" == 'true' && "${scheme}" != 'calver' ]] ; then
    echo "🛑 Value of 'zero_pad' is only supported when 'scheme' is 'calver'" 1>&2
    input_errors='true'
fi

use_api="${use_api:-false}"
if [[ "${use_api}" != 'false' && "${use_api}" != 'true' ]] ; then
    echo "🛑 Value of 'use_api' is not valid, choose from 'false' or 'true'" 1>&2
    input_errors='true'
fi

if [[ "${use_api}" == 'true' ]] ; then
    if [[ -z "${github_token:-}" ]] ; then
        echo "🛑 'use_api' is true, but environment variable 'github_token' is not set" 1>&2
        input_errors='true'
    fi
fi

# Check if the tag_prefix is set, and if not, set it to an empty string
tag_prefix="${tag_prefix:-}"

##==----------------------------------------------------------------------------
##  MacOS compatibility

export use_perl="false"
export use_gnugrep="false"
if [[ "${GITHUB_ACTIONS:-}" == 'true' && "$(uname)" == 'Darwin' ]] ; then
    export use_perl="true"
elif [[ "$(uname)" == 'Darwin' ]] ; then
    if perl --version 1>/dev/null ; then
        export use_perl="true"
    elif ! ggrep --version 1>/dev/null ; then
        echo "🛑 GNU grep not installed, try brew install coreutils" 1>&2
        exit 9
    else
        export use_gnugrep="true"
    fi
fi

function grep_p() {
    if [[ "${use_perl}" == 'true' ]] ; then
        perl -ne "print if /${1}/"
    elif [[ "${use_gnugrep}" == 'true' ]] ; then
        # shellcheck disable=SC2086
        ggrep -P "${1}"
    else
        # shellcheck disable=SC2086
        command grep -P "${1}"
    fi
}

##==----------------------------------------------------------------------------
##  Non GitHub compatibility - for testing both locally and in BATS

if [[ -z "${GITHUB_OUTPUT:-}" || -n "${BATS_VERSION:-}" ]] ; then
    export GITHUB_OUTPUT="/dev/stdout"
fi
