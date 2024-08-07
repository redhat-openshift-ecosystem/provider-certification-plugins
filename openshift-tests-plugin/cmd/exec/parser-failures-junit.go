package exec

import (
	"fmt"
	"os"

	"github.com/redhat-openshift-ecosystem/provider-certification-plugins/openshift-tests-plugin/pkg/plugin"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
)

type OptionsParserJUnit struct {
	SuiteList           string
	FailuresListXML     string
	OutputFailuresXML   string
	OutputFailuresSuite string
}

func NewCmdParserJUnit() *cobra.Command {
	opts := OptionsParserJUnit{}

	cmd := &cobra.Command{
		Use:   "parser-failures-junit",
		Short: "Extract test failures from a JUnit file, extracting failed tests, saving both list of failures and intersection with suite.",
		Long: `
		parser-failures-junit extracts test failures from a JUnit file, saving both list of failures and intersection with suite.
		Example:
		$ openshift-tests-plugin parser-failures-junit --suite /tmp/suite.txt --xml /tmp/junit.xml --out-failures-xml /tmp/failures-junit.txt --out-failures-suite /tmp/failures-suite.txt`,
		Run: func(cmd *cobra.Command, args []string) {
			err := StartParseJUnitFailures(&opts)
			if err != nil {
				log.Fatalf("command finished with errors: %v", err)
			}
		},
	}

	cmd.Flags().StringVar(&opts.SuiteList, "suite", "", "Input with the list of e2e tests available in the suite")
	cmd.Flags().StringVar(&opts.FailuresListXML, "xml", "", "Input JUnit XML")
	cmd.Flags().StringVar(&opts.OutputFailuresXML, "out-failures-xml", "", "Failures output file raw parsed from XML.")
	cmd.Flags().StringVar(&opts.OutputFailuresSuite, "out-failures-suite", "", "Failures output file of intersection from suite list.")

	return cmd
}

func StartParseJUnitFailures(opt *OptionsParserJUnit) error {
	if opt.SuiteList == "" || opt.FailuresListXML == "" {
		return fmt.Errorf("--suite and --failures must be specified")
	}

	pl, err := plugin.NewPlugin(plugin.PluginName05)
	if err != nil {
		return fmt.Errorf("unable to create fake plugin: %w", err)
	}

	if err := pl.ParseAndExtractFailuresFromJunit(opt.SuiteList, opt.FailuresListXML, opt.OutputFailuresXML, opt.OutputFailuresSuite); err != nil {
		log.Error("error processing junit: %w", err)
		os.Exit(1)
	}
	return nil
}
