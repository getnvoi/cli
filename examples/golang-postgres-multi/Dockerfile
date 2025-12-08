# Multi-stage build for optimized image size

# Stage 1: Build
FROM golang:1.23-alpine AS builder

# Install build dependencies (no SQLite needed for Postgres)
RUN apk add --no-cache gcc musl-dev

WORKDIR /app

# Copy dependency files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the application
# CGO_ENABLED=1 required for some postgres driver features
RUN CGO_ENABLED=1 GOOS=linux go build -o app .

# Stage 2: Runtime
FROM alpine:latest

# Install runtime dependencies
RUN apk --no-cache add ca-certificates

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/app .

# Expose port
EXPOSE 3000

# Run the application
CMD ["./app"]
