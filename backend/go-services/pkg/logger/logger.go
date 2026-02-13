package logger

import (
	"fmt"
	"log"
	"os"
	"strings"
	"sync"
	"time"
)

// Minimal leveled logger used by the auth service.
// - zero external deps
// - provides Debug/Info/Warn/Error/Fatal variants and Init(level)

type Level int

const (
	LevelDebug Level = iota
	LevelInfo
	LevelWarn
	LevelError
	LevelFatal
)

var (
	mu     sync.RWMutex
	logger *log.Logger = log.New(os.Stdout, "", 0)
	level  Level       = LevelInfo
)

// Init sets the global log level (case-insensitive: debug, info, warn, error, fatal).
// Call early during startup. Default level is Info.
func Init(l string) {
	mu.Lock()
	defer mu.Unlock()
	s := strings.ToLower(strings.TrimSpace(l))
	switch s {
	case "debug":
		level = LevelDebug
	case "warn", "warning":
		level = LevelWarn
	case "error":
		level = LevelError
	case "fatal":
		level = LevelFatal
	default:
		level = LevelInfo
	}
}

func header(lvl string) string {
	return fmt.Sprintf("%s [%s] ", time.Now().Format(time.RFC3339), strings.ToUpper(lvl))
}

func shouldLog(l Level) bool {
	mu.RLock()
	defer mu.RUnlock()
	return l >= level
}

func Debugf(format string, v ...interface{}) {
	if !shouldLog(LevelDebug) {
		return
	}
	logger.Printf(header("debug")+format, v...)
}

func Infof(format string, v ...interface{}) {
	if !shouldLog(LevelInfo) {
		return
	}
	logger.Printf(header("info")+format, v...)
}

func Warnf(format string, v ...interface{}) {
	if !shouldLog(LevelWarn) {
		return
	}
	logger.Printf(header("warn")+format, v...)
}

func Errorf(format string, v ...interface{}) {
	if !shouldLog(LevelError) {
		return
	}
	logger.Printf(header("error")+format, v...)
}

func Fatalf(format string, v ...interface{}) {
	logger.Printf(header("fatal")+format, v...)
	os.Exit(1)
}

// Println kept for brief messages (maps to Info)
func Println(v ...interface{}) {
	if !shouldLog(LevelInfo) {
		return
	}
	logger.Print(header("info") + fmt.Sprintln(v...))
}

// Debug/Info/Warn/Error helpers that accept a single string
func Debug(v string) { Debugf("%s", v) }
func Info(v string)  { Infof("%s", v) }
func Warn(v string)  { Warnf("%s", v) }
func Error(v string) { Errorf("%s", v) }

// LevelString returns the current level as text.
func LevelString() string {
	mu.RLock()
	defer mu.RUnlock()
	switch level {
	case LevelDebug:
		return "debug"
	case LevelInfo:
		return "info"
	case LevelWarn:
		return "warn"
	case LevelError:
		return "error"
	case LevelFatal:
		return "fatal"
	}
	return "info"
}
