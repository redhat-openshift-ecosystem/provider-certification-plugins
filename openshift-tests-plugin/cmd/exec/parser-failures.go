package exec

import (
	"bufio"
	"fmt"
	"os"

	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
)

// TODO parser failures to filter only included in the suite to replay
// Input:
// - suite list
// - failures list
// Output: stadout or file: intersection of both lists
// Optional: upload to configmap

type OptionsParserFailures struct {
	SuiteList    string
	FailuresList string
	OutputFile   string
}

func NewCmdParserFailres() *cobra.Command {

	opts := OptionsParserFailures{}

	cmd := &cobra.Command{
		Use:   "parser-failures-suite",
		Short: "Read failures from execution and return only items present in the suite ",
		Long:  ``,
		Run: func(cmd *cobra.Command, args []string) {

			fmt.Println(">>> starting")
			StartParseSuiteFailures(&opts)

		},
	}

	cmd.Flags().StringVar(&opts.SuiteList, "suite", "", "Input with the list of e2e tests available in the suite")
	cmd.Flags().StringVar(&opts.FailuresList, "failures", "", "List of failures")
	cmd.Flags().StringVar(&opts.OutputFile, "output", "", "Failure stdout")

	return cmd
}

func StartParseSuiteFailures(opt *OptionsParserFailures) {

	if opt.SuiteList == "" || opt.FailuresList == "" {
		log.Error("--suite and --failures must be specified")
		os.Exit(1)
	}

	// check files exists
	suiteFile, err := os.Open(opt.SuiteList)
	if err != nil {
		log.WithError(err).Error("error reading the suite list")
		log.Fatal(err)
	}
	defer suiteFile.Close()

	scanner := bufio.NewScanner(suiteFile)
	suiteMap := make(map[string]struct{})
	for scanner.Scan() {
		suiteMap[scanner.Text()] = struct{}{}
	}

	failFile, err := os.Open(opt.FailuresList)
	if err != nil {
		log.WithError(err).Error("error reading the suite list")
		log.Fatal(err)
	}
	defer suiteFile.Close()

	failScan := bufio.NewScanner(failFile)
	var failuresSuite []string
	for failScan.Scan() {
		test := failScan.Text()
		if _, ok := suiteMap[test]; ok {
			failuresSuite = append(failuresSuite, test)
		}
	}

	fmt.Printf("Found %d\n", len(failuresSuite))
	if opt.OutputFile != "" {
		file, err := os.Create(opt.OutputFile)
		if err != nil {
			log.WithError(err).Error("error creating output file")
			log.Fatal(err)
		}
		defer file.Close()

		w := bufio.NewWriter(file)
		for _, line := range failuresSuite {
			fmt.Fprintln(w, line)
		}
		err = w.Flush()
		if err != nil {
			log.WithError(err).Error("error saving file")
			log.Fatal(err)
		}
		fmt.Printf("File saved at %s\n", opt.OutputFile)
	}
}
