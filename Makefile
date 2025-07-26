# Docker Nginx-Bridgelink Stack Makefile
# Usage: make [target]

.PHONY: help build up down restart logs status clean test health

# Default target
help:
	@echo "Available targets:"
	@echo "  help     - Show this help message"
	@echo "  build    - Build and start the stack"
	@echo "  up       - Start the stack in detached mode"
	@echo "  down     - Stop and remove the stack"
	@echo "  restart  - Restart the stack"
	@echo "  logs     - Show logs for all services"
	@echo "  status   - Show status of containers"
	@echo "  clean    - Stop stack and remove images"
	@echo "  test     - Run basic connectivity tests"
	@echo "  health   - Check health of services"

# Build and start the stack
build:
	@echo "Building and starting Docker stack..."
	docker-compose up -d --build

# Start the stack
up:
	@echo "Starting Docker stack..."
	docker-compose up -d

# Stop the stack
down:
	@echo "Stopping Docker stack..."
	docker-compose down

# Restart the stack
restart:
	@echo "Restarting Docker stack..."
	docker-compose restart

# Show logs
logs:
	@echo "Showing logs for all services..."
	docker-compose logs -f

# Show container status
status:
	@echo "Container status:"
	docker-compose ps

# Clean up (stop and remove images)
clean:
	@echo "Cleaning up Docker stack..."
	docker-compose down --rmi all --volumes --remove-orphans

# Run basic tests
test:
	@echo "Running basic connectivity tests..."
	@echo "Testing health endpoint..."
	curl -f http://localhost/health || echo "Health check failed"
	@echo "Testing root endpoint..."
	curl -f http://localhost/ || echo "Root endpoint failed"
	@echo "Testing direct bridgelink access..."
	curl -f http://localhost:8443/ || echo "Direct access failed"

# Check health of services
health:
	@echo "Checking service health..."
	@echo "Nginx container logs (last 10 lines):"
	docker-compose logs --tail=10 nginx
	@echo ""
	@echo "Bridgelink container logs (last 10 lines):"
	docker-compose logs --tail=10 bridgelink
	@echo ""
	@echo "Container status:"
	docker-compose ps
