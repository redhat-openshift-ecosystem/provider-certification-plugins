package plugin

import (
	"bufio"
	"context"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"math/rand"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	log "github.com/sirupsen/logrus"

	occlient "github.com/openshift/client-go/config/clientset/versioned"

	sbclient "github.com/vmware-tanzu/sonobuoy/pkg/client"
	kcorev1 "k8s.io/api/core/v1"
	kmmetav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	kubernetes "k8s.io/client-go/kubernetes"
	"k8s.io/utils/ptr"
)

const (
	EnvNamespace = "opct"

	ProgressURL = "http://127.0.0.1:8099/progress"

	FiFoPath = "/tmp/shared/fifo"

	ResultsDir      = "/tmp/sonobuoy/results"
	ResultsDoneFile = "/tmp/sonobuoy/results/done"

	SharedDir               = "/tmp/shared"
	OpenShiftTestsDoneFile  = "/tmp/shared/done"
	OpenShiftTestsRunFile   = "/tmp/shared/start"
	OpenShiftTestsJUnitDir  = "/tmp/shared/junit"
	OpenShiftTestsSuiteList = "/tmp/shared/suite.list"
	OTestsSuiteListComplete = "/tmp/shared/suite.list.done"

	DefaultOpenShiftTestsRunMonitors    = "etcd-log-analyzer"
	DefaultOpenShiftTestsRunMaxParallel = "0"

	// WaitThresholdNotify defines the interval to notify for waiting message. Default 5m.
	WaitThresholdNotify = 300
	// WaitThresholdLimit defines the limit to wait for done file. Default 4h.
	WaitThresholdLimit = 14400

	KubeApiServerInternal = "https://172.30.0.1:443"
	KubeApiServerSACertCA = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
	KubeApiServerSAToken  = "/var/run/secrets/kubernetes.io/serviceaccount/token"

	PluginId05    = "05"
	PluginName05  = "openshift-cluster-upgrade"
	PluginAlias05 = "05-openshift-cluster-upgrade"
	PluginSuite05 = "none"

	PluginId10    = "10"
	PluginName10  = "openshift-kube-conformance"
	PluginAlias10 = "10-openshift-kube-conformance"
	PluginSuite10 = "kubernetes/conformance"

	PluginId20    = "20"
	PluginName20  = "openshift-conformance-validated"
	PluginAlias20 = "20-openshift-conformance-validated"
	PluginSuite20 = "openshift/conformance"

	PluginId80    = "80"
	PluginName80  = "openshift-tests-replay"
	PluginAlias80 = "80-openshift-tests-replay"
	PluginSuite80 = "all"

	PluginId99    = "99"
	PluginName99  = "openshift-artifacts-collector"
	PluginAlias99 = "99-openshift-artifacts-collector"
	PluginSuite99 = "all"

	ExecModeDefault = "default"
	ExecModeUpgrade = "upgrade"
)

// Plugin represents the plugin service.
type Plugin struct {
	name string
	id   string

	Timeout time.Duration

	SuiteName  string
	SuiteFile  string
	SuiteTests map[string]struct{}

	BlockerPlugins []*Plugin
	Progress       *PluginProgress

	Namespace string

	// Runtime
	clientKube     kubernetes.Interface
	clientSonobuoy sbclient.Interface
	DoneChan       chan bool
	DoneControl    bool

	// OTRunner is the test runner command to schedule openshift-tests run.
	OTRunner *OpenShiftTestsRunCommand

	// ExecMode is the execution mode for the workflow. Default: default
	// Valid values: default, upgrade
	ExecMode string
}

