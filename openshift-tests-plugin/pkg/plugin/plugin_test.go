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
