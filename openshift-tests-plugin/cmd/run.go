package cmd

import (
	"fmt"
	"os"

	"github.com/redhat-openshift-ecosystem/provider-certification-plugins/openshift-tests-plugin/pkg/plugin"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
)

// TODO parser failures to filter only included in the suite to replay
// Input:
// - suite list
// - failures list
// Output: stadout or file: intersection of both lists
// Optional: upload to configmap

type OptionsRun struct {
	Name string
}

func NewCmdRun() *cobra.Command {

	opts := OptionsRun{}

	cmd := &cobra.Command{
		Use:   "run",
		Short: "Run the default flow for openshift-tests plugin",
		Long:  ``,
		Run: func(cmd *cobra.Command, args []string) {

			fmt.Println(">>> starting")
			StartRun(&opts)

		},
	}

	cmd.Flags().StringVar(&opts.Name, "name", "", "Plugin name")

	return cmd
}

// StartRun is the main workflow for a regular plugin execution.
// Plugin flow:
//
// Load Config from var
// Initialize dependencies: FIFO, result dir, etc
// - create fifo
// - create work/result dirs
// - wait for sonobuoy worker/progress API (sidecar)
// - loging to OpenShift cluster
// - (when upgrade) check if MCP opct exists
// - Load suite list (from sidecar)
// Run report progress (background)
// Run plugin dependecy waiter (foreground)
// Run executor for plugin
// - Check mode: dev/prod
// - set openshift-tests params, including limiting the monitor tests
// - when dev: get random N tests and run
// - when prod: run suite
// - create run script
// - wait for run-done
// Save:
// - gather XML results
// - save failures to replay
func StartRun(opt *OptionsRun) {

	if opt.Name == "" {
		log.Error("--name must be specified")
		os.Exit(1)
	}

	pl, err := plugin.NewPlugin(opt.Name)
	if err != nil {
		log.Errorf("unable to initialize plugin name: %w", err)
		os.Exit(1)
	}
	defer pl.Done()

	// err = pl.Initialize()
	// if err != nil {
	// 	log.Errorf("unable to initialize plugin name: %w", err)
	// 	os.Exit(1)
	// }

	// go pl.RunReportProgress()

	// err = pl.RunDependencyWaiter()
	// if err != nil {
	// 	log.Errorf("unable to initialize plugin name: %w", err)
	// 	// TODO create JUnit err
	// 	os.Exit(1)
	// }

	err = pl.Run()
	if err != nil {
		log.Errorf("unable to initialize plugin name: %w", err)
		// TODO create JUnit err
		os.Exit(1)
	}

	// err = pl.Save()
	// if err != nil {
	// 	log.Errorf("unable to initialize plugin name: %w", err)
	// 	// TODO create JUnit err
	// 	os.Exit(1)
	// }

	// return pl.Summary()
}
