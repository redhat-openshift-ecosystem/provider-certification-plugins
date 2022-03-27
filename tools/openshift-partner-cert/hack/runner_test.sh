#!/bin/sh

#
# Run local CI tests. (files test_*.sh)
#

for ts in $(ls "$(dirname $0)"/test_*.sh); do
    ./${ts}
done
