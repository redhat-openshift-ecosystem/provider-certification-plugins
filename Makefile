
##############
# Formatting #
##############

.PHONY: format
format: shellcheck

.PHONY: shellcheck
shellcheck:
	hack/shellcheck.sh
