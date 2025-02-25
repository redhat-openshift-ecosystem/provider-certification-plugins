package plugin

import (
	"context"
	"fmt"

	log "github.com/sirupsen/logrus"
	sbclient "github.com/vmware-tanzu/sonobuoy/pkg/client"
	sbaggregation "github.com/vmware-tanzu/sonobuoy/pkg/plugin/aggregation"
	kcorev1 "k8s.io/api/core/v1"
	kmmetav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	klabels "k8s.io/apimachinery/pkg/labels"
	kubernetes "k8s.io/client-go/kubernetes"
)

// BlockerPluginsInput is the input for the BlockerPlugins.
type BlockerPluginsInput struct {
	KubeClient        kubernetes.Interface
	SonobClient       sbclient.Interface
	PluginBlockerName string
}

// GetPluginsBlocker get sonobuoy plugins (current and blocker) statusses.
func (p *Plugin) GetPluginsBlocker() (*sbaggregation.PluginStatus, *sbaggregation.PluginStatus, error) {
	if p.clientSonobuoy == nil {
		return nil, nil, fmt.Errorf("sonobuoy client not initialized")
	}
	sstatus, pod, err := sbaggregation.GetStatus(p.clientKube, p.Namespace)
	if err != nil {
		return nil, nil, fmt.Errorf("unable to get sonobuoy information: %v (pod info: %v)", err, pod)
	}
	pluginBlockerName := ""
	if len(p.BlockerPlugins) > 0 {
		pluginBlockerName = p.BlockerPlugins[0].name
	}
	var pStatusBlocker sbaggregation.PluginStatus
	var pStatusCurrent sbaggregation.PluginStatus
	for _, ps := range sstatus.Plugins {
		if ps.Plugin == p.PluginFullNameByName(p.name) {
			pStatusCurrent = ps
		}
		if ps.Plugin == p.PluginFullNameByName(pluginBlockerName) {
			pStatusBlocker = ps
		}
	}
	return &pStatusCurrent, &pStatusBlocker, nil
}

// GetPluginPod get the plugin pod spec.
func GetPluginPod(kclient kubernetes.Interface, namespace string, pluginPodName string) (*kcorev1.Pod, error) {
	labelSelector := kmmetav1.LabelSelector{MatchLabels: map[string]string{"component": "sonobuoy", "sonobuoy-plugin": pluginPodName}}
	log.Infof("Getting pod with labels: %v\n", labelSelector)
	listOptions := kmmetav1.ListOptions{
		LabelSelector: klabels.Set(labelSelector.MatchLabels).String(),
	}

	podList, err := kclient.CoreV1().Pods(namespace).List(context.TODO(), listOptions)
	if err != nil {
		return nil, fmt.Errorf("unable to list pods with label %q", labelSelector)
	}

	switch {
	case len(podList.Items) == 0:
		log.Warningf("no pods found with label %q in namespace %s", labelSelector, namespace)
		return nil, fmt.Errorf("no pods found with label %q in namespace %s", labelSelector, namespace)

	case len(podList.Items) > 1:
		log.Warningf("Found more than one pod with label %q. Using pod with name %q", labelSelector, podList.Items[0].GetName())
		return &podList.Items[0], nil
	default:
		return &podList.Items[0], nil
	}
}

// GetPodStatusString get the pod status string.
func GetPodStatusString(pod *kcorev1.Pod) string {
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
	return string(pod.Status.Phase)
}
