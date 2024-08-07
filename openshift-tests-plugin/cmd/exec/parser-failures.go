package exec

import (
	"os"

	"github.com/redhat-openshift-ecosystem/provider-certification-plugins/openshift-tests-plugin/pkg/plugin"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
)

type OptionsParserFailures struct {
	SuiteList    string
	FailuresList string
	OutputFile   string
}

func NewCmdParserFailres() *cobra.Command {
	opts := OptionsParserFailures{}

	cmd := &cobra.Command{
		Use:   "parser-failures-suite",
		Short: "Get the intersection tests from the suite list and test failures.",
		Long:  `parser-failures-suite receives a list of tests available in the suite and a list of failures, and returns the intersection of both lists.`,
		Run: func(cmd *cobra.Command, args []string) {
			StartParseSuiteFailures(&opts)
		},
	}

	cmd.Flags().StringVar(&opts.SuiteList, "suite", "", "Input list of e2e tests available in the suite")
	cmd.Flags().StringVar(&opts.FailuresList, "failures", "", "Input list of test failures")
	cmd.Flags().StringVar(&opts.OutputFile, "output", "", "Output file path to stadout the intersection list of tests")

	return cmd
}

func StartParseSuiteFailures(opt *OptionsParserFailures) {
	if opt.SuiteList == "" || opt.FailuresList == "" {
		log.Error("--suite and --failures must be specified")
		os.Exit(1)
	}

	if err := plugin.ParseSuiteFailures(opt.SuiteList, opt.FailuresList, opt.OutputFile); err != nil {
		log.Error("error processing the suite failures: %w", err)
		os.Exit(1)
	}
}
