package plugin

import (
	"fmt"
	"html/template"
	"os"
	"path/filepath"

	log "github.com/sirupsen/logrus"
)

// JUnitTestReport holds the JUnit test report data.
type JUnitTestReport struct {
	Filepath string
	Result   string
	Name     string
	Message  string
}

// JUnitTestReportTemplate is the template for the JUnit test report.
var JUnitTestReportTemplate = `
<testsuite name="opct" tests="1" failures="0" time="0.0">
	<testcase name="{{ .Name }}" time="0.0">
{{- if eq .Result "skipped" }}
	<skipped message="{{ .Message }}"/>
{{- else if eq .Result "failed" }}
	<failure message="{{ .Message }}"/>
{{- end }}
	</testcase>
</testsuite>`

// NewJUnitTestReport creates a new JUnit test report.
func NewJUnitTestReport(in *JUnitTestReport) *JUnitTestReport {
	return &JUnitTestReport{
		Filepath: in.Filepath,
		Result:   in.Result,
		Name:     in.Name,
		Message:  in.Message,
	}
}

// Write writes the JUnit test report to the specified file.
func (j *JUnitTestReport) Write() error {
	tmpl, err := template.New("cmd").Parse(JUnitTestReportTemplate)
	if err != nil {
		return fmt.Errorf("error creating template for run command: %w", err)
	}

	// check if parent directory exists or needs to be created.
	parentDir := filepath.Dir(j.Filepath)
	if _, err := os.Stat(parentDir); os.IsNotExist(err) {
		err := os.MkdirAll(parentDir, os.ModePerm)
		if err != nil {
			return fmt.Errorf("error creating parent directory: %w", err)
		}
	}

	// write JUnit file.
	junitFD, err := os.Create(j.Filepath)
	if err != nil {
		return fmt.Errorf("error creating run file: %w", err)
	}
	defer junitFD.Close()

	err = tmpl.Execute(junitFD, j)
	if err != nil {
		return fmt.Errorf("error rendering template for run command: %w", err)
	}

	log.Infof("JUnit file created at %s", j.Filepath)
	return nil
}
