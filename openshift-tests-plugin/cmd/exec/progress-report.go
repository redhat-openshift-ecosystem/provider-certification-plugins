package exec

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
	"sort"
	"strings"
	"time"

	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"

	"github.com/davecgh/go-spew/spew"
)

// TODO Progress Status Report

// Function: send frequently updates to sonobuoy API (aggregator server)

// Steps:
// - warm up updates
// - parse openshift-tests execution and send updates
// - unblock plugin

type OptionProgressReport struct {
	InputTotal  int64
	Input       string
	WatchInput  bool
	DoneControl string
	SkipUpdate  bool
	ShowRank    bool
	RankReverse bool
	ShowLimit   int64
}

func NewCmdProgressReport() *cobra.Command {

	opts := OptionProgressReport{}

	cmd := &cobra.Command{
		Use:   "progress-report",
		Short: "Read failures from execution and return only items present in the suite ",
		Long:  ``,
		Run: func(cmd *cobra.Command, args []string) {
			StartProgressReport(&opts)
		},
	}

	cmd.Flags().Int64Var(&opts.InputTotal, "input-total", 0, "Total counter of expected tests to run. Default: count(${SHARED_DIR}/suite.list)")
	cmd.Flags().StringVar(&opts.Input, "input", "", "Parser input file/fifo. Example: /tmp/fifo")
	cmd.Flags().BoolVar(&opts.WatchInput, "watch", false, "Keep reading the input file. Requires --done flag.")
	cmd.Flags().StringVar(&opts.DoneControl, "done", "", "Define the exit control file. Example: /tmp/done")
	cmd.Flags().BoolVar(&opts.SkipUpdate, "skip-update", false, "Skip update the report to Sonobuoy aggregator/worker API (sidecar).")
	cmd.Flags().BoolVar(&opts.ShowRank, "show-rank", false, "Show tests by Rank. Currently only Rank field 'TimeTaken' is supported.")
	cmd.Flags().BoolVar(&opts.RankReverse, "rank-reverse", false, "Reverse the rank results.")
	cmd.Flags().Int64Var(&opts.ShowLimit, "show-limit", 0, "Limit the results.")

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

type ResponseBody struct {
	Completed int64    `json:"completed,omitempty"`
	Total     int64    `json:"total,omitempty"`
	Failures  []string `json:"failures,omitempty"`
	Message   string   `json:"msg,omitempty"`
}

func progressReportSendUpdate(report *ProgressReport, msg string) {
	url := "http://127.0.0.1:8099/progress"
	payload := ResponseBody{
		Message: msg,
	}
	if report.CompleteCount > 0 {
		payload.Completed = report.CompleteCount
	}
	if report.CompleteCount > 0 {
		payload.Total = report.TotalCount
	}
	if len(report.FailedList) > 0 {
		payload.Failures = report.FailedList
	}
	marshalled, err := json.Marshal(payload)
	if err != nil {
		spew.Dump(payload)
		log.WithError(err).Error("impossible to marshall")
		return
	}

	req, err := http.NewRequest("POST", url, bytes.NewBuffer(marshalled))
	if err != nil {
		spew.Dump(payload)
		log.WithError(err).Error("error creating request")
		return
	}
	req.Header.Set("X-Custom-Header", "myvalue")
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		spew.Dump(payload)
		log.WithError(err).Error("error sending request update")
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		spew.Dump(payload)
		fmt.Println("URL:>", url)
		fmt.Println("response Status:", resp.Status)
		fmt.Println("response Headers:", resp.Header)
		body, _ := io.ReadAll(resp.Body)
		fmt.Println("response Body:", string(body))
	}
}

func parserOpenShiftTestsOutputLine(report *ProgressReport, line string) (skip bool, err error) {
	switch {
	case strings.HasPrefix(line, "started:"):
		report.StartedCount += 1

		re := regexp.MustCompile(`^started\:\s(?P<Counter>\d+\/\d+\/\d+)\s(?P<TestName>.*)`)
		match := re.FindStringSubmatch(line)
		if len(match) != 3 {
			log.Error("Unexpected results: %v", match)
			return true, nil
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
			return true, nil
		}
		// status := strings.Split(match[1], "/")
		testName := match[3]
		if _, ok := report.TestMap[testName]; !ok {
			log.Errorf("passed test not mapped: %v", testName)
			return true, nil
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
			return true, nil
		}
		// status := strings.Split(match[1], "/")
		testName := match[3]
		if _, ok := report.TestMap[testName]; !ok {
			log.Errorf("skipped test not mapped: %v", testName)
			return true, nil
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
			return true, nil
		}
		// status := strings.Split(match[1], "/")
		testName := match[3]
		if _, ok := report.TestMap[testName]; !ok {
			log.Errorf("failed test not mapped: %v", testName)
			return true, nil
		}
		report.TestMap[testName].Result = "failed"
		report.TestMap[testName].TimeTook = match[1]
		d, _ := time.ParseDuration(report.TestMap[testName].TimeTook)
		report.TestMap[testName].TimeTookSeconds = d.Seconds()
		report.TestMap[testName].EndAt = match[2]
	default:
		return true, nil
	}
	return false, nil
}

