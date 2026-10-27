#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_OS:-}" == Linux ]] || {
    echo 'error: this helper is only for disposable GitHub Linux runners' >&2
    exit 2
}

# The runner's Azure mirror has repeatedly stalled mid-download. Keep the
# existing suites, components and signing keys, using Ubuntu's archive directly.
for apt_source in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources; do
    [[ -f "$apt_source" ]] || continue
    sudo sed -i \
        -e 's#mirror+file:/etc/apt/apt-mirrors.txt#https://archive.ubuntu.com/ubuntu/#g' \
        -e 's#http://azure\.archive\.ubuntu\.com/ubuntu#https://archive.ubuntu.com/ubuntu#g' \
        -e 's#https://azure\.archive\.ubuntu\.com/ubuntu#https://archive.ubuntu.com/ubuntu#g' \
        "$apt_source"
done
apt_options=(-o Acquire::Retries=3 -o Acquire::http::Timeout=30
             -o Acquire::https::Timeout=30 -o Acquire::ForceIPv4=true)
sudo apt-get "${apt_options[@]}" update
sudo env DEBIAN_FRONTEND=noninteractive apt-get "${apt_options[@]}" install -y "$@"