// NewPlugin creates a new plugin service.
func NewPlugin(name string) (*Plugin, error) {
	p := &Plugin{
		name:        name,
		Namespace:   EnvNamespace,
		SuiteFile:   fmt.Sprintf("%s/suite.list", SharedDir),
		Progress:    NewPluginProgress(),
		DoneChan:    make(chan bool),
		DoneControl: false,
		ExecMode:    ExecModeDefault,
	}
	switch p.name {
	case PluginName05, PluginAlias05:
		p.id = PluginId05
		p.SuiteName = PluginSuite05
		p.OTRunner = NewOpenShiftRunCommand("run-upgrade", p.SuiteName)
		p.Timeout = 3 * time.Hour
	case PluginName10, PluginAlias10:
		p.id = PluginId10
		p.SuiteName = PluginSuite10
		p.BlockerPlugins = []*Plugin{{name: PluginName05}}
		p.OTRunner = NewOpenShiftRunCommand("run", p.SuiteName)
		p.Timeout = 2 * time.Hour
	case PluginName20, PluginAlias20:
		p.id = PluginId20
		p.SuiteName = PluginSuite20
		p.BlockerPlugins = []*Plugin{{name: PluginName10}}
		p.OTRunner = NewOpenShiftRunCommand("run", p.SuiteName)
		p.Timeout = 4 * time.Hour
	case PluginName80, PluginAlias80:
		p.id = PluginId80
		p.SuiteName = PluginSuite80
		p.BlockerPlugins = []*Plugin{{name: PluginName20}}
		p.OTRunner = NewOpenShiftRunCommand("run", p.SuiteName)
		p.OTRunner.File = p.SuiteFile
		p.OTRunner.MaxParallel = "1"
		p.Timeout = 1 * time.Hour
	case PluginName99, PluginAlias99:
		p.id = PluginId99
		p.SuiteName = PluginSuite99
		p.BlockerPlugins = []*Plugin{{name: PluginName80}}
		p.Timeout = 1 * time.Hour
	default:
		return nil, fmt.Errorf("unknown plugin name %q", name)
	}
	return p, nil
}

// FullName returns the full name of the plugin.
func (p *Plugin) FullName() string {
	return fmt.Sprintf("%s-%s", p.id, p.name)
}

// ID returns the plugin ID.
func (p *Plugin) ID() string {
	return p.id
}

// Name returns the plugin name.
func (p *Plugin) Name() string {
	return p.name
}

// PluginFullNameByName returns the full name (including ID) of the plugin by name.
func (p *Plugin) PluginFullNameByName(name string) string {
	id := ""
	switch name {
	case PluginName05:
		id = PluginId05
	case PluginName10:
		id = PluginId10
	case PluginName20:
		id = PluginId20
	case PluginName80:
		id = PluginId80
	}
	return fmt.Sprintf("%s-%s", id, name)
}

// Initialize resolve all dependencies before running the plugin.
func (p *Plugin) Initialize() error {
	// TODO send a message to aggregator indicating for "initialization" state.
	// The following message is sent by script version: "status=initializing"
	// Create work/result dir
	if err := os.MkdirAll(ResultsDir, os.ModePerm); err != nil {
		log.Errorf("error creating result directory %s: %v", ResultsDir, err)
	}

	// Create FIFO
	if err := syscall.Mknod(FiFoPath, syscall.S_IFIFO|0666, 0); err != nil {
		return fmt.Errorf("error creating FIFO on path %s: %v", FiFoPath, err)
	}

	// Initialize kube and sonobuoy clients
	kcli, sbcli, err := CreateClients()
	if err != nil {
		log.Errorf("error initializing the clients: %v", err)
		return nil
	}
	p.clientKube = kcli
	p.clientSonobuoy = sbcli

	// Set top level env vars from config
	// TODO move env vars discovery to a separate function

	// MIRROR_IMAGE_REPOSITORY is used in disconnected/mirrored environments
	envMirror := os.Getenv("MIRROR_IMAGE_REPOSITORY")
	if len(envMirror) > 0 {
		if p.OTRunner != nil {
			p.OTRunner.FromRepository = envMirror
		}
	}

	// UPGRADE_RELEASES is used to upgrade the cluster
	envRunMode := os.Getenv("RUN_MODE")
	if len(envRunMode) > 0 {
		switch envRunMode {
		case ExecModeUpgrade:
			p.ExecMode = ExecModeUpgrade
		case "normal":
			p.ExecMode = ExecModeDefault
		default:
			p.ExecMode = ExecModeDefault
		}
	}
	envUpgradeRelease := os.Getenv("UPGRADE_RELEASES")
	if p.ExecMode == ExecModeUpgrade && len(envUpgradeRelease) > 0 {
		if p.OTRunner != nil {
			p.OTRunner.ToImage = envUpgradeRelease
		}
	}

	if p.id == PluginId99 {
		// TODO extract the results
		return nil
	}

	// Wait for suite list complete
	doneCallback := func() {
		log.Infof("Done callback for %s", OTestsSuiteListComplete)
	}
	log.Infof("Waiting for suite list complete %s", OTestsSuiteListComplete)
	if err := watchForFile(OTestsSuiteListComplete, doneCallback); err != nil {
		log.Errorf("unable to watch done suite list on %s: %v", OTestsSuiteListComplete, err)
	}

	log.Infof("Loading total test count from %s", OpenShiftTestsSuiteList)
	p.SuiteTests, err = ParseSuiteList(OpenShiftTestsSuiteList)
	if err != nil {
		log.Errorf("unable to load suite list from %s: %v", OpenShiftTestsSuiteList, err)
	}
	log.Infof("Total test count: %d", len(p.SuiteTests))

	if err := p.InitalizeDevelMode(); err != nil {
		log.Errorf("error setting up devel mode: %v", err)
	}

	p.Progress.Set(&PluginProgress{TotalCount: ptr.To(int64(len(p.SuiteTests)))})

	// TODO(mtulio) - upgrade only: check MachineConfigPool opct exists.
	// Q(^) should we validate in CLI only or create (pre) and delete(post) in plugin?

	return nil
}

