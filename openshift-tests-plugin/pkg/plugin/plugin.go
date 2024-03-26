package plugin

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"syscall"
	"time"

	log "github.com/sirupsen/logrus"

	"github.com/redhat-openshift-ecosystem/provider-certification-tool/pkg/client"
	sbclient "github.com/vmware-tanzu/sonobuoy/pkg/client"
	kubernetes "k8s.io/client-go/kubernetes"
)

const (
	ProgressURL = "http://127.0.0.1:8099/progress"

	FiFoPath = "/tmp/shared/fifo"

	ResultsDir      = "/tmp/sonobuoy/results"
	ResultsDoneFile = "/tmp/sonobuoy/results/done"

	SharedDir               = "/tmp/shared"
	OpenShiftTestsDoneFile  = "/tmp/shared/done"
	OpenShiftTestsRunFile   = "/tmp/shared/run"
	OpenShiftTestsJUnitDir  = "/tmp/shared/junit"
	OpenShiftTestsSuiteList = "/tmp/shared/suite.list"

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
	Progress  *PluginProgress

	DoneChan    chan bool
	DoneControl bool

	clientKube     kubernetes.Interface
	clientSonobuoy sbclient.Interface
}

func NewPlugin(name string) (*Plugin, error) {
	plugin := &Plugin{
		name:        name,
		SuiteFile:   fmt.Sprintf("%s/suite.list", SharedDir),
		Progress:    NewPluginProgress(),
		DoneChan:    make(chan bool),
		DoneControl: false,
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

	// TODO
	// Initialize dependencies: FIFO, result dir, etc
	// - create fifo
	// - create work/result dirs
	// - wait for sonobuoy worker/progress API (sidecar)
	// - login OpenShift cluster
	// - (when upgrade) check if MCP opct exists
	// - Load suite list (from sidecar)

	// Create FIFO
	err := syscall.Mknod(FiFoPath, syscall.S_IFIFO|0666, 0)
	if err != nil {
		log.Errorf("error creating FIFO on path %s: %v", FiFoPath, err)
	}

	// Create work/result dir
	if err := os.MkdirAll(ResultsDir, os.ModePerm); err != nil {
		log.Errorf("error creating result directory %s: %v", ResultsDir, err)
	}

	// TODO(mtulio): wait for progress report

	// TODO(mtulio): initialize openshift api
	kcli, sbcli, err := client.CreateClients()
	if err != nil {
		log.Errorf("error initializing the clients: %v", err)
		return nil
	}
	p.clientKube = kcli
	p.clientSonobuoy = sbcli

	// TODO(mtulio): check MachineConfigPool opct (when upgrade)

	// TODO(mtulio): load suite list, and count total, updating the progress counter.
	doneCallback := func() {
		log.Infof("Done callback for %s", OpenShiftTestsSuiteList)
	}
	log.Info("Waiting for suite list on path %d", OpenShiftTestsSuiteList)
	if err := watchForFile(OpenShiftTestsSuiteList, doneCallback); err != nil {
		log.Errorf("unable to load suite list from %d: %v", OpenShiftTestsSuiteList, err)
	}

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
			log.Info("Run: Detected done.")
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
	fmt.Println(">> Done called")
	p.DoneControl = true
	p.DoneChan <- true
}

func (p *Plugin) WatchForDone() {
	defer p.Done()

	err := watchForFile(ResultsDoneFile, p.Done)
	if err != nil {
		log.Errorf("Done file watch error: %s", err)
	}

	log.Println("Done file has been created")
}

// RunReportProgress start the loop to report progress.
func (p *Plugin) RunReportProgress() {

	// watch the file/fifo for updates
	go func() {
		for {
			if p.DoneControl {
				log.Println("Detected done. Stopping reader")
				break
			}
			fifo, err := os.Open(FiFoPath)
			if err != nil {
				log.WithError(err).Error("error reading the input stream")
				time.Sleep(1 * time.Second)
				continue
			}
			defer fifo.Close()

			scanner := bufio.NewScanner(fifo)
			for scanner.Scan() {
				line := scanner.Text()
				skip, err := p.Progress.ParserOpenShiftTestsOutputLine(line)
				if err != nil {
					log.WithError(err).Error("line parser error")
					// or return/break??
					continue
				}
				if skip {
					continue
				}
				p.Progress.UpdateTotalCounters()
				p.Progress.UpdateAndSend()
			}

			log.Printf("\n>> Preliminar summary: %s\n", p.Progress.GetTotalCountersString())
		}
	}()

	log.Println("Consuming data from stream. Waiting until is finished...")
	<-p.DoneChan
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
func (p *Plugin) Summary() {
	fmt.Printf("\n>> Summary: %s\n", p.Progress.GetTotalCountersString())
}
