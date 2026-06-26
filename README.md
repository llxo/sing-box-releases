# sing-box releases

Private build recipes for reF1nd sing-box releases.

This repository does not vendor the upstream source tree. GitHub Actions clone
`reF1nd/sing-box`, check out the selected upstream release tag, apply the
provider patch, build a single Android arm64 `sing-box` binary, and publish it
to this repository's Releases.

Workflow:

- `auto-ref1nd.yml`: builds Android arm64 from reF1nd releases, selected by the
  `release_kind` input:
  - `stable`: latest non-prerelease reF1nd release.
  - `testing`: latest alpha/beta/rc reF1nd prerelease.

  Both kinds share a single `patches/provider.patch`, verified to apply cleanly
  to the `reF1nd-stable` and `reF1nd-testing` branches.

The workflow runs on a daily schedule and also supports manual dispatch with a
specific upstream release tag.

## Updating the patch

`patches/provider.patch` adds the "hide provider prefix when there is a single
provider" customization to `adapter/provider/adapter.go`. When upstream changes
break it, regenerate the patch from a reF1nd branch (do not hand-edit hunk
headers):

```sh
git clone https://github.com/reF1nd/sing-box.git
cd sing-box
git checkout reF1nd-stable          # representative of the stable line
git apply /abs/path/patches/provider.patch
git diff > /abs/path/patches/provider.patch
git checkout -- .
```

Verify it still applies to both branches before committing:

```sh
for b in reF1nd-stable reF1nd-testing; do
  git checkout -q "$b" && git checkout -- .
  git apply --check /abs/path/patches/provider.patch && echo "$b OK"
done
```