// ExtractTestsToReplay loads the suite list from the ConfigMap and save to the suite file.
func (p *Plugin) ExtractTestsToReplay() error {
	// Explicitly exclude some tests from the replay list.
	// TODO move to external function to be used in other XML/JUnit/test parsers.
	testExcludeList := []string{
		"[sig-arch] External binary usage",
	}
	isInExcludeList := func(t string) bool {
		for _, e := range testExcludeList {
			if t == e {
				return true
			}
		}
		return false
	}
	foundConfig := false
	tests := map[string]struct{}{}

	// Consume config map created by each plugin with it's failures.
	cmName := "plugin-failures-10"
	cm10, err := p.clientKube.CoreV1().ConfigMaps(p.Namespace).Get(context.TODO(), cmName, kmmetav1.GetOptions{})
	if err != nil {
		log.Errorf("unable to retrieve ConfigMap %s: %v", cmName, err)
	}
	if err == nil {
		suiteListData := cm10.Data["replay.list"]
		for _, line := range strings.Split(suiteListData, "\n") {
			if isInExcludeList(line) {
				continue
			}
			foundConfig = true
			tests[line] = struct{}{}
		}
		log.Infof("Total failed tests to replay after processing plugin %s: %d", cmName, len(tests))
	}

	cmName = "plugin-failures-20"
	cm20, err := p.clientKube.CoreV1().ConfigMaps(p.Namespace).Get(context.TODO(), cmName, kmmetav1.GetOptions{})
	if err != nil {
		log.Errorf("unable to retrieve ConfigMap %s: %v", cmName, err)
	}
	if err == nil {
		suiteListData := cm20.Data["replay.list"]
		for _, line := range strings.Split(suiteListData, "\n") {
			if isInExcludeList(line) {
				continue
			}
			foundConfig = true
			tests[line] = struct{}{}
		}
		log.Infof("Total failed tests to replay after processing plugin %s: %d", cmName, len(tests))
	}

	if !foundConfig {
		log.Warnf("No tests to replay.")
		if err := NewJUnitTestReport(&JUnitTestReport{
			Filepath: "/tmp/shared/junit/junit_e2e_replay_skip.xml",
			Result:   "skipped",
			Name:     "[opct] replay list is available",
			Message:  "No tests to replay were found, skipping the plugin",
		}).Write(); err != nil {
			return fmt.Errorf("replay junit builder: error writing xml: %w", err)
		}
		return nil
	}

	// Saving the suite list to a file for replay.
	suiteListData := ""
	for testName := range tests {
		suiteListData += testName + "\n"
	}
	log.Infof("Rewriting the new suite list to file %s", p.SuiteFile)
	if err := os.WriteFile(p.SuiteFile, []byte(suiteListData), 0644); err != nil {
		log.Errorf("error saving suite list to file: %v", err)
	}

	// Update 'openshift-tests run' flag '--file' to active execution with custom suite file
	p.OTRunner.File = p.SuiteFile
	p.SuiteTests = tests
	p.Progress.Set(&PluginProgress{TotalCount: ptr.To(int64(len(tests)))})

	return nil
}

