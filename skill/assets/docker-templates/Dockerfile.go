# Multi-stage Dockerfile for Go services. Distroless final, statically linked.
# syntax=docker/dockerfile:1.7

FROM golang:1.23-bookworm AS builder
WORKDIR /src
ENV CGO_ENABLED=0 GOOS=linux GOFLAGS="-trimpath"
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go build -ldflags="-s -w -X main.version=${VERSION:-dev}" -o /out/api ./cmd/api

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /
COPY --from=builder /out/api /api
EXPOSE 8000
USER nonroot:nonroot
ENTRYPOINT ["/api"]
