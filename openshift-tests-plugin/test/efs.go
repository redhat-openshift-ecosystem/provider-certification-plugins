package tdata

import (
	"embed"
	"fmt"
	"os"
)

//go:embed testdata/*
var TestData embed.FS

// WriteData writes data to the temp directory.
func WriteData(data []byte, dest string) (string, error) {
	// if dest is empty create temp file and return it.
	if len(dest) == 0 {
		// Create a temporary file in the temp directory
		tmpFile, err := os.CreateTemp("/tmp", "opct-plugin-test-")
		if err != nil {
			return "", fmt.Errorf("unable to create temporary file: %v", err)
		}
		defer tmpFile.Close()

		// Write the data to the temporary file
		if _, err := tmpFile.Write(data); err != nil {
			return "", fmt.Errorf("unable to write data to path %s: %v", tmpFile.Name(), err)
		}

		return tmpFile.Name(), nil
	}

	// Write the data to the specified file
	file, err := os.Create(dest)
	if err != nil {
		return "", fmt.Errorf("unable to create file at path %s: %v", dest, err)
	}
	defer file.Close()

	if _, err := file.Write(data); err != nil {
		return "", fmt.Errorf("unable to write data to file at path %s: %v", dest, err)
	}

	return dest, nil
}

type TestReader struct {
	TempFiles []string
}

func NewTestReader() *TestReader {
	return &TestReader{}
}

func (tr *TestReader) OpenFile(path string) (string, error) {
	vfsData, err := TestData.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("error reading suite list data from VFS[%s]: %v", path, err)
	}
	suiteFile, err := WriteData(vfsData, "")
	if err != nil {
		return "", fmt.Errorf("error writing suite list from VFS[%s] to file: %v", suiteFile, err)
	}
	tr.TempFiles = append(tr.TempFiles, suiteFile)
	return suiteFile, nil
}

func (tr *TestReader) OpenFileTo(path, dest string) (string, error) {
	vfsData, err := TestData.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("error reading suite list data from VFS[%s]: %v", path, err)
	}
	suiteFile, err := WriteData(vfsData, dest)
	if err != nil {
		return "", fmt.Errorf("error writing suite list from VFS[%s] to file: %v", suiteFile, err)
	}
	tr.TempFiles = append(tr.TempFiles, suiteFile)
	return suiteFile, nil
}

func (tr *TestReader) CleanUp() {
	for _, file := range tr.TempFiles {
		err := os.Remove(file)
		if err != nil {
			fmt.Printf("error removing file[%s]: %v", file, err)
		}
	}
}

func (tr *TestReader) InsertTempFile(file string) {
	tr.TempFiles = append(tr.TempFiles, file)
}