// InitializeDevelMode sets up the devel mode for the plugin.
func (p *Plugin) InitalizeDevelMode() error {
	devCountStr := os.Getenv("DEV_MODE_COUNT")
	var devCount int
	var err error

	// Devel mode isn't enabled (env var not set)
	if len(devCountStr) == 0 {
		return nil
	}
	if len(devCountStr) > 0 {
		devCount, err = strconv.Atoi(devCountStr)
		if err != nil {
			log.Errorf("error converting DEV_MODE_COUNT to int: %v", err)
			devCount = 0
		}
	}

	// Devel mode/flag is enabled but no count set.
	if devCount == 0 {
		return nil
	}

	switch p.name {
	case PluginName10, PluginName20:
		log.Infof("DEV_MODE_COUNT=%d", devCount)
		newTestMap := map[string]struct{}{}

		// Randomize the test list
		r := rand.New(rand.NewSource(time.Now().UnixNano()))
		randShuffle := func(arr []string) {
			r.Shuffle(len(arr), func(i, j int) { arr[i], arr[j] = arr[j], arr[i] })
		}
		testList := make([]string, 0, len(p.SuiteTests))
		for testName := range p.SuiteTests {
			testList = append(testList, testName)
		}
		for i := 0; i < 10; i++ {
			randShuffle(testList)
		}
		// Limit the test list to the DEV_MODE_COUNT
		if devCount > len(testList) {
			log.Warnf("DEV_MODE_COUNT(%d) is greater than the total test count(%d), truncating...", devCount, len(testList))
			devCount = len(testList)
		}
		for i := 0; i < devCount; i++ {
			testName := testList[i]
			newTestMap[testName] = struct{}{}
		}
		// save new list
		p.SuiteTests = newTestMap
		log.Infof("Total test count overrided on DEV mode: %d", len(p.SuiteTests))

		// persisting the new list
		// Save the SuiteTests map to a file
		p.SuiteFile = OpenShiftTestsSuiteList
		suiteListData := ""
		for testName := range p.SuiteTests {
			suiteListData += testName + "\n"
		}
		log.Infof("Rewriting the new suite list to file %s", p.SuiteFile)
		if err := os.WriteFile(p.SuiteFile, []byte(suiteListData), 0644); err != nil {
			log.Errorf("error saving suite list to file: %v", err)
		}

		// Update 'openshift-tests run' flag '--file' to active execution with custom suite file
		p.OTRunner.File = p.SuiteFile

	default:
		log.Infof("Skipping DEV_MODE_COUNT in plugin %s.", p.name)
	}

	return nil
}

// Run send the start command.
func (p *Plugin) Run() error {
	// generate the suite list for replay plugin
	if p.id == PluginId80 {
		if err := p.ExtractTestsToReplay(); err != nil {
			return fmt.Errorf("error initialiazing suite for replay plugin: %v", err)
		}
	}

	// Skip the plugin execution when plugin is upgrade in 'default' mode (non-upgrade).
	if p.id == PluginId05 && p.ExecMode == ExecModeDefault {
		junit := NewJUnitTestReport(&JUnitTestReport{
			Filepath: "/tmp/shared/junit/junit_e2e_upgrade_skip.xml",
			Result:   "skipped",
			Name:     "[opct] run suite in default execution mode",
			Message:  "Skipping the plugin execution the execution mode 'default'",
		})
		if err := junit.Write(); err != nil {
			return fmt.Errorf("error writing custom junit: %w", err)
		}
		// create start command in the tests container/process
		if err := p.OTRunner.CreateSkip(); err != nil {
			return fmt.Errorf("unable to create run skip script: %w", err)
		}
	} else {
		// create start command in the tests container/process
		if err := p.OTRunner.Create(); err != nil {
			log.Errorf("unable to create run script: %v", err)
		}
	}

	// Wait for run-done
	// TODO: add watch file with context timeout
	// TODO(mtulio): do we need to check for error file?
	log.Infof("Waiting for execution done [%s]", OpenShiftTestsDoneFile)
	threshold := 0
	backoffSeconds := []int{1, 2, 4, 8}
	for {
		if _, err := os.Stat(OpenShiftTestsDoneFile); err == nil {
			log.Info("Run: Detected done.")
			p.DoneControl = true
			break
		} else if errors.Is(err, os.ErrNotExist) {
			sec := backoffSeconds[threshold%len(backoffSeconds)]
			log.Debugf("backoff waiting %d seconds for done file %s", sec, OpenShiftTestsDoneFile)
			time.Sleep(time.Duration(sec) * time.Second)
			if threshold >= WaitThresholdLimit {
				return fmt.Errorf("timeout while waiting for done file %s", OpenShiftTestsDoneFile)
			}
			// every 5 minutes emit the waiting message
			if (threshold % WaitThresholdNotify) == 0 {
				log.Debugf("waiting for done file %s", OpenShiftTestsDoneFile)
			}
			threshold++
			continue
		} else {
			// file may or may not exist. See err for details.
			log.Errorf("Unexpected errors while waiting for done file: %v", err)
		}
		break
	}

	return nil
}

// Done sends the done signal to Sonobuoy worker.
func (p *Plugin) Done() {
	log.Info("Plugin done controller activated.")
	p.DoneControl = true
	go func() { p.DoneChan <- true }()
}

// WatchForDone watches for the runtime (sonobuoy) done file.
func (p *Plugin) WatchForDone() {
	defer p.Done()

	if err := watchForFile(ResultsDoneFile, p.Done); err != nil {
		log.Errorf("Done file watch error: %s", err)
	}

	log.Infof("Done file has been created at path %s\n", ResultsDoneFile)
}

