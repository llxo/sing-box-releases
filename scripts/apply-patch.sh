#!/usr/bin/env bash
set -euo pipefail

# 应用 provider 补丁。
#
# 注意：构建脚本以 --depth 1 浅克隆上游源码，git apply --3way 所需的 base blob
# 不在浅克隆对象中，3-way 回退必然失败，因此这里只用 git apply。
# git apply 本身已容忍行号 offset；当上下文发生实质变化导致失配时直接报错，
# 由维护者依据上游变更用 `git diff` 重新生成补丁（参见 README）。
#
# 参数：$1 = 补丁文件路径

patch_file="${1:?Patch file required}"

if [[ ! -f "${patch_file}" ]]; then
  echo "Patch file not found: ${patch_file}" >&2
  exit 1
fi

echo "Applying patch: ${patch_file}"

if git apply --check "${patch_file}" 2>/dev/null; then
  git apply "${patch_file}"
  echo "✓ Patch applied cleanly"
else
  echo "✗ Patch does not apply. Details:" >&2
  git apply --check -v "${patch_file}" >&2 || true
  exit 1
fi
