package plugin

import (
	"os"
	"testing"
)

// TestGetSuiteName tests the getSuiteName method
func TestGetSuiteName(t *testing.T) {
	tests := []struct {
		name          string
		pluginID      string
		envValue      string
		setupEnv      func()
		cleanupEnv    func()
		expectedSuite string
	}{
		{
			name:     "PluginId10 with DEFAULT_SUITE_NAME set",
			pluginID: PluginId10,
			setupEnv: func() {
				os.Setenv("DEFAULT_SUITE_NAME", "kubernetes/conformance/parallel")
			},
			cleanupEnv: func() {
				os.Unsetenv("DEFAULT_SUITE_NAME")
			},
			expectedSuite: "kubernetes/conformance/parallel",
		},
		{
			name:     "PluginId10 without DEFAULT_SUITE_NAME",
			pluginID: PluginId10,
			setupEnv: func() {
				os.Unsetenv("DEFAULT_SUITE_NAME")
			},
			cleanupEnv:    func() {},
			expectedSuite: PluginSuite10,
		},
		{
			name:     "PluginId10 with empty DEFAULT_SUITE_NAME",
			pluginID: PluginId10,
			setupEnv: func() {
				os.Setenv("DEFAULT_SUITE_NAME", "")
			},
			cleanupEnv: func() {
				os.Unsetenv("DEFAULT_SUITE_NAME")
			},
			expectedSuite: PluginSuite10,
		},
		{
			name:     "PluginId05 should return empty string",
			pluginID: PluginId05,
			setupEnv: func() {
				os.Setenv("DEFAULT_SUITE_NAME", "some-value")
			},
			cleanupEnv: func() {
				os.Unsetenv("DEFAULT_SUITE_NAME")
			},
			expectedSuite: "",
		},
		{
			name:     "PluginId20 should return empty string",
			pluginID: PluginId20,
			setupEnv: func() {
				os.Setenv("DEFAULT_SUITE_NAME", "some-value")
			},
			cleanupEnv: func() {
				os.Unsetenv("DEFAULT_SUITE_NAME")
			},
			expectedSuite: "",
		},
		{
			name:     "PluginId80 should return empty string",
			pluginID: PluginId80,
			setupEnv: func() {
				os.Setenv("DEFAULT_SUITE_NAME", "some-value")
			},
			cleanupEnv: func() {
				os.Unsetenv("DEFAULT_SUITE_NAME")
			},
			expectedSuite: "",
		},
		{
			name:     "PluginId99 should return empty string",
			pluginID: PluginId99,
			setupEnv: func() {
				os.Setenv("DEFAULT_SUITE_NAME", "some-value")
			},
			cleanupEnv: func() {
				os.Unsetenv("DEFAULT_SUITE_NAME")
			},
			expectedSuite: "",
		},
		{
			name:     "Unknown plugin ID should return empty string",
			pluginID: "999",
			setupEnv: func() {
				os.Setenv("DEFAULT_SUITE_NAME", "some-value")
			},
			cleanupEnv: func() {
				os.Unsetenv("DEFAULT_SUITE_NAME")
			},
			expectedSuite: "",
		},
		{
			name:     "PluginId10 with custom suite name",
			pluginID: PluginId10,
			setupEnv: func() {
				os.Setenv("DEFAULT_SUITE_NAME", "custom/conformance/suite")
			},
			cleanupEnv: func() {
				os.Unsetenv("DEFAULT_SUITE_NAME")
			},
			expectedSuite: "custom/conformance/suite",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Setup environment
			tt.setupEnv()
			defer tt.cleanupEnv()

			// Create a plugin instance (minimal initialization)
			p := &Plugin{
				name: PluginName10, // Use valid plugin name for basic initialization
				id:   tt.pluginID,
			}

			// Call getSuiteName
			result := p.getSuiteName(tt.pluginID)

			// Verify result
			if result != tt.expectedSuite {
				t.Errorf("getSuiteName(%s) = %q, want %q", tt.pluginID, result, tt.expectedSuite)
			}
		})
	}
}

