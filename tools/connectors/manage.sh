#!/usr/bin/env bash

set -e

. tools/lib/lib.sh

_get_rule_base() {
  local rule; rule=$(echo "$1" | tr -s / :)
  echo ":$rule"
}

_check_tag_exists() {
  DOCKER_CLI_EXPERIMENTAL=enabled docker manifest inspect "$1" > /dev/null
}

cmd_test_scaffold() {
  rm -rf "airbyte-integrations/connectors/source-scaffold-source-python"
  cmd_scaffold "Python Source" scaffold-source-python
}

cmd_scaffold() {
  echo "Scaffolding connector"

  docker run --rm -it -v "$(pwd)":/airbyte -w /airbyte --entrypoint "/bin/sh" node:14.11.0-slim -c '
    cd airbyte-integrations/connector-templates/generator &&
    npm install &&
    npm run generate "$@"
  ' bash "$@"
}

cmd_build() {
  local path=$1; shift || error "Missing target (root path of integration) $USAGE"
  [ -d "$path" ] || error "Path must be the root path of the integration"

  echo "Building $path"
    ./gradlew "$(_get_rule_base "$path"):clean"
    ./gradlew "$(_get_rule_base "$path"):build"
    ./gradlew "$(_get_rule_base "$path"):integrationTest"
}

_execute_task_if_exists() {
  local path=$1
  local task=$2
  echo "checking if $task exists."
  if ./gradlew "$(_get_rule_base "$path"):tasks" --all | grep -qw "^$task"; then
    echo "found $task exists. executing."
    ./gradlew "$(_get_rule_base "$path"):$task"
  fi
}

cmd_publish() {
  local path=$1; shift || error "Missing target (root path of integration) $USAGE"
  [ -d "$path" ] || error "Path must be the root path of the integration"

  cmd_build "$path"

  local image_name; image_name=$(_get_docker_image_name "$path"/Dockerfile)
  local image_version; image_version=$(_get_docker_image_version "$path"/Dockerfile)
  local versioned_image=$image_name:$image_version
  local latest_image=$image_name:latest

  echo "image_name $image_name"
  echo "$versioned_image $versioned_image"
  echo "latest_image $latest_image"

  docker tag "$image_name:dev" "$versioned_image"
  docker tag "$image_name:dev" "$latest_image"

  if _check_tag_exists $versioned_image; then
    error "You're trying to push a version that was already released ($versioned_image). Make sure you bump it up."
  fi

  echo "Publishing new version ($versioned_image)"
  docker push $versioned_image
  docker push $latest_image
}

USAGE="

Usage: $(basename "$0") <cmd> <arguments>

Available commands:
  scaffold
  build  <integration_root_path>
  publish  <integration_root_path>
"

main() {
  assert_root

  local cmd=$1; shift || error "Missing cmd $USAGE"
  cmd_"$cmd" "$@"
}

main "$@"
