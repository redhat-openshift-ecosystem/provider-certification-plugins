package exec

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/redhat-openshift-ecosystem/provider-certification-tool/pkg/client"
	"github.com/redhat-openshift-ecosystem/provider-certification-tool/pkg/status"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	sbclient "github.com/vmware-tanzu/sonobuoy/pkg/client"
	sbaggregation "github.com/vmware-tanzu/sonobuoy/pkg/plugin/aggregation"
	kcorev1 "k8s.io/api/core/v1"
	kmmetav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	klabels "k8s.io/apimachinery/pkg/labels"
	kruntime "k8s.io/apimachinery/pkg/runtime"
	kwatch "k8s.io/apimachinery/pkg/watch"
	kubernetes "k8s.io/client-go/kubernetes"
	kcache "k8s.io/client-go/tools/cache"
	kwatchtools "k8s.io/client-go/tools/watch"
)

const (
	DefaultStatusIntervalSeconds = 10
	StatusRetryLimit             = 10
)

type StatusOptions = status.StatusOptions

// StatusInput is the interface to input options when
// creating status object.
type StatusInput struct {
	Watch           bool
	IntervalSeconds int
}

type OptionsWaitForPlugin struct {
	PluginName    string
	BlockerPlugin string
}

func NewCmdWaitForPlugin() *cobra.Command {

	opts := OptionsWaitForPlugin{}

	cmd := &cobra.Command{
		Use:   "wait-for-plugin",
		Short: "Show the current status of the validation tool",
		Long:  ``,
		Run: func(cmd *cobra.Command, args []string) {

			fmt.Println(">>> starting")
			StartWaitForPlugin(&opts)

		},
	}

	cmd.Flags().StringVar(&opts.PluginName, "plugin", "", "Name of current plugin")
	cmd.Flags().StringVar(&opts.BlockerPlugin, "blocker", "", "Blocker Plugin")

	return cmd
}

type PluginConfig struct {
	Name           string
	BlockerPlugins []*PluginConfig
}

// type ContainerStatus struct {
// 	Name         string
// 	Ready        bool
// 	Started      bool
// 	RestartCount int
// }
// type PodPluginStatus struct {
// 	Name                  string
// 	Phase                 string
// 	Initialized           string
// 	InitializedReason     string
// 	Ready                 string
// 	ReadyReason           string
// 	ContainersReady       string
// 	ContainersReadyReason string
// 	PodScheduled          string
// 	PodScheduledReason    string
// 	Containers            []*ContainerStatus
// }

func StartWaitForPlugin(opts *OptionsWaitForPlugin) error {

	plugin := PluginConfig{
		Name: opts.PluginName,
		BlockerPlugins: []*PluginConfig{
			&PluginConfig{Name: opts.PluginName},
		},
	}

	s := status.NewStatusOptions(false)
	// Client setup
	kcli, sbcli, err := client.CreateClients()
	if err != nil {
		log.Error(err)
		return nil
	}

	// Pre-checks and setup
	err = s.PreRunCheck(kcli)
	if err != nil {
		log.WithError(err).Error("error running pre-checks")
		// return err
	}

	// Wait for Sonobuoy to create
	// err = wait.WaitForRequiredResources(kcli)
	// if err != nil {
	// 	log.WithError(err).Error("error waiting for sonobuoy pods to become ready")
	// 	// return err
	// }

	// pod waiter conditions:
	// pod complete; OR
	// pod running

	// pod status collector:
	// pod conditions
	// containers status[]

	// Wait for blocker readyness
	for _, blockerPlugin := range plugin.BlockerPlugins {
		err = WaitForPodRunningOrComplete(kcli, blockerPlugin.Name)
		if err != nil {
			log.WithError(err).Error("error waiting for sonobuoy pods to become ready")
			// return err
		}
	}

	// TEMP start status report for plugin
	// Wait for blocker execution complete
	for _, blockerPlugin := range plugin.BlockerPlugins {
		err = WaitForPluginExecution(sbcli, kcli, plugin.Name, blockerPlugin.Name)
		if err != nil {
			log.WithError(err).Error("error waiting for sonobuoy pods to become ready")
			// return err
		}
	}

	return nil
}

