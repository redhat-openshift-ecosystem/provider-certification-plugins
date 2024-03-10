package exec

import (
	"os"

	"github.com/spf13/cobra"
)

var execCmd = &cobra.Command{
	Use:   "exec",
	Short: "exec plugin subcommand. [WIP while replacing all plugin functions]",
	Run: func(cmd *cobra.Command, args []string) {
		if len(args) == 0 {
			cmd.Help()
			os.Exit(0)
		}
	},
}

func init() {
	execCmd.AddCommand(NewCmdWaitForPlugin())
	execCmd.AddCommand(NewCmdParserFailres())
	execCmd.AddCommand(NewCmdProgressReport())
	execCmd.AddCommand(NewCmdWaitUpdater())

}

func NewCmdExec() *cobra.Command {
	return execCmd
}
