# gl-peek

A small Bash script to have a quick look at your GitLab repositories. Inspired by [`git-peek`](https://github.com/Jarred-Sumner/git-peek), but for GitLab (cloud and self-hosted).

## Installation

Install it manually by pasting the content of the `src/gl-peek.sh` file in a file on your machine, adding it to your path and make it executable.

Example on macOS:

```sh
pbpaste > /usr/local/bin/gl-peek
chmod +x /usr/local/bin/gl-peek
```

You will need to have [`jq`](https://github.com/stedolan/jq) installed and available in your path as well.

## Usage

```sh
gl-peek <URL>

# Open the latest commit of the default branch
gl-peek https://gitlab.com/org/repo
gl-peek https://gitlab.mydomain.com/org/repo

# Open the latest commit of the given branch
gl-peek https://gitlab.com/org/repo/-/tree/<BRANCH>
gl-peek https://gitlab.mydomain.com/org/repo/-/tree/<BRANCH>

# Open the latest commit of the given merge request
gl-peek https://gitlab.com/org/repo/-/merge_requests/<ID>
gl-peek https://gitlab.mydomain.com/org/repo/-/merge_requests/<ID>

# Open the given commit
gl-peek https://gitlab.com/org/repo/-/commit/<SHA>
gl-peek https://gitlab.mydomain.com/org/repo/-/commit/<SHA>
```

## Configuration

In order for this script to work with private repositories, you will need to add a `.gl-peek` file in you `$HOME` with an access token from your GitLab instance (gitlab.com or self-hosted).

```sh
# For gitlab.com
GITLAB_TOKEN="..."

# For gitlab.fqdn.com
GITLAB_TOKEN_GITLAB_FQDN_COM="..."
```