func WaitForPluginExecution(sbcli sbclient.Interface, kclient kubernetes.Interface, plugin string, pluginBlocker string) error {

	// loop blocker check
	log.Println("Plugin %s waiting 'completed' condition for pod: %s", plugin, pluginBlocker)

	currentCheckCount := 0
	limitCheckCount := 1080
	lastCheckCount := int64(0)
	sleepIntervalSeconds := 10 * time.Second

	for {

		// get plugin API status
		sstatus, err := sbcli.GetStatus(&sbclient.StatusConfig{Namespace: "sonobuoy"})
		if err != nil {
			return err
		}
		var pStatusBlocker sbaggregation.PluginStatus
		var pStatusCurrent sbaggregation.PluginStatus
		for _, ps := range sstatus.Plugins {
			if ps.Plugin == plugin {
				pStatusCurrent = ps
			}
			if ps.Plugin == pluginBlocker {
				pStatusBlocker = ps
			}
		}
		fmt.Println(sstatus)
		pod, _ := getPluginPod(kclient, pluginBlocker)
		podPhase := getPodStatusString(pod)

		// parse fields to status api
		// check .status: is completed? is failed? then return success
		fmt.Printf("blockerStatus name(%s) pluginStatus/podStatus: %s/%s\n", pStatusBlocker.Plugin, pStatusBlocker.Status, podPhase)
		if pStatusBlocker.Status == "complete" || pStatusBlocker.Status == "failed" {
			log.Printf("Plugin[%s] with status[%s] is in unblocker condition!", pluginBlocker, pStatusBlocker.Status)
			break
		}

		// Condition 1) check freeze timeout, reset threshold if plugin progress the execution and wait
		// TODO ${count} -gt ${last_count}
		blockerProgressCount := int64(0)
		if pStatusBlocker.Progress != nil {
			blockerProgressCount = pStatusBlocker.Progress.Completed
		}
		if blockerProgressCount > lastCheckCount {
			lastCheckCount = blockerProgressCount
			currentCheckCount = 0
			time.Sleep(sleepIntervalSeconds)
			continue
		}

		// Condition 2) check blocker is also blocked. If blocker plugins is also blocked, reset freeze timeout and wait
		// TODO plugin has status=blocked-by
		if pStatusBlocker.Progress != nil &&
			strings.HasPrefix(pStatusBlocker.Progress.Message, "status=blocked-by") {
			currentCheckCount = 0
			time.Sleep(sleepIntervalSeconds)
			continue
		}
		if pStatusBlocker.Progress != nil &&
			strings.HasPrefix(pStatusBlocker.Progress.Message, "status=waiting-for") &&
			strings.HasPrefix(pStatusCurrent.Progress.Message, "status=blocked-by") {
			currentCheckCount = 0
			time.Sleep(sleepIntervalSeconds)
			continue
		}

		// check blocker is the next in the queue
		// increase timeout counter when blocker didn't progress
		lastCheckCount = blockerProgressCount
		currentCheckCount += 1

		// fail when blocker reaches the timeout w/o progressing status
		if currentCheckCount >= limitCheckCount {
			log.Error("timeout")
			return fmt.Errorf("timeout while waiting for plugin")
			// os.Exit(1)
		}

		// sleep until next check
		time.Sleep(sleepIntervalSeconds)
	}

	return nil
}

