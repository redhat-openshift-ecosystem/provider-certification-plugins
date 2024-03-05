// Package version contains all identifiable versioning info for
// describing the openshift provider cert project.
package version

import (
	"fmt"
)

var (
	programName = "openshift-tests-plugin"
	version     = "unknown"
	commit      = "unknown"
)

func GetProgramName() string {
	return programName
}

func GetVersion() string {
	return version
}

func GetCommit() string {
	return commit
}

func GetFullVersion() string {
	return fmt.Sprintf("%s+%s", version, commit)
}

func GetFullProgramName() string {
	return fmt.Sprintf("%s (%s+%s)", programName, version, commit)
}
