package plugin

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
	"strings"
	"sync"

	"github.com/hashicorp/go-retryablehttp"
	log "github.com/sirupsen/logrus"
	"k8s.io/utils/ptr"
)

// PluginProgress holds the progress state.
type PluginProgress struct {
	StartedCount    *int64
	PassedCount     *int64
	SkippedCount    *int64
	FailedCount     *int64
	CompleteCount   *int64
	TotalCount      *int64
	FailedList      []string
	ProgressMessage *string
	TestMap         map[string]*TestProgress

	svc *pluginProgressService
}

// NewPluginProgress creates a new PluginProgress service.
func NewPluginProgress() *PluginProgress {
	return &PluginProgress{
		TestMap: make(map[string]*TestProgress),
		svc: &pluginProgressService{
			url: ProgressURL,
		},
	}
}

// Set update counters for progress updater.
func (ps *PluginProgress) Set(v *PluginProgress) {
	if v.StartedCount != nil {
		ps.StartedCount = ptr.To(*v.StartedCount)
	}
	if v.PassedCount != nil {
		ps.PassedCount = ptr.To(*v.PassedCount)
	}
	if v.SkippedCount != nil {
		ps.SkippedCount = ptr.To(*v.SkippedCount)
	}
	if v.FailedCount != nil {
		ps.FailedCount = ptr.To(*v.FailedCount)
	}
	if v.CompleteCount != nil {
		ps.CompleteCount = ptr.To(*v.CompleteCount)
	}
	if v.TotalCount != nil {
		ps.TotalCount = ptr.To(*v.TotalCount)
	}
	if v.ProgressMessage != nil {
		ps.ProgressMessage = ptr.To(*v.ProgressMessage)
	}
}

// Inc set or updates the counter based in the incoming value.
func (ps *PluginProgress) Inc(v *PluginProgress) {
	if v.StartedCount != nil {
		if ps.StartedCount != nil {
			*v.StartedCount = *ps.StartedCount + *v.StartedCount
		}
	}
	if v.PassedCount != nil {
		if ps.PassedCount != nil {
			*v.PassedCount = *ps.PassedCount + *v.PassedCount
		}
	}
	if v.SkippedCount != nil {
		if ps.SkippedCount != nil {
			*v.SkippedCount = *ps.SkippedCount + *v.SkippedCount
		}
	}
	if v.FailedCount != nil {
		if ps.FailedCount != nil {
			*v.FailedCount = *ps.FailedCount + *v.FailedCount
			ps.FailedList = append(ps.FailedList, fmt.Sprintf("failed #%d", *v.FailedCount))
		}
	}
	if v.CompleteCount != nil {
		if ps.CompleteCount != nil {
			*v.CompleteCount = *ps.CompleteCount + *v.CompleteCount
		}
	}
	if v.TotalCount != nil {
		if ps.TotalCount != nil {
			*v.TotalCount = *ps.TotalCount + *v.TotalCount
		}
	}
	ps.Set(v)
}

// UpdateTotalCounters updates the total counters based on the current state.
func (ps *PluginProgress) UpdateTotalCounters() {
	pass := int64(0)
	skip := int64(0)
	failed := int64(0)
	total := int64(0)
	completed := int64(0)
	if ps.PassedCount != nil {
		pass = *ps.PassedCount
	}
	if ps.SkippedCount != nil {
		skip = *ps.SkippedCount
	}
	if ps.FailedCount != nil {
		failed = *ps.FailedCount
	}
	if ps.TotalCount != nil {
		total = *ps.TotalCount
	}
	// There are some inconsistency in the counters provided by openshift-tests output,
	// so the "Completed" (counter maintained by OPCT parsing from output) is
	// taking precedence from 'total' (provided by openshift-tests).
	ps.CompleteCount = ptr.To(pass + skip + failed)
	completed = *ps.CompleteCount
	if completed >= total {
		ps.TotalCount = ptr.To(*ps.CompleteCount)
		total = *ps.TotalCount
	}

	ps.ProgressMessage = ptr.To(fmt.Sprintf("status=running=T/C/P/F/S=%d/%d/%d/%d/%d",
		total, completed, pass, failed, skip))
}

// GetTotalCountersString returns the counters in a string format.
func (ps *PluginProgress) GetTotalCountersString() string {
	pass := int64(0)
	skip := int64(0)
	failed := int64(0)
	total := int64(0)
	completed := int64(0)
	if ps.PassedCount != nil {
		pass = *ps.PassedCount
	}
	if ps.SkippedCount != nil {
		skip = *ps.SkippedCount
	}
	if ps.FailedCount != nil {
		failed = *ps.FailedCount
	}
	if ps.TotalCount != nil {
		total = *ps.TotalCount
	}
	if ps.CompleteCount != nil {
		completed = *ps.CompleteCount
	}

	return fmt.Sprintf("T/C/P/F/S=%d/%d/%d/%d/%d",
		total, completed, pass, failed, skip)
}

// UpdateAndSend updates the current state and send to the service.
func (ps *PluginProgress) UpdateAndSend() {
	if ps.CompleteCount != nil {
		ps.svc.Completed = *ps.CompleteCount
	}
	if ps.TotalCount != nil {
		ps.svc.Total = *ps.TotalCount
	}
	if ps.ProgressMessage != nil {
		ps.svc.Message = *ps.ProgressMessage
	}
	if len(ps.FailedList) > 0 {
		ps.svc.Failures = ps.FailedList
	}
	ps.svc.Send()
}

