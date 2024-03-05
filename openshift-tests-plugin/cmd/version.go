package cmd

import (
	"fmt"

	v "github.com/redhat-openshift-ecosystem/provider-certification-plugins/openshift-tests-plugin/pkg/version"
	"github.com/spf13/cobra"
)

func NewCmdVersion() *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Print provider validation tool version",
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Printf("%s", v.GetFullVersion())
		},
	}
}
