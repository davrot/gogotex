# Build stage
FROM golang:1.24-bullseye AS builder
WORKDIR /src
COPY . .
ENV CGO_ENABLED=0 GOOS=linux GOARCH=amd64
RUN go mod download
RUN go build -o /gogotex-auth ./

# Final minimal image
FROM scratch
COPY --from=builder /gogotex-auth /gogotex-auth
EXPOSE 8081
ENTRYPOINT ["/gogotex-auth"]
