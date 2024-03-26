package exec

// TODO: run openshift-tests

// Run options:
// - Sidecar: Prepare the run script to save to a shared storage w/ run arguments
// - Local: openshift-tests binary is present in the same place the binary is running

// Functions:
// - build run args (platform, suite name, suite file list, junit dir, etc) and
// send to openshift-tests to run
// - the output of openshift-tests must be parsed to generate to a channel to generate status/progress
