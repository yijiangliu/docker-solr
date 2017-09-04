#!/bin/bash
#
set -euo pipefail

TEST_DIR="$(dirname -- "${BASH_SOURCE-$0}")"

if (( $# == 0 )); then
  echo "Usage: $BASH_SOURCE tag"
  exit
fi

tag=$1

if [[ ! -z "${DEBUG:-}" ]]; then
  set -x
fi

source "$TEST_DIR/../shared.sh"

echo "Test $tag"
container_name='test_'$(echo "$tag" | tr ':/-' '_')
echo "Cleaning up left-over containers from previous runs"
container_cleanup "$container_name"
echo "Running $container_name"
docker run --name "$container_name" -d "$tag"
SLEEP_SECS=5
echo "Sleeping $SLEEP_SECS seconds..."
sleep $SLEEP_SECS
container_status=$(docker inspect --format='{{.State.Status}}' "$container_name")
echo "container $container_name status: $container_status"
if [[ $container_status == 'exited' ]]; then
  docker logs "$container_name"
  exit 1
fi
echo "Checking that the OS matches the tag '$tag'"
if echo "$tag" | grep -q -- -alpine; then
  alpine_version=$(docker exec --user=solr "$container_name" cat /etc/alpine-release || true)
  if [[ -z $alpine_version ]]; then
    echo "Could not get alpine version from container $container_name"
    container_cleanup "$container_name"
    exit 1
  fi
  echo "Alpine $alpine_version"
else
  debian_version=$(docker exec --user=solr "$container_name" cat /etc/debian_version || true)
  if [[ -z $debian_version ]]; then
    echo "Could not get debian version from container $container_name"
    container_cleanup "$container_name"
    exit 1
  fi
  echo "Debian $debian_version"
fi

# check that the version of Solr matches the tag
changelog_version=$(docker exec --user=solr "$container_name" bash -c "egrep '^==========* ' /opt/solr/CHANGES.txt | head -n 1 | tr -d '= '")
echo "Solr version $changelog_version"
if [[ $tag = "$TAG_LOCAL_BASE:latest" ]]; then
  solr_version_from_tag=$latest
else
  solr_version_from_tag=$(echo "$tag" | sed -e 's/^.*://' -e 's/-.*//')
fi
if [[ $changelog_version != $solr_version_from_tag ]]; then
  echo "Solr version mismatch"
  container_cleanup "$container_name"
  exit 1
fi

echo "Test $BASH_SOURCE $tag succeeded"
