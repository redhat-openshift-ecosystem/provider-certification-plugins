package exec

import (
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/redhat-openshift-ecosystem/provider-certification-tool/pkg/client"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
)

// plugin1 -> this.plugin -> plugin2
//
// wait-updater ensure the Plugin API (this.plugin) is updated with
// the current state watching the blocker plugin ('plugin2')
// state (head/following plugin).

type OptionsWaitUpdate struct {
	InitTotal     int64
	Namespace     string
	PluginName    string
	BlockerPlugin string
	DoneControl   string
}

func NewCmdWaitUpdater() *cobra.Command {

	opts := OptionsWaitUpdate{}

	cmd := &cobra.Command{
		Use:   "wait-updater",
		Short: "Ensure the current plugin progress state based in the blocker",
		Long:  ``,
		Run: func(cmd *cobra.Command, args []string) {

			fmt.Println(">>> starting")
			StartWaitUpdater(&opts)

		},
	}

	cmd.Flags().Int64Var(&opts.InitTotal, "init-total", 0, "Initial value for total")
	cmd.Flags().StringVar(&opts.Namespace, "namespace", "", "Name of current namespace")
	cmd.Flags().StringVar(&opts.PluginName, "plugin", "", "Name of current plugin")
	cmd.Flags().StringVar(&opts.BlockerPlugin, "blocker", "", "Blocker Plugin")
	cmd.Flags().StringVar(&opts.DoneControl, "done", "", "Define the exit control file. Example: /tmp/done")

	return cmd
}

func watchForFile(filePath string) error {
	initialStat, err := os.Stat(filePath)
	if err != nil {
		return err
	}

	for {
		stat, err := os.Stat(filePath)
		if err != nil {
			return err
		}

		if stat.Size() != initialStat.Size() || stat.ModTime() != initialStat.ModTime() {
			break
		}

		time.Sleep(1 * time.Second)
	}

	return nil
}

func startWatchForFile(doneChan chan bool, filePath string) {
	defer func() {
		doneChan <- true
	}()

	err := watchForFile(filePath)
	if err != nil {
		log.Debugf("Done file watch error: %s", err)
	}

	log.Println("Done file has been created")
}

// Check the API and watch for done file.
func StartWaitUpdater(opts *OptionsWaitUpdate) error {

	plugin := PluginConfig{
		Namespace: opts.Namespace,
		Name:      opts.PluginName,
		BlockerPlugins: []*PluginConfig{
			&PluginConfig{Name: opts.BlockerPlugin},
		},
	}

	// Client setup
	kcli, sbcli, err := client.CreateClients()
	if err != nil {
		log.Error(err)
		// TODO send update message
		return nil
	}

	// watch done
	updaterControl := make(chan bool)
	doneControl := false
	doneChan := make(chan bool)
	go startWatchForFile(doneChan, opts.DoneControl)

	// TODO add for each blocker plugin
	// TODO be safe!
	pluginBlocker := plugin.BlockerPlugins[0].Name

	currentCheckCount := 0
	limitCheckCount := 1080
	lastCheckCount := int64(0)
	sleepIntervalSeconds := 10 * time.Second

	go func() {
		for {
			if doneControl {
				updaterControl <- true
				break
			}

			// scrap SB API
			pStatusBlocker, _, err := getPluginsBlocker(&BlockerPluginsInput{
				SonobClient:       sbcli,
				PluginConfig:      &plugin,
				PluginBlockerName: pluginBlocker,
			})
			if err != nil {
				log.Errorf("Error getting Sonobuoy Aggregator API info")
				time.Sleep(1 * time.Second)
				break
			}

			pod, _ := getPluginPod(kcli, plugin.Namespace, pluginBlocker)
			podPhase := getPodStatusString(pod)

			// parse fields to status api
			// check .status: is completed? is failed? then return success
			fmt.Printf("blockerStatus name(%s) pluginStatus/podStatus: %s/%s\n", pStatusBlocker.Plugin, pStatusBlocker.Status, podPhase)
			if pStatusBlocker.Status == "complete" || pStatusBlocker.Status == "failed" {
				log.Printf("Plugin[%s] with status[%s] is in unblocker condition!", pluginBlocker, pStatusBlocker.Status)
				break
			}

			// parse blocker counters
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

			pluginMessageState := "TBD"
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

			// parse blocker msg
			// mount the plugin message and update API
			msg := fmt.Sprintf("status=%s=%s=(0/%d/0)=[%d/%d]", pluginMessageState, pluginBlocker, remaining, currentCheckCount, limitCheckCount)
			progressReportSendUpdate(&ProgressReport{TotalCount: opts.InitTotal}, msg)

			if pStatusBlocker.Progress != nil && pStatusBlocker.Progress.Completed >= lastCheckCount {
				lastCheckCount = blockerProgressCount
				currentCheckCount = 0
				time.Sleep(sleepIntervalSeconds)
				continue
			}

			// ignore timeout when blocker is progressing
			if pStatusBlocker.Progress != nil &&
				strings.HasPrefix(pStatusBlocker.Progress.Message, "status=blocked-by") {
				currentCheckCount = 0
				time.Sleep(sleepIntervalSeconds)
				continue
			}

			// ignore timeout when blocker is also blocked
			if pStatusBlocker.Progress != nil &&
				strings.HasPrefix(pStatusBlocker.Progress.Message, "status=blocked-by") &&
				strings.HasPrefix(pluginMessageState, "status=blocked-by") {
				currentCheckCount = 0
				time.Sleep(sleepIntervalSeconds)
				continue
			}

			// ignore timeout when blocker is the next in the queue,
			// and current plugin state is blocked
			// increment timeout counter and wait
			lastCheckCount = blockerProgressCount
			currentCheckCount += 1
			if currentCheckCount >= limitCheckCount {
				log.Errorf("Timeout waiting condition 'complete' for plugin[%s].", plugin.Name)
				// TODO send update message
				os.Exit(1)
			}
			time.Sleep(sleepIntervalSeconds)
		}
	}()

	log.Infof("Waiting for Done notify.")
	<-doneChan
	doneControl = true
	log.Infof("Flow unlocked.")
	return nil
}
