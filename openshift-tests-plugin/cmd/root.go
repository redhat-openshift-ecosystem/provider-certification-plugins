/*
Copyright © 2024 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"os"

	"github.com/redhat-openshift-ecosystem/provider-certification-plugins/openshift-tests-plugin/cmd/exec"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

type PluginConfig struct {

	// Dependencies is a list of plugin names to wait for finish before start the regular flow.
	Dependencies []string
}

func NewPluginConfigFromFile(file string) *PluginConfig {

	return &PluginConfig{}
}

var pluginConfigFile string

// rootCmd represents the base command when called without any subcommands
var rootCmd = &cobra.Command{
	Use:   "openshift-tests-plugin",
	Short: "A brief description of your application",
	Long: `A longer description that spans multiple lines and likely contains
examples and usage of using your application. For example:

Cobra is a CLI library for Go that empowers applications.
This application is a tool to generate the needed files
to quickly create a Cobra application.`,
	// Uncomment the following line if your bare application
	// has an action associated with it:
	// Run: func(cmd *cobra.Command, args []string) { },
}

// Execute adds all child commands to the root command and sets flags appropriately.
// This is called by main.main(). It only needs to happen once to the rootCmd.
func Execute() {
	err := rootCmd.Execute()
	if err != nil {
		os.Exit(1)
	}
}

func initBindFlag(flag string) {
	err := viper.BindPFlag(flag, rootCmd.PersistentFlags().Lookup(flag))
	if err != nil {
		log.Warnf("Unable to bind flag %s\n", flag)
	}
}

// initConfig reads in config file and ENV variables if set.
func initConfig() {
	viper.AutomaticEnv() // read in environment variables that match
}

func init() {

	// Here you will define your flags and configuration settings.
	// Cobra supports persistent flags, which, if defined here,
	// will be global for your application.
	cobra.OnInitialize(initConfig)

	rootCmd.PersistentFlags().StringVar(&pluginConfigFile, "config", "", "config file (default is $PWD/.openshift-tests-plugin.yaml)")
	rootCmd.PersistentFlags().String("kubeconfig", "", "kubeconfig for target OpenShift cluster")
	initBindFlag("kubeconfig")

	// Cobra also supports local flags, which will only run
	// when this action is called directly.
	rootCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")

	// rootCmd.AddCommand(status.NewCmdStatus())
	rootCmd.AddCommand(exec.NewCmdExec())

}
