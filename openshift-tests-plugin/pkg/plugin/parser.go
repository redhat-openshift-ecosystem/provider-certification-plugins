package plugin

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"strings"
	"time"

	log "github.com/sirupsen/logrus"
)

// ParseSuiteFailures reads the failures list, get intersections from
// suite list, and returns only the items present in the suite.
func ParseSuiteFailures(in, suite, out string) error {
	// check files exists
	suiteFile, err := os.Open(suite)
	if err != nil {
		return fmt.Errorf("error openning the suite list: %w", err)
	}
	defer suiteFile.Close()

	scanner := bufio.NewScanner(suiteFile)
	suiteMap := make(map[string]struct{})
	for scanner.Scan() {
		suiteMap[scanner.Text()] = struct{}{}
	}

	failFile, err := os.Open(in)
	if err != nil {
		return fmt.Errorf("error opening failure list: %w", err)
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

	log.Infof("Found %d test failures on %s included in suite %s", len(failuresSuite), in, suite)
	if out != "" {
		file, err := os.Create(out)
		if err != nil {
			return fmt.Errorf("error creating output file: %w", err)
		}
		defer file.Close()

		w := bufio.NewWriter(file)
		for _, line := range failuresSuite {
			fmt.Fprintln(w, line)
		}
		err = w.Flush()
		if err != nil {
			return fmt.Errorf("error saving output file: %w", err)
		}
		log.Infof("Output file saved %s", out)
	}
	return nil
}

// ParseSuiteList reads the suite list and returns a map with the tests.
func ParseSuiteList(suite string) (map[string]struct{}, error) {
	suiteFile, err := os.Open(suite)
	if err != nil {
		log.WithError(err).Error("error reading the suite list")
		return nil, err
	}
	defer suiteFile.Close()

	scanner := bufio.NewScanner(suiteFile)
	suiteMap := make(map[string]struct{})
	for scanner.Scan() {
		line := scanner.Text()
		if !strings.HasPrefix(line, `"[`) {
			continue
		}
		suiteMap[scanner.Text()] = struct{}{}
	}
	return suiteMap, nil
}

// WriteTestSuite writes the suite to a file.
func WriteTestSuite(tests map[string]struct{}, outFile string) error {
	file, err := os.Create(outFile)
	if err != nil {
		return fmt.Errorf("error creating output file: %w", err)
	}
	defer file.Close()

	// write the test map to a file
	w := bufio.NewWriter(file)
	for test := range tests {
		fmt.Fprintln(w, test)
	}
	if err := w.Flush(); err != nil {
		return fmt.Errorf("error saving file: %w", err)
	}
	return nil
}

// resultLineParser is a struct to parse the results from the tests.
type resultLineParser struct {
	ParserName string
	TestName   string
	TimeTook   string
	Endat      string
}

// ExtractTestTimeFromLine parse line and extract information from it.
func (res *resultLineParser) ExtractTestTimeFromLine(line string) error {

	reInfo := regexp.MustCompile(fmt.Sprintf(`^%s(\:|)\s\((?P<Time>.*)\)(\s\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}|)\s(?P<TestName>.*)`, res.ParserName))
	matchInfo := reInfo.FindStringSubmatch(line)
	if len(matchInfo) < 3 {
		return fmt.Errorf("%s parser: unexpected results: matchCount(%d): %v", res.ParserName, len(matchInfo), matchInfo)
	}
	reTS := regexp.MustCompile(fmt.Sprintf(`^%s(\:|)\s\(.*\)(?P<Timestamp>\s\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\s.*`, res.ParserName))
	matchTS := reTS.FindStringSubmatch(line)
	if len(matchTS) < 1 {
		log.Debugf("%s parser: unable to extract timestamp from line: %v", res.ParserName, line)
	} else {
		res.Endat = matchTS[1]
	}
	res.TestName = matchInfo[3]
	res.TimeTook = matchInfo[1]

	return nil
}

// CalculateFields parse line and extract information from it.
func (res *resultLineParser) CalculateFields(tests map[string]*TestProgress) error {
	if _, ok := tests[res.TestName]; !ok {
		log.Errorf("%s parser: test not yet created, creating: %v", res.ParserName, res.TestName)
		tests[res.TestName] = &TestProgress{}
	}

	tests[res.TestName].Result = res.ParserName
	tests[res.TestName].EndAt = res.TimeTook
	tests[res.TestName].TimeTook = res.TimeTook
	d, _ := time.ParseDuration(tests[res.TestName].TimeTook)
	tests[res.TestName].TimeTookSeconds = d.Seconds()

	return nil
}
