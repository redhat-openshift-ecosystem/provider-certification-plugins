#!/bin/sh

#
# Run local CI tests. (files test_*.sh)
#

set -o pipefail
set -o nounset
set -o errexit

for ts in $(ls "$(dirname $0)"/test_*.sh); do
    ./${ts}
done
