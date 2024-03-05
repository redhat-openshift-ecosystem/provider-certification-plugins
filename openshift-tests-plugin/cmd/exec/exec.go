package exec

import (
	"os"

	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
)

var execCmd = &cobra.Command{
	Use:   "exec",
	Short: "exec plugin subcommand. [WIP while replacing all plugin functions]",
	Run: func(cmd *cobra.Command, args []string) {
		if len(args) == 0 {
			if err := cmd.Help(); err != nil {
				log.Errorf("one or more errors found: %v", err)
			}
			os.Exit(0)
		}
	},
}

func init() {
	execCmd.AddCommand(NewCmdParserFailres())
	execCmd.AddCommand(NewCmdParserJUnit())
	execCmd.AddCommand(NewCmdParserTestSuite())
	execCmd.AddCommand(NewCmdWaitUpdater())
	execCmd.AddCommand(NewCmdProgressMessage())
	// execCmd.AddCommand(NewCmdWaitForPlugin())
	// execCmd.AddCommand(NewCmdProgressReport())
	// execCmd.AddCommand(NewCmdProgressUpgrade())
}

func NewCmdExec() *cobra.Command {
	return execCmd
}
