package plugin

import (
	"errors"
	"fmt"
	"os"
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
