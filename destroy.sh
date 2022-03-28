#!/usr/bin/env sh

set -o pipefail
set -o nounset
set -o errexit

sonobuoy delete --wait
