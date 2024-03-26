package plugin

import (
	"errors"
	"fmt"
	"os"
	"regexp"
	"time"

	log "github.com/sirupsen/logrus"
)

func watchForFile(filePath string, doneCallback func()) error {

	for {
		if _, err := os.Stat(filePath); err == nil {
			fmt.Println("Detected done, running callback.")
			doneCallback()
		} else if errors.Is(err, os.ErrNotExist) {
			time.Sleep(1 * time.Second)
			continue
		} else {
			// file may or may not exist. See err for details.
			log.Errorf("error watching for file %s: %v", filePath, err)
		}
		break
	}

	return nil
}

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
	if len(matchInfo) != 3 {
		return fmt.Errorf("%s parser: unexpected results: %v", res.ParserName, matchInfo)
	}
	reTS := regexp.MustCompile(fmt.Sprintf(`^%s(\:|)\s\(.*\)(?P<Timestamp>\s\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\s.*`, res.ParserName))
	matchTS := reTS.FindStringSubmatch(line)
	if len(matchTS) != 1 {
		log.Debugf("%s parser: unable to extract timestamp from line: %v", res.ParserName, line)
	} else {
		res.Endat = matchTS[1]
	}
	res.TestName = matchInfo[2]
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