// RunReportProgress start the file/fifo scanner to report the progress, reading the
// data from the fifo, parsing it and sending to the aggregator server.
func (p *Plugin) RunReportProgress() {
	go func() {
		log.Info("Starting progress report reader...")
		for {
			if p.DoneControl {
				log.Info("Detected done. Stopping reader on progress report.")
				break
			}

			fifo, err := os.Open(FiFoPath)
			if err != nil {
				log.WithError(err).Error("error reading the input stream")
				fifo.Close()
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
				go func() { p.Progress.UpdateAndSend() }()
			}
			log.Infof(">> Preliminary summary: %s", p.Progress.GetTotalCountersString())
		}
	}()
}

// RunReportProgressUpgrade reports the upgrade progress to aggregator API.
func (p *Plugin) RunReportProgressUpgrade() {
	if p.id != PluginId05 {
		log.Warnf("Plugin %s is not an upgrade plugin. Skipping upgrade progress report.", p.name)
		return
	}
	if p.ExecMode != ExecModeUpgrade {
		log.Warnf("Workflow %q is not the upgrade mode. Skipping upgrade progress report.", p.ExecMode)
		return
	}
	// Get ConfigV1 client for Cluster Operators
	restConfig, err := CreateKubeRestConfig()
	if err != nil {
		// TODO return error or move to init
		return
	}
	oc, err := occlient.NewForConfig(restConfig)
	if err != nil {
		// TODO return error and/or move to init
		return
	}
	log.Debugf("Starting upgrade progress report...")
	for {
		if p.DoneControl {
			log.Info("Detected done. Stopping upgrade progress report.")
			break
		}
		cv, err := oc.ConfigV1().ClusterVersions().Get(context.TODO(), "version", kmmetav1.GetOptions{})
		if err != nil {
			log.Error("Error getting cluster version")
			time.Sleep(5 * time.Second)
			continue
		}
		progressingStatus := "False"
		progressingMessage := ""
		for _, cond := range cv.Status.Conditions {
			if cond.Type == "Progressing" {
				progressingStatus = string(cond.Status)
				if cond.Message != "" {
					progressingMessage = string(cond.Message)
				}
			}
		}

		msgProgress := fmt.Sprintf("upgrade-progressing=%s", progressingStatus)
		if progressingStatus == "True" {
			msgProgress = progressingMessage
		} else {
			msgProgress = fmt.Sprintf("%s=%s", cv.Status.Desired.Version, msgProgress)
		}

		msgProgress = fmt.Sprintf("status=%s", msgProgress)

		p.Progress.Set(&PluginProgress{ProgressMessage: &msgProgress})
		go func() { p.Progress.UpdateAndSend() }()
		log.Info("waiting 10s for the next check for upgrade progress...")
		time.Sleep(10 * time.Second)
	}
}

