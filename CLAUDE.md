# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is a **build-recipe** repository, not a source tree. It does **not** vendor any Go
code. GitHub Actions clone `reF1nd/sing-box`, check out the selected source branch,
apply `patches/provider.patch`, build a single **Android arm64** `sing-box` binary, and
publish it to this repository's GitHub Releases using the selected upstream release tag.

The entire tracked surface is: one workflow, two shell scripts, one patch, and the README.
`source/`, `dist/`, and `tmp/` are gitignored — they are CI clone targets and local scratch,
never committed. `tmp/sing-box/` (if present) is a local clone of upstream used only to
develop/verify the patch.

## Architecture / control flow

The build is driven entirely from CI; there is no local application to run.

1. `.github/workflows/auto-ref1nd.yml` — entry point. Two jobs:
   - `determine-matrix`: decides which `release_kind`(s) to build. On `workflow_dispatch`
     it uses the user's `release_kind` input; on `schedule` it re-derives the kind from the
     current UTC time (20:17 → `stable`, 20:37 → `testing`, any other time → both).
   - `build`: matrix over `release_kind`. Sets up Go, Android NDK, the build cache, then
     runs `scripts/build-android-arm64.sh` with all inputs passed as env vars.
2. `scripts/build-android-arm64.sh` — the core orchestration (see below).
3. `scripts/apply-patch.sh` — applies a patch with **plain `git apply` only** (no `--3way`).

### `build-android-arm64.sh` step order

- Resolve the target `tag`: use `INPUT_TAG` if given, else query the **release repo**
  (`UPSTREAM_RELEASE_REPO`, default `reF1nd/sing-box-releases`) for the latest tag matching
  the kind. Note the asymmetry: tags are *listed* from the release repo, but source is
  *cloned* from `UPSTREAM_SOURCE_REPO` (`reF1nd/sing-box`) by branch.
- Resolve the source branch: `stable` uses `UPSTREAM_STABLE_BRANCH` (default
  `reF1nd-stable`); `testing` uses `UPSTREAM_TESTING_BRANCH` (currently defaulted by the
  workflow to `reF1nd-testing-next`, and manually overrideable via `testing_source_branch`).
- Validate: the tag's `isPrerelease` must match the kind (`stable`→false, `testing`→true),
  and `testing` tags must contain `-(alpha|beta|rc)[.-]`.
- Skip if a same-tag release already exists in this repo, unless `FORCE_BUILD=true`.
- Shallow-clone (`--depth 1 --branch <source_branch> --single-branch`) the source, apply the patch, then run
  `go test ./adapter/provider` as a gate (the patch lives in that package).
- Build: install the `cmd/internal/build` wrapper, then `build go build ...`. The wrapper
  (`go install ./cmd/internal/build`) injects Android NDK SDK paths via `build_shared.FindSDK()`
  before exec'ing the wrapped command — that is why the build invokes `build go build`, not
  bare `go build`. Build tags come from `release/DEFAULT_BUILD_TAGS_OTHERS`, shared ldflags
  from `release/LDFLAGS`; version is `${tag#v}` injected into `constant.Version`.
- Publish via `gh`: if the release exists, `upload --clobber` the asset and `edit`; else
  `release create`. `--prerelease` is set for the `testing` kind.

### stable vs testing

A single `patches/provider.patch` serves both. The distinction is purely in tag selection:
`stable` = newest non-prerelease `v*` tag; `testing` = newest prerelease tag matching
`-(alpha|beta|rc)[.-]`. The shared patch is verified to apply to both the `reF1nd-stable`
and current testing upstream branches. As of 2026-07-14 the workflow default is
`reF1nd-testing-next`; if upstream moves testing back, change the workflow default back to
`reF1nd-testing`.

## The patch

`patches/provider.patch` adds one customization to `adapter/provider/adapter.go`: hide the
provider-name prefix on exported outbound/endpoint tags when only a single provider is
configured (`shouldHideProvider()` → `len(providers) <= 1`).

**Critical constraint:** because the source is a `--depth 1` shallow clone, the base blobs
needed for `git apply --3way` are absent, so 3-way fallback is impossible. The patch must
apply with plain `git apply` (line-offset tolerance only). When upstream context changes
enough to break it, **regenerate** the patch — never hand-edit hunk headers.

### Regenerate and verify the patch

```sh
git clone https://github.com/reF1nd/sing-box.git && cd sing-box
git checkout reF1nd-stable
git apply /abs/path/patches/provider.patch
git diff > /abs/path/patches/provider.patch
git checkout -- .

# verify it still applies to both lines before committing
for b in reF1nd-stable reF1nd-testing-next; do
  git checkout -q "$b" && git checkout -- .
  git apply --check /abs/path/patches/provider.patch && echo "$b OK"
done
```

## Conventions

- `.patch`, `.sh`, and `.yml` files are forced to **LF** line endings via `.gitattributes` —
  preserve this when editing on Windows.
- Shell scripts use `set -euo pipefail` and assert required env vars with `: "${VAR:?...}"`.
  In-code comments are written in Chinese; keep that style when adding to existing scripts.
