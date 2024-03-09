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
)

// TODO Progress Status Report

// Function: send frequently updates to sonobuoy API (aggregator server)

// Steps:
// - warm up updates
// - parse openshift-tests execution and send updates
// - unblock plugin

type OptionProgressReport struct {
	SampleInput string
	DoneControl string
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
	cmd.Flags().StringVar(&opts.DoneControl, "done", "", "done file")

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
	Completed string   `json:"completed"`
	Total     string   `json:"total"`
	Failures  []string `json:"failures"`
	Message   string   `json:"msg"`
}

func progressReportSendUpdate(report *ProgressReport, msg string) {
	url := "http://127.0.0.1:8099/progress"
	fmt.Println("URL:>", url)

	payload := ResponseBody{
		Completed: fmt.Sprintf("%d", report.CompleteCount),
		Total:     fmt.Sprintf("%d", report.TotalCount),
		Failures:  report.FailedList,
		Message:   msg,
	}
	marshalled, err := json.Marshal(payload)
	if err != nil {
		log.Fatalf("impossible to marshall teacher: %s", err)
	}

	req, err := http.NewRequest("POST", url, bytes.NewBuffer(marshalled))
	req.Header.Set("X-Custom-Header", "myvalue")
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		// panic(err)
		log.WithError(err).Error("error sending request update")
		return
	}
	defer resp.Body.Close()

	fmt.Println("response Status:", resp.Status)
	fmt.Println("response Headers:", resp.Header)
	body, _ := io.ReadAll(resp.Body)
	fmt.Println("response Body:", string(body))
}

func StartProgressReport(opt *OptionProgressReport) {
	if opt.SampleInput == "" {
		log.Error("--input must be specified")
		os.Exit(1)
	}

	report := ProgressReport{
		TestMap: make(map[string]*ProgressReportTest),
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
				// Schrodinger: file may or may not exist. See err for details.

				// Therefore, do *NOT* use !os.IsNotExist(err) to test for file existence
				fmt.Println("%s", err)

			}
			// fmt.Println("Detected done. Notify reader")
			// doneNotify = true
			break
		}
	}()

	// watch the file/fifo for updates
	go func() {
		for {

			if doneNotify {
				fmt.Println("Detected done. Stopping reader")
				break
			}
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

			fmt.Printf("\n>> Summary: T/C/P/F/S=%d/%d/%d/%d/%d\n", report.TotalCount, report.CompleteCount, report.PassedCount, report.FailedCount, report.SkippedCount)

			// TODO send data to worker API
			// msg_status := fmt.Sprintf(")
			msg := fmt.Sprintf("status=running=T/C/P/F/S=%s/%s/%s/%s/%s",
				report.TotalCount, report.CompleteCount, report.PassedCount,
				report.FailedCount, report.SkippedCount)
			progressReportSendUpdate(&report, msg)
		}

	}()

	fmt.Println("Waiting to consume data from fifo...")
	<-done
	// for e2e := range report.TestMap {
	// 	fmt.Printf("%s (%.3f) %s\n", report.TestMap[e2e].Result, report.TestMap[e2e].TimeTookSeconds, e2e)
	// }

	// Rank by slow
	// for _, e2e := range rankByWordCount(report.TestMap) {
	// 	fmt.Printf("%s (%.3f) %s\n", e2e.Result, e2e.TimeTookSeconds, e2e.TestName)
	// }
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