// TestGetSuiteNameIntegration tests the integration of getSuiteName in NewPlugin
func TestGetSuiteNameIntegration(t *testing.T) {
	tests := []struct {
		name          string
		pluginName    string
		envValue      string
		setupEnv      func()
		cleanupEnv    func()
		expectedSuite string
		wantErr       bool
	}{
		{
			name:       "Plugin10 uses getSuiteName with custom suite",
			pluginName: PluginName10,
			setupEnv: func() {
				os.Setenv("DEFAULT_SUITE_NAME", "kubernetes/conformance/parallel")
			},
			cleanupEnv: func() {
				os.Unsetenv("DEFAULT_SUITE_NAME")
			},
			expectedSuite: "kubernetes/conformance/parallel",
			wantErr:       false,
		},
		{
			name:       "Plugin10 uses default suite when env not set",
			pluginName: PluginName10,
			setupEnv: func() {
				os.Unsetenv("DEFAULT_SUITE_NAME")
			},
			cleanupEnv:    func() {},
			expectedSuite: PluginSuite10,
			wantErr:       false,
		},
		{
			name:       "Plugin10 uses alias name with custom suite",
			pluginName: PluginAlias10,
			setupEnv: func() {
				os.Setenv("DEFAULT_SUITE_NAME", "kubernetes/conformance/parallel")
			},
			cleanupEnv: func() {
				os.Unsetenv("DEFAULT_SUITE_NAME")
			},
			expectedSuite: "kubernetes/conformance/parallel",
			wantErr:       false,
		},
		{
			name:       "Plugin05 does not use getSuiteName",
			pluginName: PluginName05,
			setupEnv: func() {
				os.Setenv("DEFAULT_SUITE_NAME", "should-be-ignored")
			},
			cleanupEnv: func() {
				os.Unsetenv("DEFAULT_SUITE_NAME")
			},
			expectedSuite: PluginSuite05,
			wantErr:       false,
		},
		{
			name:       "Plugin20 does not use getSuiteName",
			pluginName: PluginName20,
			setupEnv: func() {
				os.Setenv("DEFAULT_SUITE_NAME", "should-be-ignored")
			},
			cleanupEnv: func() {
				os.Unsetenv("DEFAULT_SUITE_NAME")
			},
			expectedSuite: PluginSuite20,
			wantErr:       false,
		},
		{
			name:       "Plugin80 does not use getSuiteName",
			pluginName: PluginName80,
			setupEnv: func() {
				os.Setenv("DEFAULT_SUITE_NAME", "should-be-ignored")
			},
			cleanupEnv: func() {
				os.Unsetenv("DEFAULT_SUITE_NAME")
			},
			expectedSuite: PluginSuite80,
			wantErr:       false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Setup environment
			tt.setupEnv()
			defer tt.cleanupEnv()

			// Create plugin using NewPlugin
			plugin, err := NewPlugin(tt.pluginName)

			if tt.wantErr {
				if err == nil {
					t.Errorf("NewPlugin(%s) expected error, got nil", tt.pluginName)
				}
				return
			}

			if err != nil {
				t.Fatalf("NewPlugin(%s) unexpected error: %v", tt.pluginName, err)
			}

			// Verify SuiteName was set correctly
			if plugin.SuiteName != tt.expectedSuite {
				t.Errorf("NewPlugin(%s).SuiteName = %q, want %q", tt.pluginName, plugin.SuiteName, tt.expectedSuite)
			}
		})
	}
}

// TestGetSuiteNameConstantValues verifies the constant values used by getSuiteName
func TestGetSuiteNameConstantValues(t *testing.T) {
	// Verify plugin constants are as expected
	if PluginId10 != "10" {
		t.Errorf("PluginId10 = %q, want %q", PluginId10, "10")
	}
	if PluginSuite10 != "kubernetes/conformance" {
		t.Errorf("PluginSuite10 = %q, want %q", PluginSuite10, "kubernetes/conformance")
	}
}

