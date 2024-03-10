package exec

import (
	"os"
	"time"

	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
)

// TODO Progress Upgrade

type OptionProgressMessage struct {
	Message string
}

func NewCmdProgressMessage() *cobra.Command {

	opts := OptionProgressMessage{}

	cmd := &cobra.Command{
		Use:   "progress-msg",
		Short: "Send standalone progress message to worker API",
		Long:  ``,
		Run: func(cmd *cobra.Command, args []string) {
			StartProgressMessage(&opts)
		},
	}

	cmd.Flags().StringVar(&opts.Message, "message", "", "Message to send")

	return cmd
}

func StartProgressMessage(opts *OptionProgressMessage) error {

	if opts.Message == "" {
		log.Error("Invalid empty message")
		os.Exit(1)
	}

	progressReportSendUpdate(&ProgressReport{}, opts.Message)
	time.Sleep(10 * time.Second)

	return nil
}