// ParserOpenShiftTestsOutputLine parse the openshift-tests output line and update the counters.
func (ps *PluginProgress) ParserOpenShiftTestsOutputLine(line string) (skip bool, err error) {
	switch {
	case strings.HasPrefix(line, "started:"):
		ps.Inc(&PluginProgress{StartedCount: ptr.To(int64(1))})
		res := &resultLineParser{ParserName: "started"}
		re := regexp.MustCompile(`^started\:\s(?P<Counter>\d+\/\d+\/\d+)\s(?P<TestName>.*)`)
		match := re.FindStringSubmatch(line)
		if len(match) != 3 {
			log.Warnf("parser (%s): unexpected expression to extract results: %v", res.ParserName, match)
			return true, nil
		}
		testName := match[2]
		ps.TestMap[testName] = &TestProgress{
			TestName: testName,
		}
		ps.TestMap[testName].Result = "started"

	case strings.HasPrefix(line, "passed:"), strings.HasPrefix(line, "passed ("):
		ps.Inc(&PluginProgress{PassedCount: ptr.To(int64(1))})

		res := &resultLineParser{ParserName: "passed"}
		err := res.ExtractTestTimeFromLine(line)
		if err != nil {
			log.Warnf("parser (%s): error extracting test time: %v", res.ParserName, err)
			return true, nil
		}
		if err := res.CalculateFields(ps.TestMap); err != nil {
			log.Warnf("parser (%s): error calculating fields: %v", res.ParserName, err)
			return true, nil
		}

	case strings.HasPrefix(line, "skipped:"), strings.HasPrefix(line, "skipped ("):
		ps.Inc(&PluginProgress{SkippedCount: ptr.To(int64(1))})

		res := &resultLineParser{ParserName: "skipped"}
		err := res.ExtractTestTimeFromLine(line)
		if err != nil {
			log.Warnf("parser (%s): error extracting test time: %v", res.ParserName, err)
			return true, nil
		}
		if err := res.CalculateFields(ps.TestMap); err != nil {
			log.Warnf("parser (%s): error calculating fields: %v", res.ParserName, err)
			return true, nil
		}

	case strings.HasPrefix(line, "failed:"), strings.HasPrefix(line, "failed ("):
		ps.Inc(&PluginProgress{FailedCount: ptr.To(int64(1))})

		res := &resultLineParser{ParserName: "failed"}
		err := res.ExtractTestTimeFromLine(line)
		if err != nil {
			log.Warnf("parser (%s): error extracting test time: %v", res.ParserName, err)
			return true, nil
		}

		if err := res.CalculateFields(ps.TestMap); err != nil {
			log.Warnf("parser (%s): error calculating fields: %v", res.ParserName, err)
			return true, nil
		}

	default:
		return true, nil
	}
	return false, nil
}

// LoadTotalTestsFromSuite loads and parses the suite file (output of openshift-tests --dry-run),
// filtering only suite test names.
func (ps *PluginProgress) LoadTotalTestsFromSuite(suiteFile string) (err error) {
	// Load the counters from the suite file.
	suiteList := []string{}
	suiteFD, err := os.Open(suiteFile)
	if err != nil {
		log.WithError(err).Error("error reading the suite list")
		return fmt.Errorf("error reading the suite list: %w", err)
	}
	defer suiteFD.Close()

	scanner := bufio.NewScanner(suiteFD)
	for scanner.Scan() {
		line := scanner.Text()
		if !strings.HasPrefix(line, `"[`) {
			continue
		}
		suiteList = append(suiteList, line)
	}
	log.Infof("Found %d tests on %s", len(suiteList), suiteFile)
	ps.TotalCount = ptr.To(int64(len(suiteList)))
	return nil
}

// PluginProgress handle the HTTP requests to the progress service.
type pluginProgressService struct {
	Completed int64    `json:"completed,omitempty"`
	Total     int64    `json:"total,omitempty"`
	Failures  []string `json:"failures,omitempty"`
	Message   string   `json:"msg,omitempty"`

	sync.RWMutex `json:"-"`
	url          string `json:"-"`
}

// Send send message to sonobuoy worker service.
// TODO(mtulio): re-use keepalive HTTP connections.
func (s *pluginProgressService) Send() {
	marshaled, err := json.Marshal(s)
	if err != nil {
		log.WithError(err).Error("unable to marshall")
		return
	}

	req, err := http.NewRequest("POST", s.url, bytes.NewBuffer(marshaled))
	if err != nil {
		log.WithError(err).Error("error creating request")
		return
	}
	req.Header.Set("X-Custom-Header", "openshift-tests-plugin")
	req.Header.Set("Content-Type", "application/json")

	// create http client with backoff retries, forcing the loglevel to info.
	retryClient := retryablehttp.NewClient()
	retryClient.RetryMax = 5
	retryLogger := log.New()
	retryLogger.SetLevel(log.InfoLevel)
	retryClient.Logger = retryLogger

	client := retryClient.StandardClient()
	resp, err := client.Do(req)
	if err != nil {
		log.WithError(err).Error("error sending request update")
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		fmt.Println("URL:>", s.url)
		fmt.Println("response Status:", resp.Status)
		fmt.Println("response Headers:", resp.Header)
		body, _ := io.ReadAll(resp.Body)
		fmt.Println("response Body:", string(body))
	}
}
