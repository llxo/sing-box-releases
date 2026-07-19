#!/usr/bin/env bash
set -euo pipefail

# Build and publish the Android arm64 and Windows amd64 release assets.

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
upstream_stable_branch="${UPSTREAM_STABLE_BRANCH:-reF1nd-stable}"
upstream_testing_branch="${UPSTREAM_TESTING_BRANCH:-reF1nd-testing}"

case "${RELEASE_KIND}" in
  stable)
    prerelease_flag="false"
    release_title_suffix="stable"
    latest_tag_query='[.[] | select(.isPrerelease == false and (.tagName | startswith("v")))][0].tagName // ""'
    source_branch="${upstream_stable_branch}"
    ;;
  testing)
    prerelease_flag="true"
    release_title_suffix="testing"
    latest_tag_query='[.[] | select(.isPrerelease == true and (.tagName | test("-(alpha|beta|rc)[.-]")))][0].tagName // ""'
    source_branch="${upstream_testing_branch}"
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

if ! git ls-remote --exit-code --heads "https://github.com/${UPSTREAM_SOURCE_REPO}.git" "refs/heads/${source_branch}" >/dev/null; then
  echo "Source branch ${source_branch} not found in ${UPSTREAM_SOURCE_REPO}" >&2
  exit 1
fi

rm -rf "${source_dir}" "${dist_dir}"
git clone --depth 1 --branch "${source_branch}" --single-branch "https://github.com/${UPSTREAM_SOURCE_REPO}.git" "${source_dir}"

patch_path="${workspace}/${PATCH_FILE}"
if [[ ! -f "${patch_path}" ]]; then
  echo "Patch file not found: ${patch_path}" >&2
  exit 1
fi

pushd "${source_dir}" >/dev/null

# 核心流程：应用 provider 补丁（git apply 自带行号 offset 容忍）
bash "${workspace}/scripts/apply-patch.sh" "${patch_path}"

go test ./adapter/provider

version="${tag#v}"
android_build_tags="$(cat release/DEFAULT_BUILD_TAGS_OTHERS)"
windows_build_tags="$(cat release/DEFAULT_BUILD_TAGS_WINDOWS)"
ldflags_shared="$(cat release/LDFLAGS)"

go install -v ./cmd/internal/build

export CC="aarch64-linux-android23-clang"
export CXX="${CC}++"

mkdir -p "${dist_dir}"
CGO_ENABLED=1 GOOS=android GOARCH=arm64 build go build -v -trimpath -o "${dist_dir}/sing-box" -tags "${android_build_tags}" \
  -ldflags "-X 'github.com/sagernet/sing-box/constant.Version=${version}' ${ldflags_shared} -s -w -buildid=" \
  ./cmd/sing-box
chmod +x "${dist_dir}/sing-box"

# Windows amd64 按上游发布配置启用 purego/Naive，并与 libcronet.dll 一起打包。
windows_package_name="sing-box-${version}-windows-amd64"
windows_package_dir="${dist_dir}/${windows_package_name}"
windows_archive="${dist_dir}/${windows_package_name}.zip"
mkdir -p "${windows_package_dir}"

CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -v -trimpath -o "${windows_package_dir}/sing-box.exe" -tags "${windows_build_tags}" \
  -ldflags "-X 'github.com/sagernet/sing-box/constant.Version=${version}' ${ldflags_shared} -s -w -buildid=" \
  ./cmd/sing-box
cp LICENSE "${windows_package_dir}/LICENSE"

cronet_go_version="$(cat .github/CRONET_GO_VERSION)"
cronet_dir="$(mktemp -d)"
trap 'rm -rf "${cronet_dir}"' EXIT
git init "${cronet_dir}"
git -C "${cronet_dir}" remote add origin https://github.com/sagernet/cronet-go.git
git -C "${cronet_dir}" fetch --depth=1 origin "${cronet_go_version}"
git -C "${cronet_dir}" checkout FETCH_HEAD
CGO_ENABLED=0 go -C "${cronet_dir}" build -v -o "${cronet_dir}/build-naive" ./cmd/build-naive
GOPROXY=direct GOSUMDB=off "${cronet_dir}/build-naive" extract-lib --target windows/amd64 -o "${windows_package_dir}"

if [[ ! -f "${windows_package_dir}/libcronet.dll" ]]; then
  echo "libcronet.dll was not extracted" >&2
  exit 1
fi

(
  cd "${dist_dir}"
  zip -q -r "${windows_archive}" "${windows_package_name}"
)
rm -rf "${windows_package_dir}"

source_sha="$(git rev-parse HEAD)"
popd >/dev/null

release_page_url="https://github.com/${GITHUB_REPOSITORY}/releases/tag/${tag}"
download_base_url="https://github.com/${GITHUB_REPOSITORY}/releases/download/${tag}"
notes="$(cat <<EOF
Automated reF1nd ${release_title_suffix} builds for Android arm64 and Windows amd64.

| 项目 | 信息 |
| --- | --- |
| Release | [${tag}](${release_page_url}) |
| 源码 | [${UPSTREAM_SOURCE_REPO}@${source_branch}](https://github.com/${UPSTREAM_SOURCE_REPO}/tree/${source_branch}) |
| 源码提交 | [${source_sha}](https://github.com/${UPSTREAM_SOURCE_REPO}/commit/${source_sha}) |
| 补丁 | [${PATCH_FILE}](https://github.com/${GITHUB_REPOSITORY}/blob/${tag}/${PATCH_FILE}) |

| 平台 | 架构 | 下载 |
| --- | --- | --- |
| Android | arm64 | [sing-box](${download_base_url}/sing-box) |
| Windows | amd64 | [${windows_package_name}.zip](${download_base_url}/${windows_package_name}.zip) |
EOF
)"

# 核心流程：同名 Release 存在时只替换资产，避免重复创建 tag 或 release。
release_assets=("${dist_dir}/sing-box" "${windows_archive}")
if gh release view "${tag}" --repo "${GITHUB_REPOSITORY}" >/dev/null 2>&1; then
  gh release upload "${tag}" --repo "${GITHUB_REPOSITORY}" "${release_assets[@]}" --clobber
  gh release edit "${tag}" --repo "${GITHUB_REPOSITORY}" --draft=false --prerelease="${prerelease_flag}" --notes "${notes}"
else
  release_args=(release create "${tag}" --repo "${GITHUB_REPOSITORY}" --title "${tag}" --notes "${notes}")
  if [[ "${prerelease_flag}" == "true" ]]; then
    release_args+=(--prerelease)
  fi
  gh "${release_args[@]}" "${release_assets[@]}"
fi
