package exec

import (
	"bytes"
	"fmt"
	"os"
	"testing"

	tdata "github.com/redhat-openshift-ecosystem/provider-certification-plugins/openshift-tests-plugin/test"
	log "github.com/sirupsen/logrus"
	"github.com/stretchr/testify/assert"
)

func TestStartParseJUnitFailures(t *testing.T) {
	td := tdata.NewTestReader()
	defer td.CleanUp()

	// Extract the suite list from the VFS
	suiteFile, err := td.OpenFile("testdata/suites/suite10.list")
	if err != nil {
		t.Fatalf("error opening suite file: %v", err)
	}
	// Extract the XML from the VFS
	xfsFile, err := td.OpenFile("testdata/suites/junit5.xml")
	if err != nil {
		t.Fatalf("error opening junit file: %v", err)
	}

	// Expected output data/files
	outJunitFailuresWantEFS := "testdata/suites/junit5-out-failures.txt"
	outJunitFailuresWant, err := td.OpenFile(outJunitFailuresWantEFS)
	if err != nil {
		t.Fatalf("error opening junit file: %v", err)
	}
	outJunitFailuresSuiteWantEFS := "testdata/suites/junit5-out-failures-suite10.txt"
	outJunitFailuresSuiteWant, err := td.OpenFile(outJunitFailuresSuiteWantEFS)
	if err != nil {
		t.Fatalf("error opening junit file: %v", err)
	}

	outJunitFailuresGot := "/tmp/junit-failures-out-got.txt"
	outJunitFailuresSuiteGot := "/tmp/junit-failures-suite-out-got.txt"
	td.InsertTempFile(outJunitFailuresGot)
	td.InsertTempFile(outJunitFailuresSuiteGot)

	// Helper function to compare files
	compareFiles := func(file1, file2 string) (bool, error) {
		content1, e1 := os.ReadFile(file1)
		if e1 != nil {
			return false, e1
		}
		content2, e2 := os.ReadFile(file2)
		if e2 != nil {
			return false, e2
		}
		return bytes.Equal(content1, content2), nil
	}

	// Test
	type testCase struct {
		name         string
		opt          *OptionsParserJUnit
		err          error
		run          func(*testing.T, *OptionsParserJUnit) error
		checkResults func(*testing.T, *OptionsParserJUnit)
	}
	cases := []*testCase{
		{
			name: "valid input",
			opt: &OptionsParserJUnit{
				SuiteList:           suiteFile,
				FailuresListXML:     xfsFile,
				OutputFailuresXML:   outJunitFailuresGot,
				OutputFailuresSuite: outJunitFailuresSuiteGot,
			},
			err: nil,
			run: func(t *testing.T, opt *OptionsParserJUnit) error {
				return StartParseJUnitFailures(opt)
			},
			checkResults: func(t *testing.T, opt *OptionsParserJUnit) {
				log.Debugf("comparing files %s to %s", outJunitFailuresGot, outJunitFailuresWant)
				equal, err := compareFiles(outJunitFailuresGot, outJunitFailuresWant)
				if err != nil {
					log.Errorf("error comparing files: %v", err)
				}
				assert.NoError(t, err)
				assert.True(t, equal)

				log.Debugf("comparing files %s to %s", outJunitFailuresSuiteGot, outJunitFailuresSuiteWant)
				equal, err = compareFiles(outJunitFailuresSuiteGot, outJunitFailuresSuiteWant)
				if err != nil {
					log.Errorf("error comparing files: %v", err)
				}
				assert.NoError(t, err)
				assert.True(t, equal)
			},
		},
		{
			name: "error when missing suite list",
			opt: &OptionsParserJUnit{
				SuiteList:           "",
				FailuresListXML:     xfsFile,
				OutputFailuresXML:   outJunitFailuresGot,
				OutputFailuresSuite: outJunitFailuresSuiteGot,
			},
			err: fmt.Errorf("--suite and --failures must be specified"),
			run: func(t *testing.T, opt *OptionsParserJUnit) error {
				return StartParseJUnitFailures(opt)
			},
			checkResults: nil,
		},
		{
			name: "error when missing JUnit",
			opt: &OptionsParserJUnit{
				SuiteList:           suiteFile,
				FailuresListXML:     "",
				OutputFailuresXML:   outJunitFailuresGot,
				OutputFailuresSuite: outJunitFailuresSuiteGot,
			},
			err: fmt.Errorf("--suite and --failures must be specified"),
			run: func(t *testing.T, opt *OptionsParserJUnit) error {
				return StartParseJUnitFailures(opt)
			},
			checkResults: nil,
		},
		{
			name: "error when invalid output failures junit",
			opt: &OptionsParserJUnit{
				SuiteList:           suiteFile,
				FailuresListXML:     xfsFile,
				OutputFailuresXML:   outJunitFailuresGot,
				OutputFailuresSuite: outJunitFailuresSuiteGot,
			},
			err: nil,
			run: func(t *testing.T, opt *OptionsParserJUnit) error {
				return StartParseJUnitFailures(opt)
			},
			checkResults: func(t *testing.T, opt *OptionsParserJUnit) {
				log.Debugf("comparing files %s to %s", outJunitFailuresGot, outJunitFailuresSuiteWant)
				equal, err := compareFiles(outJunitFailuresGot, outJunitFailuresSuiteWant)
				if err != nil {
					log.Errorf("error comparing files: %v", err)
				}
				assert.NoError(t, err)
				assert.False(t, equal)
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := tc.run(t, tc.opt)
			assert.Equal(t, tc.err, err)
			if tc.checkResults != nil {
				tc.checkResults(t, tc.opt)
			}
		})
	}
}
