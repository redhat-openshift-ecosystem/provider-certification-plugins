package exec

import (
	"testing"

	tdata "github.com/redhat-openshift-ecosystem/provider-certification-plugins/openshift-tests-plugin/test"
	"github.com/stretchr/testify/assert"
)

func TestStartParseParserTestSuite(t *testing.T) {
	// removeFiles := []string{}
	// defer testCleanUp(removeFiles)
	td := tdata.NewTestReader()
	defer td.CleanUp()

	// Extract the suite list from the VFS
	suiteFile, err := td.OpenFile("testdata/suites/suite10.list")
	if err != nil {
		t.Fatalf("error opening suite file: %v", err)
	}

	outputFile := "/tmp/oplugin.test-parse-suite.output.txt"
	td.InsertTempFile(outputFile)

	// Test case 1: Valid suite list and output file
	opts := OptionsParserTestSuite{
		SuiteList:  suiteFile,
		OutputFile: outputFile,
	}
	assert.NoError(t, StartParseParserTestSuite(&opts))

	// Test case 2: Missing suite list
	opts = OptionsParserTestSuite{
		OutputFile: outputFile,
	}
	assert.Error(t, StartParseParserTestSuite(&opts))

	// Test case 3: Invalid suite list
	opts = OptionsParserTestSuite{
		SuiteList:  "invalid.txt",
		OutputFile: outputFile,
	}
	assert.Error(t, StartParseParserTestSuite(&opts))

	// Test case 4: Skipping output file
	opts = OptionsParserTestSuite{
		SuiteList: suiteFile,
	}
	assert.NoError(t, StartParseParserTestSuite(&opts))
}

func TestNewCmdParserTestSuite(t *testing.T) {
	cmd := NewCmdParserTestSuite()
	assert.NotNil(t, cmd)
}
