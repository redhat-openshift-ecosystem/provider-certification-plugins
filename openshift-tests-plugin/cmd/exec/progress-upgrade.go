package exec

import (
	"context"
	"fmt"
	"os"
	"time"

	occlient "github.com/openshift/client-go/config/clientset/versioned"
	"github.com/redhat-openshift-ecosystem/provider-certification-tool/pkg/client"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	kmmetav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/utils/ptr"
)

// TODO Progress Upgrade

type OptionProgressUpgrade struct {
	InputTotal  int64
	DoneControl string
}

func NewCmdProgressUpgrade() *cobra.Command {

	opts := OptionProgressUpgrade{}

	cmd := &cobra.Command{
		Use:   "progress-upgrade",
		Short: "Report progress for upgrade plugin",
		Long:  ``,
		Run: func(cmd *cobra.Command, args []string) {
			StartProgressUpgrade(&opts)
		},
	}

	cmd.Flags().Int64Var(&opts.InputTotal, "input-total", 0, "Total counter of expected tests to run. Default: count(${SHARED_DIR}/suite.list)")
	cmd.Flags().StringVar(&opts.DoneControl, "done", "", "Define the exit control file. Example: /tmp/done")

	return cmd
}

func runUpgradeMonitor(oc *occlient.Clientset, doneChan chan bool, doneController *bool) error {
	for {
		if *doneController {
			go func() { doneChan <- true }()
			break
		}
		cv, err := oc.ConfigV1().ClusterVersions().Get(context.TODO(), "version", kmmetav1.GetOptions{})
		if err != nil {
			log.Error("Error getting cluster version")
			time.Sleep(1 * time.Second)
			continue
		}
		progressingStatus := "False"
		progressingMessage := ""
		for _, cond := range cv.Status.Conditions {
			if cond.Type == "Progressing" {
				progressingStatus = string(cond.Status)
			}
			if cond.Message != "" {
				progressingMessage = string(cond.Message)
			}
		}

		msgProgress := fmt.Sprintf("upgrade-progressing-%s", progressingStatus)
		if progressingStatus == "True" {
			msgProgress = progressingMessage
		} else {
			msgProgress = fmt.Sprintf("%s=%s", cv.Status.Desired.Version, msgProgress)
		}

		msgProgress = fmt.Sprintf("status=%s", msgProgress)

		progressReportSendUpdate(&ProgressReport{}, msgProgress)
		fmt.Println("Waiting progress upgrade")
		time.Sleep(5 * time.Second)
	}

	return nil
}

func StartProgressUpgrade(opts *OptionProgressUpgrade) error {

	watcherChan := make(chan bool)
	doneControl := ptr.To(false)
	doneChan := make(chan bool)
	go startWatchForFile(doneChan, opts.DoneControl, doneControl)

	if os.Getenv("RUN_MODE") == os.Getenv("PLUGIN_RUN_MODE_UPGRADE") {
		// Get ConfigV1 client for Cluster Operators
		restConfig, err := client.CreateRestConfig()
		if err != nil {
			return err
		}
		oc, err := occlient.NewForConfig(restConfig)
		if err != nil {
			return err
		}
		go runUpgradeMonitor(oc, watcherChan, doneControl)
		log.Infof("UPGRADE: Waiting for Done notify.")
		<-watcherChan
	}

	log.Infof("UPGRADE: Flow done.")
	return nil
}
