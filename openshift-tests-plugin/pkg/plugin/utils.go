package plugin

import (
	"errors"
	"os"
	"time"

	log "github.com/sirupsen/logrus"
)

// watchForFile watches for a file to be created and calls the doneCallback when it is ready.
func watchForFile(filePath string, doneCallback func()) error {
	for {
		if _, err := os.Stat(filePath); err == nil {
			log.Infof("Detected file [%s], running callback.", filePath)
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