// RunDependencyWaiter runs the blocker plugin controller to ensure plugin/step
// runs only after the previous plugin has been finished.
func (p *Plugin) RunDependencyWaiter() error {
	if len(p.BlockerPlugins) == 0 {
		return nil
	}
	pluginBlocker := p.BlockerPlugins[0].name
	pluginBlockerPodName := p.PluginFullNameByName(pluginBlocker)

	// TODO: move to context setting timeout in hours.
	// TODO: introduce workflow, step/plugin, and blocker timeouts in the plugin,
	// to coordinate the execution and avoid infinite loops.
	// TODO deprecate counters in favor of time calculation
	currentCheckCount := int64(0)
	limitCheckCount := int64(2000)
	lastCheckCount := int64(0)
	sleepIntervalSeconds := 10

	// TODO move timeout to global config.
	timeInit := time.Now()
	timeLimit := timeInit.Add(6 * time.Hour)

	log.Infof("Initializing dependency waiter for plugin[%s] blocked by[%s]...", p.Name(), pluginBlocker)
	// msgPrefix := fmt.Sprintf("Dependency controller for plugin=%s blocked by=%s", p.Name(), pluginBlocker)
	backoffSeconds := []int{1, 2, 4, 8, 16}
	backoffCount := 0
	for {
		log.Infof("Reconciling blocker plugin waiter: plugin=%s blocked by=%s", p.Name(), pluginBlocker)

		checkTime := time.Now()
		msgPrefixReconciling := fmt.Sprintf("[%v/%v] reconciling", checkTime.Sub(timeInit), timeLimit.Sub(timeInit))

		if p.DoneControl {
			log.Info("Done control detected. Stopping dependency waiter...")
			break
		}

		// scrap Sonobuoy API
		_, pStatusBlocker, err := p.GetPluginsBlocker()
		if err != nil {
			errMsg := fmt.Sprintf("error getting Sonobuoy Aggregator API info: %v", err)
			if backoffCount < len(backoffSeconds) {
				time.Sleep(time.Duration(backoffSeconds[backoffCount]) * time.Second)
				backoffCount++
				log.Errorf("%s [%d/%d]", errMsg, backoffCount, len(backoffSeconds))
				continue
			}
			log.Errorf("timeout waiting for blocker plugin[%s].", pluginBlocker)
			return fmt.Errorf(errMsg)
		}

		pod, _ := GetPluginPod(p.clientKube, p.Namespace, pluginBlockerPodName)
		podPhase := GetPodStatusString(pod)

		log.Infof("%s: blocker info: status=%s podPhase=%s", msgPrefixReconciling, pStatusBlocker.Status, podPhase)

		// Condition 1) check freeze timeout, reset threshold if plugin progress the execution and wait
		// TODO ${count} -gt ${last_count}
		blockerProgressCount := int64(0)
		if pStatusBlocker.Progress != nil {
			blockerProgressCount = pStatusBlocker.Progress.Completed
		}
		blockerProgressTotal := int64(0)
		if pStatusBlocker.Progress != nil {
			blockerProgressTotal = pStatusBlocker.Progress.Total
		}
		remaining := (blockerProgressTotal - blockerProgressCount) * (-1)
		pluginMessageState := ""

		// Condition 2) check blocker is also blocked. If blocker plugins is also blocked, reset freeze timeout and wait
		// TODO plugin has status=blocked-by
		if pStatusBlocker.Progress != nil &&
			strings.HasPrefix(pStatusBlocker.Progress.Message, "status=waiting-for") {
			pluginMessageState = "blocked-by"
		} else if pStatusBlocker.Progress != nil &&
			strings.HasPrefix(pStatusBlocker.Progress.Message, "status=blocked-by") {
			pluginMessageState = "blocked-by"
		} else {
			pluginMessageState = "waiting-for"
		}

		// mount the plugin message and update API
		log.Infof("%s: sending message=%s", msgPrefixReconciling, pluginMessageState)
		msg := fmt.Sprintf("status=%s=%s=(0/%d/0)=[%d/%d]", pluginMessageState, pluginBlocker, remaining, currentCheckCount, limitCheckCount)
		p.Progress.Set(&PluginProgress{ProgressMessage: &msg})
		p.Progress.UpdateAndSend()

		if pStatusBlocker.Status == "complete" || pStatusBlocker.Status == "failed" || podPhase == "Completed" {
			log.Infof("Plugin[%s] with status[%s] is in unblocker condition!", pluginBlocker, pStatusBlocker.Status)
			break
		}

		// TODO review the state: pod failed or completed
		if podPhase == "Failed" || podPhase == "NotReady" {
			lastCheckCount = blockerProgressCount
			currentCheckCount += 1
			if currentCheckCount >= 10 {
				// TODO/Q: should we send a message to the aggregator?
				// TODO/Q: should we return error or just stop/break plugin execution?
				log.Errorf("Pod[%s] is in failed state or returned unxpected value (Phase==[%s]). Stop waiter and continue...", pluginBlocker, podPhase)
				break
			}
			log.Infof("%s: pod[%s] is in failed state or returned unexpected value (Phase==[%s]). Starting timeout...", msgPrefixReconciling, pluginBlocker, podPhase)
			time.Sleep(5 * time.Second)
			continue
		}
		if pStatusBlocker.Progress != nil && pStatusBlocker.Progress.Completed > lastCheckCount {
			lastCheckCount = blockerProgressCount
			currentCheckCount = 0
			log.Debugf("%s: skipping timeout when blocker is progressing: %d/%d...", msgPrefixReconciling, lastCheckCount, currentCheckCount)
			time.Sleep(time.Duration(sleepIntervalSeconds))
			continue
		}

		// ignore timeout when blocker is progressing
		if pStatusBlocker.Progress != nil && strings.HasPrefix(pStatusBlocker.Progress.Message, "status=blocked-by") {
			currentCheckCount = 0
			log.Debugf("%s: skipping timeout when is already blocked", msgPrefixReconciling)
			time.Sleep(time.Duration(sleepIntervalSeconds))
			continue
		}

		// ignore timeout when blocker is also blocked
		if pStatusBlocker.Progress != nil &&
			strings.HasPrefix(pStatusBlocker.Progress.Message, "status=blocked-by") &&
			strings.HasPrefix(pluginMessageState, "status=blocked-by") {
			currentCheckCount = 0
			log.Debugf("%s: skipping timeout when blocker's plugin is also blocked", msgPrefixReconciling)
			time.Sleep(time.Duration(sleepIntervalSeconds))
			continue
		}

		// ignore timeout when blocker is the next in the queue,
		// and current plugin state is blocked
		// increment timeout counter and wait
		// lastCheckCount = blockerProgressCount
		// currentCheckCount += 1
		// if currentCheckCount >= limitCheckCount {
		if timeInit.After(timeLimit) {
			// TODO send update message?
			return fmt.Errorf("timeout waiting condition 'complete' for plugin[%s]", p.name)
		}
		log.Infof("%s: waiting %d seconds for the next check...", msgPrefixReconciling, sleepIntervalSeconds)
		time.Sleep(time.Duration(sleepIntervalSeconds) * time.Second)
	}

	log.Infof("Plugin blocker waiter is unlocked.")
	return nil
}

