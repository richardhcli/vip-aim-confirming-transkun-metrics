#!/bin/bash
# setup_env.sh
# Handles in-place conda environment creation and syncing.

VENV_DIR=$1
ENV_FILE=$2
INSTALL_LOG=$3

echo -e "\t* Syncing environment with $ENV_FILE..."

# This ONE command handles creation, updating, and installing all packages
# --prune: removes packages that are no longer in the environment.yml
conda env update --prefix "$VENV_DIR" --file "$ENV_FILE" --prune >> "$INSTALL_LOG" 2>&1

if [ $? -eq 0 ]; then
    echo -e "\t* Environment synced successfully!"
else
    echo -e "\t* ERROR: Environment sync failed. Check $INSTALL_LOG for details."
    exit 1
fi