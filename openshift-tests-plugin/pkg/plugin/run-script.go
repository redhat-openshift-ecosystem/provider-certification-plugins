package plugin

import (
	"fmt"
	"html/template"
	"os"

	log "github.com/sirupsen/logrus"
)

const OpenShiftTestsBinPath = "/usr/bin/openshift-tests"

type OpenShiftTestsRunCommand struct {
	BinPath      string
	Command      string
	SuiteName    string
	Monitortests string
	MaxParallel  string
	JUnitDir     string
	FiFoPath     string
	ToImage      string
	Options      string
	File         string
}

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
{{- if .Options }}
  --options="{{ .Options }}" \
{{- end}}
{{- if .File }}
  --file="{{ .File }}" \
{{- end}}
  | tee -a {{ .FiFoPath }} || true
`

func NewOpenShiftRunCommand(command, suiteName string) *OpenShiftTestsRunCommand {
	return &OpenShiftTestsRunCommand{
		BinPath:      OpenShiftTestsBinPath,
		Command:      command,
		SuiteName:    suiteName,
		FiFoPath:     FiFoPath,
		JUnitDir:     OpenShiftTestsJUnitDir,
		Monitortests: DefaultOpenShiftTestsRunMonitors,
		MaxParallel:  DefaultOpenShiftTestsRunMaxParallel,
	}
}

func (ocmd *OpenShiftTestsRunCommand) Create() error {
	runFile, err := os.Create(OpenShiftTestsRunFile)
	if err != nil {
		return fmt.Errorf("error creating run file: %w", err)
	}
	defer runFile.Close()

	tmpl, err := template.New("cmd").Parse(OpenShiftTestsRunBaseTemplate)
	if err != nil {
		return fmt.Errorf("error creating template for run command: %w", err)
	}
	err = tmpl.Execute(runFile, ocmd)
	if err != nil {
		return fmt.Errorf("error rendering template for run command: %w", err)
	}

	log.Printf("Run file created at %s\n", OpenShiftTestsRunFile)
	return nil
}
