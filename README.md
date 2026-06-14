# sing-box releases

Private build recipes for reF1nd sing-box releases.

This repository does not vendor the upstream source tree. GitHub Actions clone
`reF1nd/sing-box`, check out the selected upstream release tag, apply the
workflow-specific provider patch, build a single Android arm64 `sing-box`
binary, and publish it to this repository's Releases.

Workflows:

- `auto-ref1nd-stable.yml`: latest non-prerelease reF1nd release,
  using `patches/provider.patch`.
- `auto-ref1nd-testing.yml`: latest alpha/beta/rc reF1nd prerelease,
  using `patches/provider-testing.patch`.

Both workflows also support manual dispatch with a specific upstream release
tag.