// WaitForPodRunningOrComplete will wait for the sonobuoy pod in the sonobuoy namespace to go into
// a Running/Ready state and then return nil.
func WaitForPodRunningOrComplete(kclient kubernetes.Interface, pluginName string) error {
	var obj kruntime.Object

	restClient := kclient.CoreV1().RESTClient()

	selector := fmt.Sprintf("component=sonobuoy,sonobuoy-plugin=%s", pluginName)
	lw := kcache.NewFilteredListWatchFromClient(restClient, "pods", "sonobuoy", func(options *kmmetav1.ListOptions) {
		options.LabelSelector = selector
	})

	// Wait for Sonobuoy Pods to become Ready
	fmt.Printf("WaitForPodRunningOrComplete() \n")
	latestPhase := "TBD"
	ctx, cancel := context.WithTimeout(context.TODO(), time.Minute*3)
	defer cancel()
	_, err := kwatchtools.UntilWithSync(ctx, lw, obj, nil, func(event kwatch.Event) (bool, error) {
		switch event.Type {
		case kwatch.Error:
			return false, fmt.Errorf("error waiting for sonobuoy to start: %w", event.Object.(error))
		case kwatch.Deleted:
			return false, errors.New("sonobuoy pod deleted while waiting to become ready")
		}

		pod, isPod := event.Object.(*kcorev1.Pod)
		if !isPod {
			return false, errors.New("type error watching for sononbuoy to start")
		}

		podStatus := getPodStatusString(pod)
		latestPhase = podStatus
		if podStatus == "Running" || podStatus == "Complete" {
			return true, nil
		}

		log.Debugf(" Waiting for plugin pod [%s] to be scheduled. Phase(%s)\n", pluginName, latestPhase)

		return false, nil
	})
	if err != nil {
		return err
	}

	log.Infof(" Plugin pod [%s] executed. Phase(%s)\n", pluginName, latestPhase)
	return nil
}

// func podIsReady(pod *kcorev1.Pod) bool {
// 	for _, cond := range pod.Status.Conditions {
// 		if cond.Type == kcorev1.PodReady && cond.Status == kcorev1.ConditionTrue {
// 			return true
// 		}
// 	}
// 	return false
// }

// func podIsCompleted(pod *kcorev1.Pod) bool {
// 	if pod == nil {
// 		return false
// 	}
// 	for _, cond := range pod.Status.Conditions {
// 		if cond.Type == kcorev1.PodReady &&
// 			cond.Status == "False" &&
// 			cond.Reason == "PodCompleted" {
// 			return true
// 		}
// 	}
// 	return false
// }

func getPluginPod(kclient kubernetes.Interface, pluginName string) (*kcorev1.Pod, error) {
	// selector := fmt.Sprintf("component=sonobuoy,sonobuoy-plugin=%s", pluginName)
	// pods := kclient.CoreV1().ListOptions().Pod()

	namespace := "sonobuoy"
	// ctx, cancel := context.WithTimeout(context.TODO(), time.Minute*3)
	// defer cancel()
	labelSelector := kmmetav1.LabelSelector{MatchLabels: map[string]string{"component": "sonobuoy", "sonobuoy-plugin": pluginName}}
	listOptions := kmmetav1.ListOptions{
		LabelSelector: klabels.Set(labelSelector.MatchLabels).String(),
	}
	// pods, _ := kclient.CoreV1().Pods("sonobuoy").List(ctx, listOptions)

	podList, err := kclient.CoreV1().Pods(namespace).List(context.TODO(), listOptions)
	if err != nil {
		return nil, fmt.Errorf("unable to list pods with label %q", labelSelector)
	}

	switch {
	case len(podList.Items) == 0:
		log.Warningf("no pods found with label %q in namespace %s", labelSelector, namespace)
		// return nil, NoPodWithLabelError()
		return nil, fmt.Errorf(fmt.Sprintf("no pods found with label %q in namespace %s", labelSelector, namespace))

	case len(podList.Items) > 1:
		log.Warningf("Found more than one pod with label %q. Using pod with name %q", labelSelector, podList.Items[0].GetName())
		return &podList.Items[0], nil
	default:
		return &podList.Items[0], nil
	}
	// return nil, nil
}

func getPodStatusString(pod *kcorev1.Pod) string {
	if pod == nil {
		return "TBD(pod)"
	}

	for _, cond := range pod.Status.Conditions {
		// Pod Running
		if cond.Type == kcorev1.PodReady &&
			cond.Status == kcorev1.ConditionTrue &&
			pod.Status.Phase == kcorev1.PodRunning {
			return "Running"
		}
		// Pod Completed
		if cond.Type == kcorev1.PodReady &&
			cond.Status == "False" &&
			cond.Reason == "PodCompleted" {
			return "Completed"
		}
		// Pod NotReady (Container)
		if cond.Type == kcorev1.PodReady &&
			cond.Status == "False" &&
			cond.Reason == "ContainersNotReady" {
			return "NotReady"
		}
	}
	// fmt.Println("Default phase")
	return string(pod.Status.Phase)
}
