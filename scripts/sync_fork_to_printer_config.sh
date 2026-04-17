#!/bin/bash
# Sync this repo (your fork clone) into Mainsail/Klipper printer_data layout.
# - Updates 0_Xplorer/01_Default_CFG from repo 01_Default_CFG (merge, no --delete).
# - Copies known _deploy/*.cfg templates into 01__User_Custom__CFG (machine printer.cfg unchanged).
#
# Usage:
#   bash scripts/sync_fork_to_printer_config.sh [REPO_DIR] [PRINTER_DATA_CONFIG_DIR]
# Defaults:
#   REPO_DIR=$HOME/Xplorer_UpdateManager
#   PRINTER_DATA_CONFIG_DIR=$HOME/printer_data/config

set -euo pipefail

REPO="${1:-${HOME}/Xplorer_UpdateManager}"
DEST="${2:-${HOME}/printer_data/config}"

if [[ ! -d "${REPO}/.git" ]]; then
  echo "No git repo at ${REPO}. Clone your fork first, e.g.:"
  echo "  git clone https://github.com/YOUR_USER/Xplorer_UpdateManager.git ${REPO}"
  exit 1
fi

if [[ ! -d "${DEST}" ]]; then
  echo "Config directory not found: ${DEST}"
  exit 1
fi

SRC_DEFAULT="${REPO}/01_Default_CFG"
DST_DEFAULT="${DEST}/0_Xplorer/01_Default_CFG"
SRC_DEPLOY="${REPO}/_deploy"
DST_USER="${DEST}/01__User_Custom__CFG"

if [[ ! -d "${SRC_DEFAULT}" ]]; then
  echo "Missing ${SRC_DEFAULT}"
  exit 1
fi

mkdir -p "${DST_DEFAULT}" "${DST_USER}"

echo "==> rsync ${SRC_DEFAULT}/ -> ${DST_DEFAULT}/ (no --delete: keeps extra files on printer)"
rsync -a "${SRC_DEFAULT}/" "${DST_DEFAULT}/"

if [[ -d "${SRC_DEPLOY}" ]]; then
  for f in neoprobe.cfg Tool0_carto.cfg Xplorer_V1.1_IDEX_custom.cfg lll_buffer.cfg PLR_2xExtr_carto.cfg; do
    if [[ -f "${SRC_DEPLOY}/${f}" ]]; then
      cp -a "${SRC_DEPLOY}/${f}" "${DST_USER}/${f}"
      echo "==> updated ${DST_USER}/${f}"
    fi
  done
fi

echo "==> Done. Restart Klipper from Mainsail (or: sudo systemctl restart klipper)."