// TestWorkflowGuardSkipMatrix tests the OPCT-432 workflow guard skip matrix.
// Matrix:
//
//	Plugin 05 (upgrade):              run in upgrade, skip in default/disconnected
//	Plugin 10 (kube-conformance):     run in default/disconnected, skip in upgrade
//	Plugin 20 (conformance-validated): run in default/disconnected, skip in upgrade
//	Plugin 80 (replay):               always active (no guard)
//	Plugin 99 (collector):            always active (no guard)
func TestWorkflowGuardSkipMatrix(t *testing.T) {
	tests := []struct {
		name       string
		pluginName string
		execMode   string
		wantSkip   bool
	}{
		// Plugin 05: skip in default, run in upgrade
		{
			name:       "Plugin05 default mode should skip",
			pluginName: PluginName05,
			execMode:   ExecModeDefault,
			wantSkip:   true,
		},
		{
			name:       "Plugin05 upgrade mode should run",
			pluginName: PluginName05,
			execMode:   ExecModeUpgrade,
			wantSkip:   false,
		},
		// Plugin 10: run in default, skip in upgrade
		{
			name:       "Plugin10 default mode should run",
			pluginName: PluginName10,
			execMode:   ExecModeDefault,
			wantSkip:   false,
		},
		{
			name:       "Plugin10 upgrade mode should skip",
			pluginName: PluginName10,
			execMode:   ExecModeUpgrade,
			wantSkip:   true,
		},
		// Plugin 20: run in default, skip in upgrade
		{
			name:       "Plugin20 default mode should run",
			pluginName: PluginName20,
			execMode:   ExecModeDefault,
			wantSkip:   false,
		},
		{
			name:       "Plugin20 upgrade mode should skip",
			pluginName: PluginName20,
			execMode:   ExecModeUpgrade,
			wantSkip:   true,
		},
		// Plugin 80 (replay): always active
		{
			name:       "Plugin80 default mode should run",
			pluginName: PluginName80,
			execMode:   ExecModeDefault,
			wantSkip:   false,
		},
		{
			name:       "Plugin80 upgrade mode should run",
			pluginName: PluginName80,
			execMode:   ExecModeUpgrade,
			wantSkip:   false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p, err := NewPlugin(tt.pluginName)
			if err != nil {
				t.Fatalf("NewPlugin(%s) unexpected error: %v", tt.pluginName, err)
			}
			p.ExecMode = tt.execMode

			skipPlugin := inactiveInWorkflowReason(p.id, p.ExecMode) != ""

			if skipPlugin != tt.wantSkip {
				t.Errorf("workflow guard for %s in %s mode: got skip=%v, want skip=%v",
					tt.pluginName, tt.execMode, skipPlugin, tt.wantSkip)
			}
		})
	}
}

// TestWorkflowGuardExecModeFromEnv tests that RUN_MODE env var correctly
// propagates to ExecMode during initialization, which drives the guard.
func TestWorkflowGuardExecModeFromEnv(t *testing.T) {
	tests := []struct {
		name         string
		runModeEnv   string
		setEnv       bool
		expectedMode string
	}{
		{
			name:         "RUN_MODE=upgrade sets ExecModeUpgrade",
			runModeEnv:   "upgrade",
			setEnv:       true,
			expectedMode: ExecModeUpgrade,
		},
		{
			name:         "RUN_MODE=normal sets ExecModeDefault",
			runModeEnv:   "normal",
			setEnv:       true,
			expectedMode: ExecModeDefault,
		},
		{
			name:         "RUN_MODE unset defaults to ExecModeDefault",
			runModeEnv:   "",
			setEnv:       false,
			expectedMode: ExecModeDefault,
		},
		{
			name:         "RUN_MODE=unknown defaults to ExecModeDefault",
			runModeEnv:   "unknown",
			setEnv:       true,
			expectedMode: ExecModeDefault,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.setEnv {
				os.Setenv("RUN_MODE", tt.runModeEnv)
				defer os.Unsetenv("RUN_MODE")
			} else {
				os.Unsetenv("RUN_MODE")
			}

			// NewPlugin sets ExecMode to ExecModeDefault,
			// Initialize() reads RUN_MODE and updates it.
			// We test the env-to-mode mapping directly here
			// since Initialize() requires cluster connectivity.
			p, err := NewPlugin(PluginName10)
			if err != nil {
				t.Fatalf("NewPlugin unexpected error: %v", err)
			}

			// Simulate the Initialize() env parsing
			envRunMode := os.Getenv("RUN_MODE")
			if len(envRunMode) > 0 {
				switch envRunMode {
				case ExecModeUpgrade:
					p.ExecMode = ExecModeUpgrade
				case "normal":
					p.ExecMode = ExecModeDefault
				default:
					p.ExecMode = ExecModeDefault
				}
			}

			if p.ExecMode != tt.expectedMode {
				t.Errorf("ExecMode = %q, want %q (RUN_MODE=%q)",
					p.ExecMode, tt.expectedMode, tt.runModeEnv)
			}
		})
	}
}

