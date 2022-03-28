#!/bin/sh

#
# openshift-tests-partner-cert reporter
# Send progress of openshift-tests to sonobuoy worker.
#

#set -o pipefail
#set -o nounset
#set -o errexit

source $(dirname $0)/shared.sh

sleep 10;

PASSED=0;
FAILURES="";
HAS_UPDATE=0;
#TODO(): check while done file is created by executor [${results_dir}/done]
# The pipe could be closed depending of executor strategy. For example
# If executor runs openshift-tests twice for some customization, it could broke
# the report-progress. At the same time, the report-progress should finish after
# executor has finished.
while read line;
do
    #TODO(bug): JOB_PROGRESS is not detecting the last test count. Example: 'started: (0/10/10)''
    JOB_PROGRESS=$(echo $line | grep -Po "\([0-9]{1,}\/[0-9]{1,}\/[0-9]{1,}\)" || true);
    if [ ! -z "${JOB_PROGRESS}" ]; then
        HAS_UPDATE=1;
        TOTAL=$(echo ${JOB_PROGRESS:1:-1} | cut -d'/' -f 3);

        #TODO(fix): woraround for last test which is not reporting passed/skipped
        PASSED=$(echo ${JOB_PROGRESS:1:-1} | cut -d'/' -f 2);

    #elif [[ $line == passed:* ]] || [[ $line == skipped:* ]]; then
    #    PASSED=$((PASSED + 1));
    #    HAS_UPDATE=1;

    elif [[ $line == failed:* ]]; then
        if [ -z "${FAILURES}" ]; then
            FAILURES=\"$(echo $line | cut -d"\"" -f2)\"
        else
            FAILURES=,\"$(echo $line | cut -d"\"" -f2)\"
        fi
        HAS_UPDATE=1;
    fi

    if [ $HAS_UPDATE -eq 1 ]; then
        echo "JOB_PROGRESS=[${JOB_PROGRESS}]"
        echo "DATA=[{\"completed\":$PASSED,\"total\":$TOTAL,\"failures\":[$FAILURES]}]"
        echo "Sending update..."
        curl -s http://127.0.0.1:8099/progress -d "{\"completed\":$PASSED,\"total\":$TOTAL,\"failures\":[$FAILURES]}";
        HAS_UPDATE=0;
    fi
    JOB_PROGESS="";

done <"${results_pipe}"