func StartProgressReport(opt *OptionProgressReport) {
	if opt.Input == "" {
		log.Error("--input must be specified")
		os.Exit(1)
	}

	report := ProgressReport{
		TotalCount: opt.InputTotal,
		TestMap:    make(map[string]*ProgressReportTest),
	}
	doneNotify := false
	done := make(chan struct{})

	// Start listening for events.
	go func() {
		for {
			if _, err := os.Stat(opt.DoneControl); err == nil {
				fmt.Println("Detected done. Notify reader")
				doneNotify = true
				done <- struct{}{}
			} else if errors.Is(err, os.ErrNotExist) {
				time.Sleep(1 * time.Second)
				continue
			} else {
				// file may or may not exist. See err for details.
				fmt.Println("%s", err)
			}
			break
		}
	}()

	// watch the file/fifo for updates
	go func() {
		for {
			if doneNotify {
				log.Println("Detected done. Stopping reader")
				break
			}
			suiteFile, err := os.Open(opt.Input)
			if err != nil {
				log.WithError(err).Error("error reading the input stream")
				// log.Fatal(err)
				// waiting 2 for the next check
				time.Sleep(1 * time.Second)
				continue
			}
			defer suiteFile.Close()
			scanner := bufio.NewScanner(suiteFile)
			log.Println("Consuming data from stream %s", opt.Input)
			for scanner.Scan() {
				line := scanner.Text()
				skip, err := parserOpenShiftTestsOutputLine(&report, line)
				if err != nil {
					log.WithError(err).Error("line parser error")
					// or return/break??
					continue
				}
				if skip {
					continue
				}
				report.CompleteCount = report.PassedCount + report.SkippedCount + report.FailedCount
				// TotalCount is extracted from the suite list. If it isn't set or unknown, set it while
				// incrementally while the suite is executed.
				if report.CompleteCount >= report.TotalCount {
					report.TotalCount = report.CompleteCount
				}
				if !opt.SkipUpdate {
					msg := fmt.Sprintf("status=running=T/C/P/F/S=%d/%d/%d/%d/%d",
						report.TotalCount, report.CompleteCount, report.PassedCount,
						report.FailedCount, report.SkippedCount)
					progressReportSendUpdate(&report, msg)
				}
			}

			log.Printf("\n>> Summary: T/C/P/F/S=%d/%d/%d/%d/%d\n", report.TotalCount, report.CompleteCount, report.PassedCount, report.FailedCount, report.SkippedCount)
		}
	}()

	log.Println("Consuming data from stream. Waiting until is finished...")
	<-done

	// Raw results
	// for e2e := range report.TestMap {
	// 	fmt.Printf("%s (%.3f) %s\n", report.TestMap[e2e].Result, report.TestMap[e2e].TimeTookSeconds, e2e)
	// }

	// Rank by slower first
	if opt.ShowRank {
		log.Println("Showing summary by rank of slower test")
		for idx, e2e := range rankByTestField(report.TestMap, "TimeTookSeconds", opt.RankReverse) {
			fmt.Printf("%s (%.3f) %s\n", e2e.Result, e2e.TimeTookSeconds, e2e.TestName)
			if opt.ShowLimit != 0 && int64(idx) >= opt.ShowLimit {
				break
			}
		}
	}
	fmt.Printf("\n>> Summary Final: T/C/P/F/S=%d/%d/%d/%d/%d\n", report.TotalCount, report.CompleteCount, report.PassedCount, report.FailedCount, report.SkippedCount)
}

// Rank

type ProgressReportTestList []ProgressReportTest

func rankByTestField(wordFrequencies map[string]*ProgressReportTest, rankType string, reverse bool) ProgressReportTestList {
	pl := make(ProgressReportTestList, len(wordFrequencies))
	i := 0
	for _, v := range wordFrequencies {
		pl[i] = *v
		i++
	}
	if reverse {
		sort.Sort(sort.Reverse(pl))
	} else {
		sort.Sort(pl)
	}

	return pl
}

func (p ProgressReportTestList) Len() int { return len(p) }
func (p ProgressReportTestList) Less(i, j int) bool {
	return p[i].TimeTookSeconds < p[j].TimeTookSeconds
}
func (p ProgressReportTestList) Swap(i, j int) { p[i], p[j] = p[j], p[i] }
