BINARY=go-auth

.PHONY: build test run lint tidy

build:
	go build -o bin/$(BINARY) ./...

test:
	go test ./... -v

run:
	go run ./main.go

tidy:
	go mod tidy

lint:
	go vet ./...
