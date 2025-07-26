# Docker Nginx-Bridgelink Stack Makefile
# Usage: make [target]

.PHONY: help build up down restart logs status clean test health ssl-dev ssl-prod ssl-test trust-cert

# Default target
help:
	@echo "Available targets:"
	@echo "  help      - Show this help message"
	@echo "  build     - Build and start the stack"
	@echo "  up        - Start the stack in detached mode"
	@echo "  down      - Stop and remove the stack"
	@echo "  restart   - Restart the stack"
	@echo "  logs      - Show logs for all services"
	@echo "  status    - Show status of containers"
	@echo "  clean     - Stop stack and remove images"
	@echo "  test      - Run basic connectivity tests"
	@echo "  health    - Check health of services"
	@echo "  ssl-dev   - Setup self-signed SSL certificates for development"
	@echo "  ssl-prod  - Setup Let's Encrypt SSL for production (requires domain)"
	@echo "  ssl-test  - Test SSL configuration"
	@echo "  trust-cert - Trust the self-signed certificate on macOS"

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

# Setup development SSL certificates
ssl-dev:
	@echo "Setting up self-signed SSL certificates for development..."
	./scripts/setup-ssl.sh
	@echo "Restarting stack with SSL..."
	docker-compose down
	docker-compose up -d
	@echo "SSL setup complete. Access via https://localhost/"

# Setup production SSL with Let's Encrypt
ssl-prod:
	@echo "Setting up Let's Encrypt SSL for production..."
	@echo "Usage: make ssl-prod DOMAIN=your-domain.com EMAIL=your-email@domain.com"
	@if [ -z "$(DOMAIN)" ] || [ -z "$(EMAIL)" ]; then \
		echo "Error: DOMAIN and EMAIL are required"; \
		echo "Example: make ssl-prod DOMAIN=api.yourdomain.com EMAIL=admin@yourdomain.com"; \
		exit 1; \
	fi
	./scripts/setup-letsencrypt.sh $(DOMAIN) $(EMAIL)

# Test SSL configuration
ssl-test:
	@echo "Testing SSL configuration..."
	@echo "Testing HTTPS health endpoint..."
	curl -f -k https://localhost/health || echo "HTTPS health check failed"
	@echo "Testing SSL certificate..."
	openssl s_client -connect localhost:443 -servername localhost </dev/null 2>/dev/null | openssl x509 -noout -text | grep -E "(Subject|Issuer|Not After)"

# Trust self-signed certificate on macOS
trust-cert:
	@echo "Adding self-signed certificate to macOS keychain..."
	@if [ ! -f ssl/cert.crt ]; then \
		echo "Error: SSL certificate not found. Run 'make ssl-dev' first."; \
		exit 1; \
	fi
	sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ssl/cert.crt
	@echo "Certificate trusted. You may need to restart your browser."
