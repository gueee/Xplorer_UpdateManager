#!/bin/bash
# Run ON THE PRINTER (bash). Backs up printer_data/config, clones/updates fork, syncs into live config.
set -euo pipefail
B="${HOME}/printer_data_config_backup_$(date +%Y%m%d_%H%M).tar.gz"
tar czf "${B}" -C "${HOME}" printer_data/config
echo "Backup: ${B}"
REPO="${HOME}/Xplorer_UpdateManager"
if [[ ! -d "${REPO}/.git" ]]; then
  git clone https://github.com/gueee/Xplorer_UpdateManager.git "${REPO}"
else
  git -C "${REPO}" fetch origin
  git -C "${REPO}" pull --ff-only origin main
fi
chmod +x "${REPO}/scripts/sync_fork_to_printer_config.sh"
bash "${REPO}/scripts/sync_fork_to_printer_config.sh" "${REPO}" "${HOME}/printer_data/config"
echo "SYNC_OK — restart Klipper from Mainsail."
