#!/bin/sh

#
# openshift-tests-partner-cert reporter
# Send progress of openshift-tests to sonobuoy worker.
#

results_dir="${RESULTS_DIR:-/tmp/sonobuoy/results}"
results_pipe="${results_dir}/status_pipe"

sleep 10;        
PASSED=0;
FAILURES="";        
HAS_UPDATE=0;
while read line; 
do
    JOB_PROGRESS=$(echo $line | grep -Po "\([0-9]{1,}\/[0-9]{1,}\/[0-9]{1,}\)");            
    if [ ! -z "${JOB_PROGRESS}" ]; then              
        TOTAL=$(echo ${JOB_PROGRESS:1:-1} | cut -d'/' -f 3);  
        HAS_UPDATE=1;                          

    elif [[ $line == passed:* ]] || [[ $line == skipped:* ]]; then
        PASSED=$((PASSED + 1));
        HAS_UPDATE=1;

    elif [[ $line == failed:* ]]; then              
        if [ -z "${FAILURES}" ]; then
        FAILURES=\"$(echo $line | cut -d"\"" -f2)\"
        else
        FAILURES=,\"$(echo $line | cut -d"\"" -f2)\"
        fi
        HAS_UPDATE=1;
    fi

    if [ $HAS_UPDATE -eq 1 ]; then
        curl -v http://127.0.0.1:8099/progress -d "{\"completed\":$PASSED,\"total\":$TOTAL,\"failures\":[$FAILURES]}";
        HAS_UPDATE=0;
    fi
    JOB_PROGESS="";

done <"${results_pipe}"
