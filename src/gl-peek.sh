#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [[ "${TRACE-0}" == "1" ]]; then
	set -o xtrace
fi

if [[ "${1-}" =~ ^-*h(elp)?$ || $# == 0 ]]; then
	echo '
gl-peek@0.0.0

Take a quick look at a repository from GitLab.

Usage:

    gl-peek <URL>

Example:

    gl-peek https://gitlab.com/org/repo
    gl-peek https://gitlab.com/org/repo/-/tree/<branch>
    gl-peek https://gitlab.com/org/repo/-/merge_requests/<id>
    gl-peek https://gitlab.com/org/repo/-/commit/<sha>

    gl-peek https://gitlab.mydomain.com/org/repo
    gl-peek https://gitlab.mydomain.com/org/repo/-/tree/<branch>
    gl-peek https://gitlab.mydomain.com/org/repo/-/merge_requests/<id>
    gl-peek https://gitlab.mydomain.com/org/repo/-/commit/<sha>

Configuration:

    Add a `~/.gl-peek` file with your GitLab tokens to access private repositories:

    ```
    # For gitlab.com
    GITLAB_TOKEN="..."

    # For gitlab.fqdn.com
    GITLAB_TOKEN_GITLAB_FQDN_COM="..."

    # Define your editor of choice
    EDITOR="subl"
    ```
'
	exit
fi

cd "$(dirname "$0")"

GITLAB_DOMAIN="gitlab.com"
GITLAB_TOKEN=""

# @see https://stackoverflow.com/a/45977232/14997312
# Following regex is based on https://www.rfc-editor.org/rfc/rfc3986#appendix-B with
# additional sub-expressions to split authority into userinfo, host and port
#
readonly URI_REGEX='^(([^:/?#]+):)?(//((([^:/?#]+)@)?([^:/?#]+)(:([0-9]+))?))?(/([^?#]*))(\?([^#]*))?(#(.*))?'
#                    ↑↑            ↑  ↑↑↑            ↑         ↑ ↑            ↑ ↑        ↑  ↑        ↑ ↑
#                    |2 scheme     |  ||6 userinfo   7 host    | 9 port       | 11 rpath |  13 query | 15 fragment
#                    1 scheme:     |  |5 userinfo@             8 :…           10 path    12 ?…       14 #…
#                                  |  4 authority
#                                  3 //…

parse_host () {
	[[ "$@" =~ $URI_REGEX ]] && echo "${BASH_REMATCH[7]}"
}

background_task() {
	eval "$@" &>/dev/null & disown;
}

load_token() {
	if [[ -f "$HOME/.gl-keep" ]]; then
		source "$HOME/.gl-keep"
	fi
}

fetch() {
	local org="$1"
	local repository="$2"
	local path="${3:-""}"

	echo "$(curl -s "https://$GITLAB_DOMAIN/api/v4/projects/$org%2F$repository/$path" -H "Authorization: Bearer $GITLAB_TOKEN")"
}

fetch_default_branch() {
	local org="$1"
	local repository="$2"

	echo "$(fetch "$org" "$repository" | jq -r '.default_branch')"
}

fetch_last_commit() {
	local org="$1"
	local repository="$2"
	local branch="$3"

	echo "$(fetch "$org" "$repository" "repository/commits?per_page=1&page=1&ref_name=$branch" | jq -r '.[0].id')"
}

fetch_merge_request_branch() {
	local org="$1"
	local repository="$2"
	local merge_request_id="$3"

	echo "$(fetch "$org" "$repository" "merge_requests/$merge_request_id" | jq -r .source_branch)"
}

fetch_archive() {
	local org="$1"
	local repository="$2"
	local branch_or_commit="$3"
	local commit="$4"

	local slugified_branch_or_commit=$(echo "$branch_or_commit" | sed 's/\//-/g')
	local folder_name="$repository-$slugified_branch_or_commit-$commit"
	local folder="/tmp/$folder_name"

	mkdir -p $folder
	cd $(dirname $folder)
	background_task "curl -s 'https://$GITLAB_DOMAIN/api/v4/projects/$org%2F$repository/repository/archive.tar.gz?sha=$branch_or_commit' -H 'Authorization: Bearer $GITLAB_TOKEN' | tar -zx" &
	$EDITOR "$folder"
}

peek_default() {
	local org="$1"
	local repository="$2"

	local default_branch="$(fetch_default_branch "$org" "$repository")"
	local last_commit=$(fetch_last_commit "$org" "$repository" "$default_branch")

	fetch_archive "$org" "$repository" "$default_branch" "$last_commit"
}

peek_branch() {
	local org="$1"
	local repository="$2"
	local branch="$3"

	local last_commit=$(fetch_last_commit "$org" "$repository" "$branch")

	fetch_archive "$org" "$repository" "$branch" "$last_commit"
}

peek_commit() {
	local org="$1"
	local repository="$2"
	local commit="$3"

	fetch_archive "$org" "$repository" "$commit" "$commit"
}

peek_merge_requests() {
	local org="$1"
	local repository="$2"
	local merge_request_id="$3"

	local branch=$(fetch_merge_request_branch "$org" "$repository" "$merge_request_id")
	local last_commit=$(fetch_last_commit "$org" "$repository" "$branch")

	fetch_archive "$org" "$repository" "$branch" "$last_commit"
}

main() {
	# Test jq dependency
	if ! [[ -x "$(which jq)" ]]; then
		echo "Missing `jq` dependency. Install it with `brew install jq`."
		exit
	fi

	# Parse host
	local host=$(parse_host $1 || echo "__ERROR__")

	if [[ $host == "__ERROR__" ]]; then
		echo "Could not parse $1, is it a valid URL?"
		exit
	fi

	GITLAB_DOMAIN="$host"

	# Load token from config and set local $GITLAB_TOKEN
	load_token
	if [[ $host != "gitlab.com" ]]; then
		token_name=$(echo $host | sed "s/\./_/g" | tr '[:lower:]' '[:upper:]')
		token_name="GITLAB_TOKEN_$token_name"
		GITLAB_TOKEN=$(echo "${!token_name}")
	fi

	# Parse path and extract org, repository, category and ID.
	# These will be used to trigger the correct fetching function.
	local path=$(parse_path $1)
	path=${path/\//}

	# echo $path
	org=$(echo "$path" | awk -F"/" '{print $1}')
	repository=$(echo "$path" | awk -F"/" '{print $2}')
	category=$(echo "$path" | awk -F"/" '{print $4}') # MR, commit
	id=$(echo "$path" | awk -F"/" '{print $5}') # commit hash, MR ID

	# Throw if category is not supported.
	if [[ -n $category && $category != "merge_requests" && $category != "commit" && $category != "tree" ]]; then
		echo "Category '$category' not supported.";
		exit;
	fi

	# Dispatch actions
	if [[ $category == "merge_requests" ]]; then
		peek_merge_requests $org $repository $id
	elif [[ $category == "commit" ]]; then
		peek_commit $org $repository $id
	elif [[ $category == "tree" ]]; then
		# Branch names can have "/" in them, so we need to extract everything after /tree
		# This will not work with URL including a path to specific folder which follows the same pattern.
		id=$(echo $path | grep --only-matching -E 'tree/(.*)$')
		id=${id/tree\//}
		peek_branch $org $repository $id
	else
		peek_default $org $repository
	fi
}

main "$@"

