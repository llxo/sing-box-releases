#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${UPSTREAM_SOURCE_REPO:?UPSTREAM_SOURCE_REPO is required}"
: "${UPSTREAM_RELEASE_REPO:?UPSTREAM_RELEASE_REPO is required}"
: "${RELEASE_KIND:?RELEASE_KIND is required}"
: "${PATCH_FILE:?PATCH_FILE is required}"

workspace="${GITHUB_WORKSPACE:-$(pwd)}"
source_dir="${workspace}/source"
dist_dir="${workspace}/dist"
input_tag="${INPUT_TAG:-}"
force_build="${FORCE_BUILD:-false}"

case "${RELEASE_KIND}" in
  stable)
    prerelease_flag="false"
    release_title_suffix="stable"
    latest_tag_query='[.[] | select(.isPrerelease == false and (.tagName | startswith("v")))][0].tagName // ""'
    ;;
  testing)
    prerelease_flag="true"
    release_title_suffix="testing"
    latest_tag_query='[.[] | select(.isPrerelease == true and (.tagName | test("-(alpha|beta|rc)[.-]")))][0].tagName // ""'
    ;;
  *)
    echo "Unsupported RELEASE_KIND: ${RELEASE_KIND}" >&2
    exit 1
    ;;
esac

if [[ -n "${input_tag}" ]]; then
  tag="${input_tag}"
else
  tag="$(gh release list --repo "${UPSTREAM_RELEASE_REPO}" --limit 100 --json tagName,isPrerelease --jq "${latest_tag_query}")"
fi

if [[ -z "${tag}" || "${tag}" != v* ]]; then
  echo "Invalid upstream release tag: ${tag}" >&2
  exit 1
fi

actual_prerelease="$(gh release view "${tag}" --repo "${UPSTREAM_RELEASE_REPO}" --json isPrerelease --jq .isPrerelease)"
if [[ "${actual_prerelease}" != "${prerelease_flag}" ]]; then
  echo "Tag ${tag} prerelease=${actual_prerelease}, expected ${prerelease_flag} for ${RELEASE_KIND}" >&2
  exit 1
fi

if [[ "${RELEASE_KIND}" == "testing" && ! "${tag}" =~ -(alpha|beta|rc)[.-] ]]; then
  echo "Testing tag must contain alpha, beta, or rc: ${tag}" >&2
  exit 1
fi

if gh release view "${tag}" --repo "${GITHUB_REPOSITORY}" >/dev/null 2>&1 && [[ "${force_build}" != "true" ]]; then
  echo "Release ${tag} already exists in ${GITHUB_REPOSITORY}; set force_build=true to rebuild."
  exit 0
fi

if ! git ls-remote --exit-code --tags "https://github.com/${UPSTREAM_SOURCE_REPO}.git" "refs/tags/${tag}" >/dev/null; then
  echo "Source tag ${tag} not found in ${UPSTREAM_SOURCE_REPO}" >&2
  exit 1
fi

rm -rf "${source_dir}" "${dist_dir}"
git clone --depth 1 --branch "${tag}" "https://github.com/${UPSTREAM_SOURCE_REPO}.git" "${source_dir}"

patch_path="${workspace}/${PATCH_FILE}"
if [[ ! -f "${patch_path}" ]]; then
  echo "Patch file not found: ${patch_path}" >&2
  exit 1
fi

pushd "${source_dir}" >/dev/null

# 核心流程：灵活应用补丁，支持行号偏移和 3-way merge
bash "${workspace}/scripts/apply-patch-flexible.sh" "${patch_path}"

go test ./adapter/provider

version="${tag#v}"
build_tags="$(cat release/DEFAULT_BUILD_TAGS_OTHERS)"
ldflags_shared="$(cat release/LDFLAGS)"

go install -v ./cmd/internal/build

export CC="aarch64-linux-android23-clang"
export CXX="${CC}++"

mkdir -p "${dist_dir}"
CGO_ENABLED=1 GOOS=android GOARCH=arm64 build go build -v -trimpath -o "${dist_dir}/sing-box" -tags "${build_tags}" \
  -ldflags "-X 'github.com/sagernet/sing-box/constant.Version=${version}' ${ldflags_shared} -s -w -buildid=" \
  ./cmd/sing-box
chmod +x "${dist_dir}/sing-box"

source_sha="$(git rev-parse HEAD)"
popd >/dev/null

notes="$(cat <<EOF
Automated reF1nd ${release_title_suffix} Android arm64 build.

Source: ${UPSTREAM_SOURCE_REPO}@${tag}
Source commit: ${source_sha}
Patch: ${PATCH_FILE}
EOF
)"

# 核心流程：同名 Release 存在时只替换资产，避免重复创建 tag 或 release。
if gh release view "${tag}" --repo "${GITHUB_REPOSITORY}" >/dev/null 2>&1; then
  gh release upload "${tag}" --repo "${GITHUB_REPOSITORY}" "${dist_dir}/sing-box" --clobber
  gh release edit "${tag}" --repo "${GITHUB_REPOSITORY}" --draft=false --prerelease="${prerelease_flag}" --notes "${notes}"
else
  release_args=(release create "${tag}" --repo "${GITHUB_REPOSITORY}" --title "${tag}" --notes "${notes}")
  if [[ "${prerelease_flag}" == "true" ]]; then
    release_args+=(--prerelease)
  fi
  gh "${release_args[@]}" "${dist_dir}/sing-box"
fi

