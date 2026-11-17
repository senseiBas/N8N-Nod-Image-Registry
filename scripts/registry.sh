#!/usr/bin/env bash
set -euo pipefail
: "${UPSTREAM_SHA:?Missing upstream SHA}"
[[ "$UPSTREAM_SHA" =~ ^[0-9a-f]{40}$ ]]
registry=ghcr.io/senseibas
# Only an explicit missing manifest permits a build. Authentication/network failures fail closed.
exists() {
  local error
  error=$(mktemp)
  if docker buildx imagetools inspect "$1" > /dev/null 2>"$error"; then
    rm -f "$error"
    return 0
  fi
  if grep -Eqi 'manifest unknown|not found' "$error"; then
    rm -f "$error"
    return 1
  fi
  cat "$error" >&2
  rm -f "$error"
  exit 1
}
case "${1:-}" in
  build)
    case "${IMAGE:?}" in
      server) file=deployment/self-host/Dockerfile ;;
      browser) file=Dockerfile.browser ;;
      workspace) file=Dockerfile.workspace ;;
      *) exit 2 ;;
    esac
    [[ "${ARCH:?}" == amd64 || "$ARCH" == arm64 ]]
    tag="$registry/nod-$IMAGE:$UPSTREAM_SHA-$ARCH"
    if exists "$tag"; then
      echo "Already published: $tag"
      exit 0
    fi
    source_dir=$(mktemp -d)
    trap 'rm -rf "$source_dir"' EXIT
    git -C "$source_dir" init --quiet
    git -C "$source_dir" fetch --depth 1 https://github.com/n8n-io/nod.git "$UPSTREAM_SHA"
    git -C "$source_dir" checkout --detach FETCH_HEAD
    test "$(git -C "$source_dir" rev-parse HEAD)" = "$UPSTREAM_SHA"
    docker buildx build "$source_dir" --file "$source_dir/$file" \
      --platform "linux/$ARCH" --tag "$tag" --push \
      --label "org.opencontainers.image.source=https://github.com/senseiBas/N8N-Nod-Image-Registry" \
      --label "org.opencontainers.image.revision=$UPSTREAM_SHA" \
      --cache-from "type=registry,ref=$registry/nod-$IMAGE:buildcache-$ARCH" \
      --cache-to "type=registry,ref=$registry/nod-$IMAGE:buildcache-$ARCH,mode=max"
    ;;
  publish)
    for image in server browser workspace; do
      ref="$registry/nod-$image"
      if ! exists "$ref:$UPSTREAM_SHA"; then
        docker buildx imagetools create --tag "$ref:$UPSTREAM_SHA" \
          "$ref:$UPSTREAM_SHA-amd64" "$ref:$UPSTREAM_SHA-arm64"
      fi
      docker buildx imagetools inspect "$ref:$UPSTREAM_SHA" --raw | \
        jq -e '[.manifests[].platform | select(.os == "linux") | .architecture] | (index("amd64") != null) and (index("arm64") != null)'
    done
    # No latest tag is touched until every build and immutable manifest has succeeded.
    for image in server browser workspace; do
      ref="$registry/nod-$image"
      docker buildx imagetools create --tag "$ref:latest" "$ref:$UPSTREAM_SHA"
      expected=$(docker buildx imagetools inspect "$ref:$UPSTREAM_SHA" --format '{{.Manifest.Digest}}')
      actual=$(docker buildx imagetools inspect "$ref:latest" --format '{{.Manifest.Digest}}')
      test "$expected" = "$actual"
      echo "Published $ref:latest ($UPSTREAM_SHA, $actual)" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
    done
    ;;
  *) echo 'Usage: registry.sh build|publish' >&2; exit 2 ;;
esac
