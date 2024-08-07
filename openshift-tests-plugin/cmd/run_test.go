package cmd

import (
	"fmt"
	"os"
	"testing"

	"github.com/redhat-openshift-ecosystem/provider-certification-plugins/openshift-tests-plugin/pkg/plugin"
	tdata "github.com/redhat-openshift-ecosystem/provider-certification-plugins/openshift-tests-plugin/test"
	log "github.com/sirupsen/logrus"
	"github.com/stretchr/testify/assert"
)

func TestStartRun(t *testing.T) {
	type testCase struct {
		name          string
		opt           *OptionsRun
		expectedError string
		run           func(*testing.T, *testCase)
	}

	td := tdata.NewTestReader()
	defer td.CleanUp()

	createEmptyFile := func(path string) {
		file, err := os.Create(path)
		if err != nil {
			log.Warnf("pre-run: failed to create file: %v", err)
			if err.Error() == "file exists" {
				return
			}
		}
		defer file.Close()
		td.InsertTempFile(path)
	}

	// resolving in-cluster dependency. The KUBECONFIG env var is set in podSpec
	createFakeKubeConfig := func() {
		// Create fake kubeconfig file
		kubeconfigPath := "/tmp/fake.kc"

		// Set environment variable KUBECONFIG
		if err := os.Setenv("KUBECONFIG", kubeconfigPath); err != nil {
			t.Fatalf("pre-run: failed to set KUBECONFIG environment variable: %v", err)
		}
		createEmptyFile(kubeconfigPath)
	}
	createDirectory := func(path string) {
		if err := os.Mkdir(path, 0755); err != nil {
			existsErr := fmt.Sprintf("mkdir %s: file exists", path)
			if err.Error() == existsErr {
				return
			}
			t.Fatalf("pre-run: failed to create dir %s: %v", path, err)
		}
		td.InsertTempFile(plugin.SharedDir)
	}
	removeDirectory := func(path string) {
		err := os.RemoveAll(path)
		if err != nil {
			log.Warnf("post-run: failed to remove dir %s: %v\n", path, err)
		}
	}
	copyFromVFSToFile := func(src, dst string) {
		_, err := td.OpenFileTo(src, dst)
		if err != nil {
			log.Warnf("error retrieving data from VFS[%s]: %v\n", src, err)
		}
	}

	cases := []*testCase{
		{
			name:          "valid input, offline, finish with error, missing JUnit /tmp/shared/junit/junit_e2e_fake.xml",
			expectedError: `error running dependency waiter: error getting Sonobuoy Aggregator API info: sonobuoy client not initialized`,
			opt:           &OptionsRun{Name: plugin.PluginName20},
			run: func(t *testing.T, tc *testCase) {
				tdc := tdata.NewTestReader()
				defer tdc.CleanUp()

				// PreRun
				createFakeKubeConfig()
				defer removeDirectory("/tmp/fake.kc")
				createDirectory(plugin.SharedDir)
				defer removeDirectory(plugin.SharedDir)
				// No copy suite list
				createEmptyFile("/tmp/shared/suite.list.done")
				createEmptyFile("/tmp/shared/done")
				// No create JUnit dir and file

				err := StartRun(tc.opt)
				if err != nil {
					assert.Equal(t, tc.expectedError, err.Error())
				}
				/*
					TODO check:
					- fifo exists
					- /tmp/shared/start was created
					- /tmp/sonobuoy/results/junit_e2e_test.xml
					- /tmp/failures-20-suite.txt exists
				*/
			},
		},
		{
			name:          "valid input, offline, finish with error, missing test list /tmp/shared/suite.list",
			opt:           &OptionsRun{Name: plugin.PluginName20},
			expectedError: `error running dependency waiter: error getting Sonobuoy Aggregator API info: sonobuoy client not initialized`,
			run: func(t *testing.T, tc *testCase) {
				tdc := tdata.NewTestReader()
				defer tdc.CleanUp()

				// PreRun
				createFakeKubeConfig()
				defer removeDirectory("/tmp/fake.kc")
				createDirectory(plugin.SharedDir)
				defer removeDirectory(plugin.SharedDir)
				copyFromVFSToFile("testdata/suites/suite10.list", "/tmp/shared/suite.list")
				createEmptyFile("/tmp/shared/suite.list.done")
				createEmptyFile("/tmp/shared/done")
				createDirectory("/tmp/shared/junit")
				copyFromVFSToFile("testdata/suites/junit5.xml", "/tmp/shared/junit/junit_e2e_test.xml")

				err := StartRun(tc.opt)
				if err != nil {
					assert.Equal(t, tc.expectedError, err.Error())
				}
				/*
					TODO check:
					- fifo exists
					- /tmp/shared/start was created
					- /tmp/sonobuoy/results/junit_e2e_test.xml
					- /tmp/failures-20-suite.txt exists
				*/
			},
		},
		// TODO: add more test cases
		// TODO: create success test cases, need to woraround required APIs (kube, SB, etc)
		// {
		// 	name:          "valid input, offline, finish with error, init",
		// 	expectedError: `run command finished with errors: error processing JUnits: no XML files found`,
		// },
		// {
		// 	// then cp test/testdata/suites/suite10.list /tmp/shared/suite.list
		// 	name:          "valid input, offline, finish with error, missing kubernetes clients (as expected)",
		// 	expectedError: `run command finished with errors: error processing JUnits: error saving to ConfigMap: kubernetes client not initialized`,
		// 	// expect files:
		// 	run: func(t *testing.T, tc *testCase) {
		// 		fmt.Println("TODO")
		// 	},
		// },
		// {
		// 	name: "valid input, error normal flow without cluster endpoint, fake files",
		// 	opt: &OptionsRun{
		// 		Name: "pluginName",
		// 		ID:   "pluginId",
		// 	},
		// {
		// 	name: "invalid plugin name",
		// 	opt: &OptionsRun{
		// 		Name: "invalidPluginName",
		// 		ID:   "pluginId",
		// 	},
		// 	expectedError: "plugin name not found: plugin not found",
		// 	run: func(t *testing.T, tc *testCase) {
		// 		err := StartRun(tc.opt)
		// 		if err == nil {
		// 			t.Errorf("expected error, got nil")
		// 		}
		// 	},
		// },
		// {
		// 	name: "invalid plugin id",
		// 	opt: &OptionsRun{
		// 		Name: "pluginName",
		// 		ID:   "invalidPluginId",
		// 	},
		// 	expectedError: "plugin name not found: plugin not found",
		// 	run: func(t *testing.T, tc *testCase) {
		// 		err := StartRun(tc.opt)
		// 		if err == nil {
		// 			t.Errorf("expected error, got nil")
		// 		}
		// 	},
		// },
		// {
		// 	name: "invalid plugin name and id",
		// 	opt: &OptionsRun{
		// 		Name: "invalidPluginName",
		// 		ID:   "invalidPluginId",
		// 	},

		// 	expectedError: "plugin name not found: plugin not found",
		// 	run: func(t *testing.T, tc *testCase) {
		// 		err := StartRun(tc.opt)
		// 		if err == nil {
		// 			t.Errorf("expected error, got nil")
		// 		}
		// 	},
		// },
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			tc.run(t, tc)
		})
	}
}
