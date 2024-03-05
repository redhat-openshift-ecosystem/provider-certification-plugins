package plugin

import (
	"fmt"
	"os"

	"github.com/spf13/viper"
	sbclient "github.com/vmware-tanzu/sonobuoy/pkg/client"
	sbdynamic "github.com/vmware-tanzu/sonobuoy/pkg/dynamic"
	"k8s.io/client-go/kubernetes"
	krest "k8s.io/client-go/rest"
	kclient "k8s.io/client-go/tools/clientcmd"
)

// CreateKubeRestConfig creates a kubernetes rest config from the kubeconfig file.
func CreateKubeRestConfig() (*krest.Config, error) {
	kubeconfig := os.Getenv("KUBECONFIG")

	if len(kubeconfig) == 0 {
		kubeconfig = viper.GetString("kubeconfig")
		if kubeconfig == "" {
			return nil, fmt.Errorf("--kubeconfig or KUBECONFIG environment variable must be set")
		}

		// Check kubeconfig exists
		if _, err := os.Stat(kubeconfig); err != nil {
			return nil, fmt.Errorf("kubeconfig %q does not exists: %v", kubeconfig, err)
		}
	}

	clientConfig, err := kclient.BuildConfigFromFlags("", kubeconfig)
	return clientConfig, err
}

// CreateClients creates kubernetes and sonobuoy client instances
func CreateClients() (kubernetes.Interface, sbclient.Interface, error) {
	clientConfig, err := CreateKubeRestConfig()
	if err != nil {
		return nil, nil, fmt.Errorf("error creating kube client config: %v", err)
	}

	clientset, err := kubernetes.NewForConfig(clientConfig)
	if err != nil {
		return nil, nil, fmt.Errorf("error creating kube client: %v", err)
	}

	skc, err := sbdynamic.NewAPIHelperFromRESTConfig(clientConfig)
	if err != nil {
		return nil, nil, fmt.Errorf("error creating sonobuoy rest helper: %v", err)
	}

	sonobuoyClient, err := sbclient.NewSonobuoyClient(clientConfig, skc)
	if err != nil {
		return nil, nil, fmt.Errorf("error creating sonobuoy client: %v", err)
	}

	return clientset, sonobuoyClient, nil
}
