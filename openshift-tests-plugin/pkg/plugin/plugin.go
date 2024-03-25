package plugin

import (
	"errors"
	"fmt"
	"os"
	"time"

	log "github.com/sirupsen/logrus"
)

const (
	ProgressURL = "http://127.0.0.1:8099/progress"

	FiFoPath               = "/tmp/shared/fifo"
	ResultsDir             = "/tmp/sonobuoy/results"
	SharedDir              = "/tmp/shared"
	OpenShiftTestsDoneFile = "/tmp/shared/done"
	OpenShiftTestsRunFile  = "/tmp/shared/run"
	OpenShiftTestsJUnitDir = "/tmp/shared/junit"

	DefaultOpenShiftTestsRunMonitors    = "etcd-log-analyzer"
	DefaultOpenShiftTestsRunMaxParallel = "0"

	// WaitThresholdNotify defines the interval to notify for waiting message. Default 5m.
	WaitThresholdNotify = 300
	// WaitThresholdLimit defines the limit to wait for done file. Default 4h.
	WaitThresholdLimit = 1440

	KubeApiServerInternal = "https://172.30.0.1:443"
	KubeApiServerSACertCA = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
	KubeApiServerSAToken  = "/var/run/secrets/kubernetes.io/serviceaccount/token"

	PluginId05    = "05"
	PluginName05  = "openshift-cluster-upgrade"
	PluginSuite05 = "none"

	PluginId10    = "10"
	PluginName10  = "openshift-kube-conformance"
	PluginSuite10 = "kubernetes/conformance"

	PluginId20    = "20"
	PluginName20  = "openshift-conformance-validated"
	PluginSuite20 = "openshift/conformance"

	PluginId80    = "80"
	PluginName80  = "openshift-tests-replay"
	PluginSuite80 = "openshift/conformance"

	PluginId99    = "99"
	PluginName99  = "openshift-artifacts-collector"
	PluginSuite99 = "openshift/conformance"
)

type Plugin struct {
	name      string
	id        string
	SuiteName string
	SuiteFile string
}

func NewPlugin(name string) (*Plugin, error) {
	plugin := &Plugin{
		name:      name,
		SuiteFile: fmt.Sprintf("%s/suite.list", SharedDir),
	}
	switch plugin.name {
	case PluginName05:
		plugin.id = PluginId05
		plugin.SuiteName = PluginSuite05
	case PluginName10:
		plugin.id = PluginId10
		plugin.SuiteName = PluginSuite10
	case PluginName20:
		plugin.id = PluginId20
		plugin.SuiteName = PluginSuite20
	case PluginName80:
		plugin.id = PluginId80
		plugin.SuiteName = PluginSuite80
	default:
		return nil, fmt.Errorf("Plugin unknown. Unable to initialize plugin service")
	}
	return plugin, nil
}

func (p *Plugin) FullName() string {
	return fmt.Sprintf("%s-%s", p.id, p.name)
}

func (p *Plugin) ID() string {
	return p.id
}

// Initialize resolve all dependencies before running the plugin.
func (p *Plugin) Initialize() error {

	return nil
}

// Run send the start command.
func (p *Plugin) Run() error {

	ocmd := "run"
	switch p.name {
	case PluginName05:
		ocmd = "run-upgrade"
	}
	orun := NewOpenShiftRunCommand(ocmd, p.SuiteName)

	// check "isDevRun" and limit the execution from suite to file

	err := orun.Create()
	if err != nil {
		log.Errorf("unable to create run file: %v", err)
	}

	// Wait for run-done
	// TODO: add watch file with context timeout
	// TODO(mtulio): do we need to check for error file?
	log.Infof("Waiting for execution done [%s]", OpenShiftTestsDoneFile)
	threshold := 0
	for {
		if _, err := os.Stat(OpenShiftTestsDoneFile); err == nil {
			fmt.Println("Detected done.")
		} else if errors.Is(err, os.ErrNotExist) {
			time.Sleep(1 * time.Second)
			if threshold >= WaitThresholdLimit {
				return fmt.Errorf("timeout while waitinf for done file %s", OpenShiftTestsDoneFile)
			}
			// every 5 minutes emit the waiting message
			if (threshold % WaitThresholdNotify) == 0 {
				log.Infof("waiting for done file %s", OpenShiftTestsDoneFile)
			}
			threshold++
			continue
		} else {
			// file may or may not exist. See err for details.
			log.Errorf("Unexpacted errors while waiting for done file: %v", err)
		}
		break
	}

	return nil
}

// Run sends the done signal to Sonobuoy.
func (p *Plugin) Done() {

}

// RunReportProgress start the loop to report progress.
func (p *Plugin) RunReportProgress() {

}

// RunDependencyWaiter runs the dependency loop checker.
func (p *Plugin) RunDependencyWaiter() error {

	return nil
}

// Save collects the JUnit results, parse it and save to result dir.
func (p *Plugin) Save() error {

	return nil
}

// Summary shows the summary and exit.
func (p *Plugin) Summary() error {

	return nil
}
