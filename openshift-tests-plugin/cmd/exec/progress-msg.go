package exec

import (
	"fmt"

	"github.com/redhat-openshift-ecosystem/provider-certification-plugins/openshift-tests-plugin/pkg/plugin"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"k8s.io/utils/ptr"
)

type OptionProgressMessage struct {
	Message string
	Total   int64
	Current int64
}

func NewCmdProgressMessage() *cobra.Command {

	opts := OptionProgressMessage{}

	cmd := &cobra.Command{
		Use:   "progress-msg",
		Short: "Send standalone progress message to worker API.",
		Long: `Create custom messages and send it to the aggregator through worker API.
		This approach is commonly used to send plugin progress in standalone steps (shell scripts)
		running in opct/sonobuoy environment.
		Example:
		$ openshift-tests-plugin progress-msg --message "Running test step XPTO" --total 100 --current 10`,
		Run: func(cmd *cobra.Command, args []string) {
			if err := StartProgressMessage(&opts); err != nil {
				log.Fatalf("command finished with errors: %v", err)
			}
		},
	}

	cmd.Flags().StringVar(&opts.Message, "message", "", "Message to send to aggregator.")
	cmd.Flags().Int64Var(&opts.Total, "total", 0, "Total number of items to process")
	cmd.Flags().Int64Var(&opts.Current, "current", 0, "Current number of items processed")

	return cmd
}

func StartProgressMessage(opts *OptionProgressMessage) error {

	if opts.Message == "" {
		return fmt.Errorf("invalid empty flag --message")
	}
	progress := plugin.NewPluginProgress()
	if progress == nil {
		return fmt.Errorf("failed to create progress report service")
	}
	progress.Set(&plugin.PluginProgress{
		ProgressMessage: ptr.To(opts.Message),
	})
	if opts.Total > 0 {
		progress.Set(&plugin.PluginProgress{
			TotalCount: ptr.To(opts.Total),
		})
	}
	if opts.Current > 0 {
		progress.Set(&plugin.PluginProgress{
			CompleteCount: ptr.To(opts.Current),
		})
	}
	progress.UpdateAndSend()
	return nil
}