// Summary shows the summary and exit.
func (p *Plugin) Summary() {
	log.Infof(">> Summary: %s", p.Progress.GetTotalCountersString())

	log.Println("Showing summary by rank of slower test")
	// TODO make as an option:
	optReverse := true
	optLimit := int64(10)
	for idx, e2e := range rankTestsByTimeTaken(p.Progress.TestMap, "TimeTookSeconds", optReverse) {
		fmt.Printf("%s (%.3f) %s\n", e2e.Result, e2e.TimeTookSeconds, e2e.TestName)
		if optLimit != 0 && int64(idx) >= optLimit {
			break
		}
	}
}

// ProcessJUnit collects the JUnit results, parse it and save to result dir.
func (p *Plugin) ProcessJUnit() error {
	log.Info("JUnit processor started!")
	xmlFiles, err := filepath.Glob("/tmp/shared/junit/junit_e2e_*.xml")
	if err != nil {
		return fmt.Errorf("error finding XML files: %w", err)
	}
	if len(xmlFiles) == 0 {
		if p.id != PluginId80 {
			return fmt.Errorf("no JUnit/XMLs files found")
		}
		// TODO move this check/fallback to somewhere more appropriated?
		xmlSkip := "/tmp/shared/junit/junit_e2e_replay_skip.xml"
		if err := NewJUnitTestReport(&JUnitTestReport{
			Filepath: xmlSkip,
			Result:   "skipped",
			Name:     "[opct] replay runner did not generate JUnit file, see container 'tests' for more details",
			Message: fmt.Sprintf(`README: read the 'tests' container to check why plugin didn't generated the results.
			Skipping plugin %s as JUnit file has been generated by the following replay test list: %v`, p.name, p.SuiteTests),
		}).Write(); err != nil {
			return fmt.Errorf("replay junit builder: error writing xml: %w", err)
		}
		xmlFiles = append(xmlFiles, xmlSkip)
	}

	for _, xmlFilePath := range xmlFiles {
		newFilePath := filepath.Join(ResultsDir, filepath.Base(xmlFilePath))
		log.Infof("moving XML file [%s] to [%s]", xmlFilePath, newFilePath)

		// Copy file instead of move, because the move issue:
		// os.Rename() give error "invalid cross-device link" in container's volumes.
		xmlFD, err := os.Open(xmlFilePath)
		if err != nil {
			return fmt.Errorf("couldn't open source file: %s", err)
		}
		newFileFD, err := os.Create(newFilePath)
		if err != nil {
			xmlFD.Close()
			return fmt.Errorf("couldn't open dest file: %s", err)
		}
		defer newFileFD.Close()
		_, err = io.Copy(newFileFD, xmlFD)
		xmlFD.Close()
		if err != nil {
			return fmt.Errorf("writing to output file failed: %s", err)
		}
	}

	xmlFile := xmlFiles[0]
	resultJunitFile := filepath.Join(ResultsDir, filepath.Base(xmlFile))

	if err := p.ParseAndExtractFailuresFromJunit(
		"/tmp/shared/suite.list",
		resultJunitFile,
		"/tmp/shared/failures.list",
		fmt.Sprintf("/tmp/failures-%s-suite.txt", p.ID()),
	); err != nil {
		return fmt.Errorf("error parsing JUnit: %w", err)
	}

	if err := p.SaveToConfigMap(fmt.Sprintf("/tmp/failures-%s-suite.txt", p.ID())); err != nil {
		return fmt.Errorf("error saving to ConfigMap: %w", err)
	}

	// Save XML to worker result control file
	res, err := os.OpenFile(ResultsDoneFile, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0644)
	if err != nil {
		return fmt.Errorf("error opening file %s: %w", ResultsDoneFile, err)
	}
	defer res.Close()

	log.Infof("Notify worker for done: writing JUnit file %s to result file %s", resultJunitFile, ResultsDoneFile)
	_, err = res.WriteString(resultJunitFile)
	if err != nil {
		return fmt.Errorf("error writing to file: %w", err)
	}

	return nil
}