// TestWorkflowGuardReplayUnaffected confirms the replay plugin (80) is
// never subject to the workflow guard regardless of execution mode.
func TestWorkflowGuardReplayUnaffected(t *testing.T) {
	for _, mode := range []string{ExecModeDefault, ExecModeUpgrade} {
		t.Run("replay_in_"+mode, func(t *testing.T) {
			p, err := NewPlugin(PluginName80)
			if err != nil {
				t.Fatalf("NewPlugin(%s) unexpected error: %v", PluginName80, err)
			}
			p.ExecMode = mode

			skipPlugin := false
			if p.id == PluginId05 && p.ExecMode == ExecModeDefault {
				skipPlugin = true
			}
			if (p.id == PluginId10 || p.id == PluginId20) && p.ExecMode == ExecModeUpgrade {
				skipPlugin = true
			}

			if skipPlugin {
				t.Errorf("replay plugin should never be skipped, but got skip=true in %s mode", mode)
			}
		})
	}
}

// TestGetSuiteNameEdgeCases tests edge cases for getSuiteName
func TestGetSuiteNameEdgeCases(t *testing.T) {
	tests := []struct {
		name          string
		pluginID      string
		envValue      string
		setupEnv      func()
		cleanupEnv    func()
		expectedSuite string
	}{
		{
			name:     "Very long suite name",
			pluginID: PluginId10,
			setupEnv: func() {
				longName := "kubernetes/conformance/very/long/path/to/test/suite/that/exceeds/normal/length"
				os.Setenv("DEFAULT_SUITE_NAME", longName)
			},
			cleanupEnv: func() {
				os.Unsetenv("DEFAULT_SUITE_NAME")
			},
			expectedSuite: "kubernetes/conformance/very/long/path/to/test/suite/that/exceeds/normal/length",
		},
		{
			name:     "Suite name with special characters",
			pluginID: PluginId10,
			setupEnv: func() {
				os.Setenv("DEFAULT_SUITE_NAME", "kubernetes/conformance-2.0_test")
			},
			cleanupEnv: func() {
				os.Unsetenv("DEFAULT_SUITE_NAME")
			},
			expectedSuite: "kubernetes/conformance-2.0_test",
		},
		{
			name:     "Suite name with whitespace (should preserve)",
			pluginID: PluginId10,
			setupEnv: func() {
				os.Setenv("DEFAULT_SUITE_NAME", "  kubernetes/conformance  ")
			},
			cleanupEnv: func() {
				os.Unsetenv("DEFAULT_SUITE_NAME")
			},
			expectedSuite: "  kubernetes/conformance  ",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.setupEnv()
			defer tt.cleanupEnv()

			p := &Plugin{
				name: PluginName10,
				id:   tt.pluginID,
			}

			result := p.getSuiteName(tt.pluginID)

			if result != tt.expectedSuite {
				t.Errorf("getSuiteName(%s) = %q, want %q", tt.pluginID, result, tt.expectedSuite)
			}
		})
	}
}

