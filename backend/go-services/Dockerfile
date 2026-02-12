# Build stage
FROM golang:1.24-bullseye AS builder
WORKDIR /src
COPY . .
ENV CGO_ENABLED=0 GOOS=linux GOARCH=amd64
RUN go mod download
# ensure missing dependency modules are fetched (helps when go.sum entries are absent in repo)
RUN go get golang.org/x/time@v0.4.0 github.com/prometheus/client_golang@v1.16.0 github.com/redis/go-redis/v9@v9.0.0 || true
RUN go build -o /gogotex-auth ./

# Final minimal image
FROM scratch
COPY --from=builder /gogotex-auth /gogotex-auth
EXPOSE 8081
ENTRYPOINT ["/gogotex-auth"]
