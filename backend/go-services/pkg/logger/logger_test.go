package logger

import (
	"bytes"
	"log"
	"strings"
	"testing"
)

func TestInitAndLevelString(t *testing.T) {
	Init("debug")
	if got := LevelString(); got != "debug" {
		t.Fatalf("LevelString() = %q, want %q", got, "debug")
	}
	Init("WARN")
	if got := LevelString(); got != "warn" {
		t.Fatalf("LevelString() = %q, want %q", got, "warn")
	}
	Init("Error")
	if got := LevelString(); got != "error" {
		t.Fatalf("LevelString() = %q, want %q", got, "error")
	}
	Init("nonsense")
	if got := LevelString(); got != "info" {
		t.Fatalf("LevelString() = %q, want %q for unknown input", got, "info")
	}
}

func TestLevelFilteringAndPrintln(t *testing.T) {
	// capture output by replacing package logger
	var buf bytes.Buffer
	orig := logger
	logger = log.New(&buf, "", 0)
	defer func() { logger = orig }()

	Init("warn")
	Debugf("debug-msg")
	Infof("info-msg")
	Warnf("warn-msg")
	Errorf("error-msg")

	out := buf.String()
	if strings.Contains(out, "debug-msg") {
		t.Fatalf("debug messages should be suppressed at warn level")
	}
	if strings.Contains(out, "info-msg") {
		t.Fatalf("info messages should be suppressed at warn level")
	}
	if !strings.Contains(out, "warn-msg") {
		t.Fatalf("warn message missing: %q", out)
	}
	if !strings.Contains(out, "error-msg") {
		t.Fatalf("error message missing: %q", out)
	}

	// Test Println maps to info and is suppressed at warn
	buf.Reset()
	Println("hello")
	if strings.Contains(buf.String(), "hello") {
		t.Fatalf("Println should be suppressed at warn level")
	}

	// at info level Println should appear
	Init("info")
	buf.Reset()
	Println("hello")
	if !strings.Contains(buf.String(), "hello") {
		t.Fatalf("Println expected at info level, got: %q", buf.String())
	}
}