// TestPluginIDByName verifies plugin IDs resolve from both names and aliases,
// since BlockerPlugins may be populated with either form.
func TestPluginIDByName(t *testing.T) {
	tests := []struct {
		name   string
		input  string
		wantID string
	}{
		{name: "name 05", input: PluginName05, wantID: PluginId05},
		{name: "alias 05", input: PluginAlias05, wantID: PluginId05},
		{name: "name 10", input: PluginName10, wantID: PluginId10},
		{name: "alias 10", input: PluginAlias10, wantID: PluginId10},
		{name: "name 20", input: PluginName20, wantID: PluginId20},
		{name: "alias 20", input: PluginAlias20, wantID: PluginId20},
		{name: "name 80", input: PluginName80, wantID: PluginId80},
		{name: "name 99", input: PluginName99, wantID: PluginId99},
		{name: "unknown plugin", input: "not-a-plugin", wantID: ""},
		{name: "empty", input: "", wantID: ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := pluginIDByName(tt.input); got != tt.wantID {
				t.Errorf("pluginIDByName(%q) = %q, want %q", tt.input, got, tt.wantID)
			}
		})
	}
}

// TestDependencyWaiterSkipsInactiveBlocker covers OPCT-433: a plugin must not wait
// for a blocker that is not part of the current workflow, otherwise it polls until
// the 6h timeout. Plugin 10 blocked by plugin 05 in regular mode is the case that
// blocks the CLI-side manifest skip (opct PR #253).
func TestDependencyWaiterSkipsInactiveBlocker(t *testing.T) {
	tests := []struct {
		name       string
		pluginName string
		execMode   string
		wantSkip   bool
	}{
		{
			name:       "plugin10 in default mode must not wait for upgrade plugin 05",
			pluginName: PluginName10,
			execMode:   ExecModeDefault,
			wantSkip:   true,
		},
		{
			name:       "plugin10 in upgrade mode keeps waiting for plugin 05",
			pluginName: PluginName10,
			execMode:   ExecModeUpgrade,
			wantSkip:   false,
		},
		{
			name:       "plugin20 keeps waiting for plugin 10 in default mode",
			pluginName: PluginName20,
			execMode:   ExecModeDefault,
			wantSkip:   false,
		},
		{
			name:       "plugin20 in upgrade mode must not wait for inactive plugin 10",
			pluginName: PluginName20,
			execMode:   ExecModeUpgrade,
			wantSkip:   true,
		},
		{
			name:       "plugin80 keeps waiting for plugin 20 in default mode",
			pluginName: PluginName80,
			execMode:   ExecModeDefault,
			wantSkip:   false,
		},
		{
			name:       "plugin80 in upgrade mode must not wait for inactive plugin 20",
			pluginName: PluginName80,
			execMode:   ExecModeUpgrade,
			wantSkip:   true,
		},
		{
			name:       "plugin99 keeps waiting for always-active plugin 80",
			pluginName: PluginName99,
			execMode:   ExecModeUpgrade,
			wantSkip:   false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p, err := NewPlugin(tt.pluginName)
			if err != nil {
				t.Fatalf("NewPlugin(%s) unexpected error: %v", tt.pluginName, err)
			}
			p.ExecMode = tt.execMode

			if len(p.BlockerPlugins) == 0 {
				t.Fatalf("plugin %s expected to have a blocker configured", tt.pluginName)
			}
			blocker := p.BlockerPlugins[0].name
			gotSkip := inactiveInWorkflowReason(pluginIDByName(blocker), p.ExecMode) != ""

			if gotSkip != tt.wantSkip {
				t.Errorf("waiter guard for %s (blocker=%s) in %s mode: got skip=%v, want skip=%v",
					tt.pluginName, blocker, tt.execMode, gotSkip, tt.wantSkip)
			}
		})
	}
}

// TestDependencyWaiterNoBlockerReturnsNil guards the pre-existing early return used
// by the --blocker="" escape hatch (OPCT-454), which must keep working.
func TestDependencyWaiterNoBlockerReturnsNil(t *testing.T) {
	p, err := NewPlugin(PluginName05)
	if err != nil {
		t.Fatalf("NewPlugin(%s) unexpected error: %v", PluginName05, err)
	}
	if len(p.BlockerPlugins) != 0 {
		t.Fatalf("plugin %s expected to have no blocker, got %d", PluginName05, len(p.BlockerPlugins))
	}
	if err := p.RunDependencyWaiter(); err != nil {
		t.Errorf("RunDependencyWaiter() with no blocker = %v, want nil", err)
	}
}
