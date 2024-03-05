package exec

import (
	"fmt"
	"os"

	"github.com/redhat-openshift-ecosystem/provider-certification-plugins/openshift-tests-plugin/pkg/plugin"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
)

type OptionsParserTestSuite struct {
	SuiteList  string
	OutputFile string
}

func NewCmdParserTestSuite() *cobra.Command {
	opts := OptionsParserTestSuite{}

	cmd := &cobra.Command{
		Use:   "parser-test-suite",
		Short: "Parser e2e stdout (from openshift-tests) extracting test names saving to output file.",
		Long: `Parse the e2e stdout (from openshift-tests) extracting test names saving to output file.
		Example:
		$ openshift-tests-plugin parser-test-suite --suite /tmp/e2e.log --output /tmp/e2e-tests.txt`,
		Run: func(cmd *cobra.Command, args []string) {
			if err := StartParseParserTestSuite(&opts); err != nil {
				log.Errorf("command finished with errors: %v", err)
				os.Exit(1)
			}
		},
	}

	cmd.Flags().StringVar(&opts.SuiteList, "e2e-log", "", "Input with the list of e2e tests available in the suite")
	cmd.Flags().StringVar(&opts.OutputFile, "output", "", "Output file path to save the tests")

	return cmd
}

func StartParseParserTestSuite(opt *OptionsParserTestSuite) error {
	if opt.SuiteList == "" {
		return fmt.Errorf("missing required flags: --suite")
	}

	tests, err := plugin.ParseSuiteList(opt.SuiteList)
	if err != nil {
		return fmt.Errorf("error processing the suite failures: %w", err)
	}

	log.Infof("Total tests: %d", len(tests))

	if opt.OutputFile != "" {
		if err := plugin.WriteTestSuite(tests, opt.OutputFile); err != nil {
			return fmt.Errorf("error writing the suite failures: %w", err)
		}
	} else {
		log.Info("Skipping output file, using --output to save the results")
	}

	return nil
}
