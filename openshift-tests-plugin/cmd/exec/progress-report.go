package exec

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"sort"
	"strings"
	"time"

	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
)

// TODO Progress Status Report

// Function: send frequently updates to sonobuoy API (aggregator server)

// Steps:
// - warm up updates
// - parse openshift-tests execution and send updates
// - unblock plugin

type OptionProgressReport struct {
	SampleInput string
}

func NewCmdProgressReport() *cobra.Command {

	opts := OptionProgressReport{}

	cmd := &cobra.Command{
		Use:   "progress-report",
		Short: "Read failures from execution and return only items present in the suite ",
		Long:  ``,
		Run: func(cmd *cobra.Command, args []string) {

			fmt.Println(">>> starting")
			StartProgressReport(&opts)

		},
	}

	cmd.Flags().StringVar(&opts.SampleInput, "input", "", "Parser input")

	return cmd
}

type ProgressReportTest struct {
	TestName        string
	StartedAt       string
	EndAt           string
	TimeTook        string
	TimeTookSeconds float64
	Result          string
}

type ProgressReport struct {
	StartedCount    int64
	PassedCount     int64
	SkippedCount    int64
	FailedCount     int64
	CompleteCount   int64
	TotalCount      int64
	FailedList      []string
	ProgressMessage string
	TestMap         map[string]*ProgressReportTest
}

func StartProgressReport(opt *OptionProgressReport) {
	if opt.SampleInput == "" {
		log.Error("--input must be specified")
		os.Exit(1)
	}

	report := ProgressReport{
		TestMap: make(map[string]*ProgressReportTest),
	}

	// check files exists
	suiteFile, err := os.Open(opt.SampleInput)
	if err != nil {
		log.WithError(err).Error("error reading the suite list")
		log.Fatal(err)
	}
	defer suiteFile.Close()
	scanner := bufio.NewScanner(suiteFile)
	for scanner.Scan() {
		line := scanner.Text()
		switch {
		case strings.HasPrefix(line, "started:"):
			report.StartedCount += 1

			re := regexp.MustCompile(`^started\:\s(?P<Counter>\d+\/\d+\/\d+)\s(?P<TestName>.*)`)
			match := re.FindStringSubmatch(line)
			if len(match) != 3 {
				log.Error("Unexpected results: %v", match)
				continue
			}
			// status := strings.Split(match[1], "/")
			testName := match[2]

			// fmt.Println(testName)
			report.TestMap[testName] = &ProgressReportTest{
				TestName: testName,
			}
			report.TestMap[testName].Result = "started"

		case strings.HasPrefix(line, "passed:"):
			report.PassedCount += 1
			// todo parse started

			re := regexp.MustCompile(`^passed\:\s\((?P<Time>.*)\)\s(?P<Timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\s(?P<TestName>.*)`)
			match := re.FindStringSubmatch(line)
			if len(match) != 4 {
				log.Errorf("passed Unexpected results: %v", match)
				continue
			}
			// status := strings.Split(match[1], "/")
			testName := match[3]
			if _, ok := report.TestMap[testName]; !ok {
				log.Errorf("passed test not mapped: %v", testName)
				continue
			}
			report.TestMap[testName].Result = "passed"
			report.TestMap[testName].TimeTook = match[1]
			d, _ := time.ParseDuration(report.TestMap[testName].TimeTook)
			report.TestMap[testName].TimeTookSeconds = d.Seconds()
			report.TestMap[testName].EndAt = match[2]

		case strings.HasPrefix(line, "skipped:"):
			report.SkippedCount += 1
			// todo parse started
			re := regexp.MustCompile(`^skipped\:\s\((?P<Time>.*)\)\s(?P<Timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\s(?P<TestName>.*)`)
			match := re.FindStringSubmatch(line)
			if len(match) != 4 {
				log.Errorf("skipped Unexpected results: %v", match)
				continue
			}
			// status := strings.Split(match[1], "/")
			testName := match[3]
			if _, ok := report.TestMap[testName]; !ok {
				log.Errorf("skipped test not mapped: %v", testName)
				continue
			}
			report.TestMap[testName].Result = "skipped"
			report.TestMap[testName].TimeTook = match[1]
			d, _ := time.ParseDuration(report.TestMap[testName].TimeTook)
			report.TestMap[testName].TimeTookSeconds = d.Seconds()
			report.TestMap[testName].EndAt = match[2]

		case strings.HasPrefix(line, "failed:"):
			report.FailedCount += 1
			re := regexp.MustCompile(`^failed\:\s\((?P<Time>.*)\)\s(?P<Timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\s(?P<TestName>.*)`)
			match := re.FindStringSubmatch(line)
			if len(match) != 4 {
				log.Errorf("failed Unexpected results: %v", match)
				continue
			}
			// status := strings.Split(match[1], "/")
			testName := match[3]
			if _, ok := report.TestMap[testName]; !ok {
				log.Errorf("failed test not mapped: %v", testName)
				continue
			}
			report.TestMap[testName].Result = "failed"
			report.TestMap[testName].TimeTook = match[1]
			d, _ := time.ParseDuration(report.TestMap[testName].TimeTook)
			report.TestMap[testName].TimeTookSeconds = d.Seconds()
			report.TestMap[testName].EndAt = match[2]
		default:
			continue
		}
		report.CompleteCount = report.PassedCount + report.SkippedCount + report.FailedCount
		report.TotalCount = report.CompleteCount
	}

	// for e2e := range report.TestMap {
	// 	fmt.Printf("%s (%.3f) %s\n", report.TestMap[e2e].Result, report.TestMap[e2e].TimeTookSeconds, e2e)
	// }

	// Rank by slow
	for _, e2e := range rankByWordCount(report.TestMap) {
		fmt.Printf("%s (%.3f) %s\n", e2e.Result, e2e.TimeTookSeconds, e2e.TestName)
	}
	fmt.Printf("\n>> Summary: T/C/P/F/S=%d/%d/%d/%d/%d\n", report.TotalCount, report.CompleteCount, report.PassedCount, report.FailedCount, report.SkippedCount)
}

type ProgressReportTestList []ProgressReportTest

func rankByWordCount(wordFrequencies map[string]*ProgressReportTest) ProgressReportTestList {
	pl := make(ProgressReportTestList, len(wordFrequencies))
	i := 0
	for _, v := range wordFrequencies {
		pl[i] = *v
		i++
	}
	sort.Sort(sort.Reverse(pl))
	return pl
}

// type Pair struct {
// 	Key   string
// 	Value int
// }

func (p ProgressReportTestList) Len() int { return len(p) }
func (p ProgressReportTestList) Less(i, j int) bool {
	return p[i].TimeTookSeconds < p[j].TimeTookSeconds
}
func (p ProgressReportTestList) Swap(i, j int) { p[i], p[j] = p[j], p[i] }
