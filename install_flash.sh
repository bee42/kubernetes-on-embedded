#!/bin/bash
set -e 
set -o pipefail


curl -O https://raw.githubusercontent.com/hypriot/flash/master/flash && \
chmod +x flash && \
sudo mv flash /usr/local/bin/flash
