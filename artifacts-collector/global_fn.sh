#!/usr/bin/env bash

# Shared functions used across plugin service.

# os_log_info logger function, printing the current bash script
# and line as prefix.
os_log_info() {
    caller_src=$(caller | awk '{print$2}')
    caller_name="$(basename -s .sh "$caller_src"):$(caller | awk '{print$1}')"
    echo "$(date --iso-8601=seconds) | [${SERVICE_NAME}] | $caller_name> " "$@"
}
export -f os_log_info

# sys_sig_handler_error handles the ERR sigspec.
sys_sig_handler_error(){
    os_log_info "[signal handler] ERROR on line $(caller)" >&2
}
trap sys_sig_handler_error ERR

# sys_sig_handler_term handles the TERM(15) sigspec.
sys_sig_handler_term() {
    os_log_info "[signal handler] TERM signal received. Caller: $(caller)"
}
trap sys_sig_handler_term TERM
