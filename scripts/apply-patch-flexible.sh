#!/usr/bin/env bash
set -euo pipefail

# 灵活应用补丁：优先直接 apply，失败时尝试 3-way merge
# 参数：$1 = 补丁文件路径

patch_file="${1:?Patch file required}"

if [[ ! -f "${patch_file}" ]]; then
  echo "Patch file not found: ${patch_file}" >&2
  exit 1
fi

echo "Attempting to apply patch: ${patch_file}"

# 尝试 1: 直接 apply
if git apply --check "${patch_file}" 2>/dev/null; then
  echo "✓ Patch applies cleanly"
  git apply "${patch_file}"
  exit 0
fi

echo "⚠ Direct apply failed, trying 3-way merge..."

# 尝试 2: 3-way merge（允许行号偏移和上下文差异）
if git apply --3way "${patch_file}" 2>/dev/null; then
  echo "✓ Patch applied via 3-way merge"

  # 检查是否有冲突
  if git diff --check 2>/dev/null; then
    exit 0
  else
    echo "⚠ Merge conflicts detected, attempting auto-resolution..." >&2
    # 3-way merge 成功但有冲突标记时，检查是否能自动解决
    if git diff --name-only --diff-filter=U | grep -q .; then
      echo "✗ Unresolved conflicts remain" >&2
      git status --short
      exit 1
    fi
  fi
  exit 0
fi

echo "✗ All patch strategies failed" >&2
exit 1
