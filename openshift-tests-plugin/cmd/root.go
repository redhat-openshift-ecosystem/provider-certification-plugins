/*
	TODO:
	- Add a license header to this file

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

var pluginConfigFile string

var rootCmd = &cobra.Command{
	Use:   "openshift-tests-plugin",
	Short: "Sonobuoy-based plugin for openshift-tests utility.",
	Long: `A longer description that spans multiple lines and likely contains
examples and usage of using your application. For example:

Cobra is a CLI library for Go that empowers applications.
This application is a tool to generate the needed files
to quickly create a Cobra application.`,
}

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

func initConfig() {
	viper.AutomaticEnv() // read in environment variables that match
}

func init() {
	cobra.OnInitialize(initConfig)

	rootCmd.PersistentFlags().StringVar(&pluginConfigFile, "config", "", "config file (default is $PWD/.openshift-tests-plugin.yaml)")
	rootCmd.PersistentFlags().String("kubeconfig", "", "kubeconfig for target OpenShift cluster")
	initBindFlag("kubeconfig")

	rootCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")

	rootCmd.AddCommand(exec.NewCmdExec())
	rootCmd.AddCommand(NewCmdRun())
	rootCmd.AddCommand(NewCmdVersion())
}
