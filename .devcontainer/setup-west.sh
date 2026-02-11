#!/usr/bin/env bash
set -euo pipefail

# ルートと _west の絶対パス
ROOT_DIR="/workspaces/zmk-config"
WEST_WS="${ROOT_DIR}/_west"
ORIG_MANIFEST_DIR="${ROOT_DIR}/config"
ORIG_MANIFEST_FILE="${ORIG_MANIFEST_DIR}/west.yml"

# ルート側に誤作成された .west をクリーン
if [ -d "${ROOT_DIR}/.west" ]; then
  rm -rf "${ROOT_DIR}/.west"
fi

# _west/config に west.yml のシンボリックリンクを張る（オリジナル変更を自動反映）
mkdir -p "${WEST_WS}/config"
[ -e "${WEST_WS}/config/west.yml" ] && rm -f "${WEST_WS}/config/west.yml"
ln -s ../../config/west.yml "${WEST_WS}/config/west.yml"

# _west をワークスペースとして初期化（manifest はリンクで参照）
cd "${WEST_WS}"
if [ ! -d ".west" ]; then
  west init -l ./config
fi

# Git may refuse operations inside the workspace when ownership differs
# ("detected dubious ownership"). Add common safe.directory entries so
# west can initialize/update repositories inside the workspace.
if command -v git >/dev/null 2>&1; then
  git config --global --add safe.directory "${ROOT_DIR}" || true
  git config --global --add safe.directory "${WEST_WS}" || true
  # Also add any immediate child directories (e.g. zmk, zephyr) so
  # git operations won't fail due to ownership checks. This covers
  # repos created/updated by `west`.
  for d in "${WEST_WS}"/*; do
    if [ -d "${d}" ]; then
      git config --global --add safe.directory "${d}" || true
    fi
  done
fi

# 依存取得と環境反映
# Run `west update` in background and concurrently add any newly-created
# repositories under ${WEST_WS} to git's safe.directory as they appear.
if command -v git >/dev/null 2>&1; then
  west update --fetch-opt=--filter=tree:0 &
  WEST_PID=$!

  # While west is running, poll for created .git directories and register
  # them as safe.directory to avoid ownership checks failing during setup.
  while kill -0 "${WEST_PID}" 2>/dev/null; do
    # limit depth to avoid excessive scanning
    find "${WEST_WS}" -maxdepth 6 -type d -print 2>/dev/null | while read -r d; do
      if [ -d "${d}/.git" ]; then
        git config --global --add safe.directory "${d}" || true
      fi
    done
    sleep 0.5
  done
  wait "${WEST_PID}"
else
  west update --fetch-opt=--filter=tree:0
fi

west zephyr-export

echo "West workspace ready at: ${WEST_WS}"
echo "Manifest linked from: ${ORIG_MANIFEST_FILE}"