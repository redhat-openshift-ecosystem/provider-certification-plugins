package cmd

import (
	"fmt"
	"os"
	"time"

	"github.com/redhat-openshift-ecosystem/provider-certification-plugins/openshift-tests-plugin/pkg/plugin"
	v "github.com/redhat-openshift-ecosystem/provider-certification-plugins/openshift-tests-plugin/pkg/version"
	log "github.com/sirupsen/logrus"

	"github.com/spf13/cobra"
)

type OptionsRun struct {
	Name string
	ID   string
}

func init() {

	log.SetLevel(log.DebugLevel)
	log.SetFormatter(&log.TextFormatter{
		FullTimestamp:   true,
		TimestampFormat: "2006-01-02 15:04:05",
	})
	log.SetOutput(os.Stdout)

}

func NewCmdRun() *cobra.Command {
	opts := OptionsRun{}
	cmd := &cobra.Command{
		Use:   "run",
		Short: "Execute the default workflow for openshift-tests plugin",
		Long:  ``,
		Run: func(cmd *cobra.Command, args []string) {
			if err := StartRun(&opts); err != nil {
				// TODO create JUnit err
				log.Errorf("run command finished with errors: %v", err)
				os.Exit(1)
			}
			log.Info("run command finished successfully")
			os.Exit(0)
		},
	}

	cmd.Flags().StringVar(&opts.Name, "name", "", "Plugin name")
	cmd.Flags().StringVar(&opts.ID, "id", "", "Plugin ID")

	return cmd
}

func StartRun(opt *OptionsRun) error {
	pluginName, err := opt.GetPluginName()
	if err != nil {
		return fmt.Errorf("plugin name not found: %w", err)
	}

	log.Infof("Starting plugin %s (%s)", pluginName, v.GetFullVersion())

	pl, err := plugin.NewPlugin(pluginName)
	if err != nil {
		return fmt.Errorf("unable to create plugin %s: %w", pluginName, err)
	}
	defer pl.Done()

	if err = pl.Initialize(); err != nil {
		return fmt.Errorf("unable to initialize plugin %s: %w", pluginName, err)
	}

	go pl.WatchForDone()

	if err = pl.RunDependencyWaiter(); err != nil {
		return fmt.Errorf("error running dependency waiter: %w", err)
	}
	go pl.RunReportProgress()
	go pl.RunReportProgressUpgrade()

	if err = pl.Run(); err != nil {
		return fmt.Errorf("error running plugin: %w", err)
	}

	pl.Summary()
	log.Info("Processing JUnit")
	// TODO gather XML results
	// TODO save failures to replay
	if err = pl.ProcessJUnit(); err != nil {
		// log.Errorf("error processing JUnits: %v", err)
		return fmt.Errorf("error processing JUnits: %w", err)
	}

	log.Infof("Waiting for done controller in the main flow...")
	for {
		if pl.DoneControl {
			log.Infof("Done state detected, unblocking main flow [%v]", pl.DoneControl)
			break
		}
		log.Infof("Waiting for done state [%v]", pl.DoneControl)
		time.Sleep(1 * time.Second)
	}
	log.Info("Done!")

	return nil
}

func (opt *OptionsRun) ValidatePluginNameOrID() error {
	switch opt.Name {
	case plugin.PluginName05:
	case plugin.PluginName10:
	case plugin.PluginName20:
	case plugin.PluginName80:
	case plugin.PluginName99:
	default:
		return fmt.Errorf("invalid plugin name: %s", opt.Name)
	}
	return nil
}

func (opt *OptionsRun) GetPluginNameByID(id string) (string, error) {
	switch id {
	case plugin.PluginId05:
		return plugin.PluginName05, nil
	case plugin.PluginId10:
		return plugin.PluginName10, nil
	case plugin.PluginId20:
		return plugin.PluginName20, nil
	case plugin.PluginId80:
		return plugin.PluginName80, nil
	case plugin.PluginId99:
		return plugin.PluginName99, nil
	}
	return "", fmt.Errorf("invalid plugin ID: %s", id)
}

// GetPluginName returns the name of the plugin based on the provided options.
// If the `Name` field is not empty, it validates the plugin name and returns it.
// If the `ID` field is not empty, it retrieves the plugin name by ID and returns it.
// If neither `Name` nor `ID` is provided, it returns an error indicating that the plugin name or ID must be specified.
func (opt *OptionsRun) GetPluginName() (string, error) {
	if opt.Name != "" {
		if err := opt.ValidatePluginNameOrID(); err != nil {
			return "", nil
		}
		return opt.Name, nil
	}
	if opt.ID != "" {
		name, err := opt.GetPluginNameByID(opt.ID)
		if err != nil {
			return "", err
		}
		return name, nil
	}
	return "", fmt.Errorf("plugin name or ID must be specified")
}
