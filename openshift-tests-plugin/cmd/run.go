package cmd

import (
	"fmt"
	"os"
	"time"

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

			// fmt.Println(">>> starting")
			err := StartRun(&opts)
			if err != nil {
				// TODO create JUnit err
				log.Errorf("command finished with errors: %v", err)
				os.Exit(1)
			}
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
func StartRun(opt *OptionsRun) error {

	if opt.Name == "" {
		return fmt.Errorf("--name must be specified")
	}

	pl, err := plugin.NewPlugin(opt.Name)
	if err != nil {
		return fmt.Errorf("unable to initialize plugin name: %w", err)
	}
	defer pl.Done()

	go pl.WatchForDone()

	err = pl.Initialize()
	if err != nil {
		return fmt.Errorf("unable to initialize plugin name: %w", err)
	}

	go pl.RunReportProgress()

	err = pl.RunDependencyWaiter()
	if err != nil {
		return fmt.Errorf("unable to initialize plugin name: %w", err)

	}

	err = pl.Run()
	if err != nil {
		return fmt.Errorf("unable to initialize plugin name: %w", err)
	}

	// err = pl.Save()
	// if err != nil {
	// 	log.Errorf("unable to initialize plugin name: %w", err)
	// 	// TODO create JUnit err
	// 	os.Exit(1)
	// }
	pl.Summary()

	log.Println("Waiting for done controller in the main flow...")
	for {
		if pl.DoneControl {
			log.Printf("\n OK %v\n", pl.DoneControl)
			break
		}
		log.Printf("\nWaiting %v\n", pl.DoneControl)
		time.Sleep(1 * time.Second)
	}
	return nil
}