// ParseAndExtractFailuresFromJunit reads the JUnit XML file, parse it and save the failures to a file.
func (p *Plugin) ParseAndExtractFailuresFromJunit(suiteList, xmlFile, outFailuresXML, outFailuresSuite string) error {
	xmlData, err := os.ReadFile(xmlFile)
	if err != nil {
		return fmt.Errorf("error reading XML file: %w", err)
	}

	// Parse the XML data (JUnit created by openshift-tests)
	type Skipped struct {
		Message string `xml:"message,attr"`
	}
	type TestCase struct {
		Name      string  `xml:"name,attr"`
		Time      string  `xml:"time,attr"`
		Failure   string  `xml:"failure"`
		Skipped   Skipped `xml:"skipped"`
		SystemOut string  `xml:"system-out"`
	}
	type Property struct {
		Name  string `xml:"name,attr"`
		Value string `xml:"value,attr"`
	}
	type TestSuite struct {
		XMLName   xml.Name   `xml:"testsuite"`
		Name      string     `xml:"name,attr"`
		Tests     int        `xml:"tests,attr"`
		Skipped   int        `xml:"skipped,attr"`
		Failures  int        `xml:"failures,attr"`
		Time      string     `xml:"time,attr"`
		Property  Property   `xml:"property"`
		TestCases []TestCase `xml:"testcase"`
	}

	var ts TestSuite
	if err := xml.Unmarshal(xmlData, &ts); err != nil {
		return fmt.Errorf("error parsing XML data: %w", err)
	}

	// Iterate over the test cases
	failures := []string{}
	total := 0
	skips := 0
	fails := 0
	for _, testcase := range ts.TestCases {
		// Access the properties of each test case
		total += 1
		if len(testcase.Skipped.Message) > 0 {
			skips += 1
		}
		if len(testcase.Failure) > 0 {
			fails += 1
			failures = append(failures, fmt.Sprintf("\"%s\"", testcase.Name))
			continue
		}
	}
	pass := total - (skips + fails)

	// Save failures to a file.
	if err := os.WriteFile(outFailuresXML, []byte(strings.Join(failures, "\n")), 0644); err != nil {
		return fmt.Errorf("error saving failures to file: %w", err)
	}

	if err := ParseSuiteFailures(outFailuresXML, suiteList, outFailuresSuite); err != nil {
		return fmt.Errorf("error saving failures to file: %w", err)
	}

	// Summary. TODO/Q: should we print only in debug mode?
	fmt.Println("Parsed counters: total:", total, "skips:", skips, "fails:", fails, "pass:", pass)
	fmt.Printf("Suite info: name=%s tests=%d skipped=%d failures=%d time=%v\n", ts.Name, ts.Tests, ts.Skipped, ts.Failures, ts.Time)
	fmt.Printf("Suite runner properties: %s=%s\n", ts.Property.Name, ts.Property.Value)
	return nil
}

// SaveToConfigMap saves the failures tests to a ConfigMap.
func (p *Plugin) SaveToConfigMap(outFailuresSuite string) error {

	// Read the failureSuiteFile from file
	failureSuiteData, err := os.ReadFile(outFailuresSuite)
	if err != nil {
		return fmt.Errorf("error reading failure suite file: %w", err)
	}

	// Create a ConfigMap object
	configMap := &kcorev1.ConfigMap{
		ObjectMeta: kmmetav1.ObjectMeta{
			Name:      fmt.Sprintf("plugin-failures-%s", p.ID()),
			Namespace: EnvNamespace,
		},
		Data: map[string]string{
			"replay.list": string(failureSuiteData),
		},
	}

	// Create the ConfigMap using the Kubernetes client
	if p.clientKube == nil {
		return fmt.Errorf("kubernetes client not initialized")
	}
	_, err = p.clientKube.CoreV1().ConfigMaps(EnvNamespace).Create(context.TODO(), configMap, kmmetav1.CreateOptions{})
	if err != nil {
		return fmt.Errorf("error creating ConfigMap: %w", err)
	}

	log.Info("JUnit processor done!")
	return nil
}
