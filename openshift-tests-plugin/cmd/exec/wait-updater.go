/*
OPCT plugin openshift-tests

This plugin ensures the step will run serially considering the dependency (blocker plugin).

plugin1 -> this.plugin -> plugin2

wait-updater ensure the Plugin API (this.plugin) is updated with
the current state watching the blocker plugin ('plugin2')
state (head/following plugin).
*/
package exec

import (
	"fmt"
	"os"

	"github.com/redhat-openshift-ecosystem/provider-certification-plugins/openshift-tests-plugin/pkg/plugin"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
)

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
		Short: "Ensure the plugin (--plugin) waits for the blocker plugin (--blocker) to finish.",
		Long:  `wait-updater ensure execution is blocked until the blocker plugin is finished.`,
		Run: func(cmd *cobra.Command, args []string) {
			if err := StartWaitUpdater(&opts); err != nil {
				log.Fatalf("command finished with errors: %v", err)
			}
			os.Exit(0)
		},
	}

	cmd.Flags().Int64Var(&opts.InitTotal, "init-total", 0, "Initial value for total")
	// cmd.Flags().StringVar(&opts.Namespace, "namespace", "", "Name of current namespace")
	cmd.Flags().StringVar(&opts.PluginName, "plugin", "", "Name of current plugin")
	cmd.Flags().StringVar(&opts.BlockerPlugin, "blocker", "", "Blocker Plugin")
	cmd.Flags().StringVar(&opts.DoneControl, "done", "", "Define the exit control file. Example: /tmp/done")

	return cmd
}

// Check the API and watch for done file.
func StartWaitUpdater(opts *OptionsWaitUpdate) error {
	pl, err := plugin.NewPlugin(opts.PluginName)
	if err != nil {
		return fmt.Errorf("unable to create plugin %s: %w", opts.PluginName, err)
	}
	defer pl.Done()

	if err = pl.Initialize(); err != nil {
		return fmt.Errorf("unable to initialize plugin %s: %w", opts.PluginName, err)
	}

	if err = pl.RunDependencyWaiter(); err != nil {
		return fmt.Errorf("error running dependency waiter: %w", err)
	}
	log.Infof("exec wait-updater completed!")
	return nil
}
