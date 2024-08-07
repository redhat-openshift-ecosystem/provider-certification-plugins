package plugin

import (
	"fmt"
	"html/template"
	"os"

	log "github.com/sirupsen/logrus"
)

// OpenShiftTestsBinPath is the binary path for openshift-tests.
const OpenShiftTestsBinPath = "/usr/bin/openshift-tests"

// OpenShiftTestsRunFile holds the openshift-tests command options to create run/start script.
type OpenShiftTestsRunCommand struct {
	BinPath        string
	Command        string
	SuiteName      string
	Monitortests   string
	MaxParallel    string
	JUnitDir       string
	FiFoPath       string
	ToImage        string
	FromRepository string
	Options        string
	File           string
}

// OpenShiftTestsRunBaseTemplate is the template for the run the openshift-tests command.
var OpenShiftTestsRunBaseTemplate = `
{{ .BinPath }} {{ .Command }} {{ .SuiteName }} \
  --junit-dir="{{ .JUnitDir }}" \
  --max-parallel-tests="{{ .MaxParallel }}" \
{{- if .Monitortests }}
  --monitor="{{ .Monitortests }}" \
{{- end}}
{{- if .ToImage }}
  --to-image="{{ .ToImage }}" \
{{- end}}
{{- if .FromRepository }}
  --from-repository="{{ .FromRepository }}" \
{{- end}}
{{- if .Options }}
  --options="{{ .Options }}" \
{{- end}}
{{- if .File }}
  --file="{{ .File }}" \
{{- end}}
  | tee -a {{ .FiFoPath }} || true
`

// NewOpenShiftRunCommand creates a new OpenShiftTestsRunCommand wraper.
func NewOpenShiftRunCommand(command, suiteName string) *OpenShiftTestsRunCommand {
	return &OpenShiftTestsRunCommand{
		BinPath:      OpenShiftTestsBinPath,
		Command:      command,
		SuiteName:    suiteName,
		JUnitDir:     OpenShiftTestsJUnitDir,
		MaxParallel:  DefaultOpenShiftTestsRunMaxParallel,
		Monitortests: DefaultOpenShiftTestsRunMonitors,
		FiFoPath:     FiFoPath,
	}
}

// Create creates run/start script for openshift-tests.
func (ocmd *OpenShiftTestsRunCommand) Create() error {
	tmpl, err := template.New("cmd").Parse(OpenShiftTestsRunBaseTemplate)
	if err != nil {
		return fmt.Errorf("error creating template for run command: %w", err)
	}

	runFile, err := os.Create(OpenShiftTestsRunFile)
	if err != nil {
		return fmt.Errorf("error creating run file: %w", err)
	}
	defer runFile.Close()

	err = tmpl.Execute(runFile, ocmd)
	if err != nil {
		return fmt.Errorf("error rendering template for run command: %w", err)
	}

	log.Infof("Run file created at %s", OpenShiftTestsRunFile)
	return nil
}

// CreateSkip creates skip test on run/start script.
func (ocmd *OpenShiftTestsRunCommand) CreateSkip() error {
	SkipScript := `echo "skipped: (0.0s) 2024-07-05T20:27:49 \"[opct] openshift-tests runner\"" | tee -a {{ .FiFoPath }} || true`
	tmpl, err := template.New("cmd").Parse(SkipScript)
	if err != nil {
		return fmt.Errorf("error creating template for run command: %w", err)
	}

	runFile, err := os.Create(OpenShiftTestsRunFile)
	if err != nil {
		return fmt.Errorf("error creating run file: %w", err)
	}
	defer runFile.Close()

	err = tmpl.Execute(runFile, ocmd)
	if err != nil {
		return fmt.Errorf("error rendering template for run command: %w", err)
	}

	log.Infof("Run file created at %s", OpenShiftTestsRunFile)
	return nil
}
