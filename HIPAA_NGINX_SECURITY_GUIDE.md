# HIPAA-Compliant Nginx Security Implementation Guide

## Overview
This guide provides comprehensive documentation for implementing a HIPAA-compliant nginx reverse proxy with mutual TLS (mTLS), client certificate authentication, and secure multi-stack Docker architecture for healthcare data exchange.

## Architecture Overview

### Current Setup
- **nginx-proxy stack**: Handles SSL termination, security headers, mTLS
- **bridgelink-app stack**: Runs the healthcare application
- **External network**: Allows secure communication between stacks

### Security Layers
1. **Mutual TLS (mTLS)** - Client certificate authentication
2. **IP Address Whitelisting** - Network-level access control
3. **Path-Based Access Control** - API endpoint restrictions
4. **Rate Limiting** - Protection against abuse
5. **HIPAA Audit Logging** - Comprehensive access tracking

---

## 1. Docker Stack Separation

### Prerequisites
Create external network for inter-stack communication:
```bash
docker network create --driver bridge --subnet=172.20.0.0/24 healthcare-network
```

### Bridgelink Application Stack
**File: `bridgelink-docker-compose.yml`**
```yaml
services:
  bridgelink:
    image: innovarhealthcare/bridgelink:latest
    container_name: bridgelink-app
    # Remove external port exposure for security
    expose:
      - "6001"  # API1 endpoint
      - "6002"  # API2 endpoint
      - "6003"  # Admin endpoint
    networks:
      healthcare-network:
        ipv4_address: 172.20.0.10
    restart: unless-stopped
    environment:
      - LOG_LEVEL=INFO
      - AUDIT_ENABLED=true
      - HIPAA_MODE=true
    # Health check for container monitoring
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6001/health"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  healthcare-network:
    external: true
```

### Nginx Proxy Stack
**File: `nginx-docker-compose.yml`**
```yaml
services:
  nginx:
    image: nginx:alpine
    container_name: nginx-proxy
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./ssl:/etc/ssl/certs:ro
      - ./ssl:/etc/ssl/private:ro
      - ./logs:/var/log/nginx  # HIPAA audit logging
    networks:
      healthcare-network:
        ipv4_address: 172.20.0.5
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Log rotation for HIPAA compliance
  logrotate:
    image: alpine:latest
    container_name: nginx-logrotate
    volumes:
      - ./logs:/var/log/nginx
      - ./scripts/logrotate.conf:/etc/logrotate.conf:ro
    command: |
      sh -c 'while true; do 
        logrotate /etc/logrotate.conf
        sleep 86400
      done'
    restart: unless-stopped

networks:
  healthcare-network:
    external: true
```

---

## 2. HIPAA Minimum Security Requirements

### Technical Safeguards (45 CFR §164.312)

#### Encryption Requirements
- **Data in Transit**: TLS 1.2 minimum (TLS 1.3 recommended)
- **Data at Rest**: AES-256 encryption minimum
- **Key Management**: Secure key storage and rotation

#### Access Controls
- **Unique User Authentication**: Each client must have unique certificates
- **Role-Based Access**: Minimum necessary access principle
- **Multi-Factor Authentication**: Client certificates + IP whitelisting
- **Session Management**: Automatic timeout and secure headers

#### Audit Controls
- **Comprehensive Logging**: All PHI access logged
- **Log Integrity**: Immutable audit trails
- **Regular Review**: Automated log analysis
- **Retention**: Logs retained for 6+ years

---

## 3. Client Certificate Management

### Generate Certificate Authority (CA)
```bash
# Generate CA private key
openssl genrsa -out client-ca.key 4096

# Create CA certificate
openssl req -new -x509 -days 3650 -key client-ca.key -out client-ca.crt \
    -subj "/CN=Healthcare-CA/O=Healthcare-Org/C=US"
```

### Client Certificate Generation Script
**File: `scripts/generate-client-cert.sh`**
```bash
#!/bin/bash
# Generate client certificates for healthcare partners

CLIENT_NAME=$1
ORG_NAME=$2
API_ACCESS=$3  # api1, api2, admin, or combination

if [ -z "$CLIENT_NAME" ] || [ -z "$ORG_NAME" ] || [ -z "$API_ACCESS" ]; then
    echo "Usage: $0 <client_name> <organization> <api_access>"
    echo "Example: $0 hospital1-client 'Hospital One' 'api1'"
    exit 1
fi

# Create client directory
mkdir -p clients/${CLIENT_NAME}

# Generate client private key
openssl genrsa -out clients/${CLIENT_NAME}/${CLIENT_NAME}.key 4096

# Create certificate signing request
openssl req -new -key clients/${CLIENT_NAME}/${CLIENT_NAME}.key \
    -out clients/${CLIENT_NAME}/${CLIENT_NAME}.csr \
    -subj "/CN=${CLIENT_NAME}/O=${ORG_NAME}/C=US"

# Sign with CA
openssl x509 -req -days 365 -in clients/${CLIENT_NAME}/${CLIENT_NAME}.csr \
    -CA ssl/client-ca.crt -CAkey ssl/client-ca.key -CAcreateserial \
    -out clients/${CLIENT_NAME}/${CLIENT_NAME}.crt

# Create client config file
cat > clients/${CLIENT_NAME}/client-config.txt << EOF
Client: ${CLIENT_NAME}
Organization: ${ORG_NAME}
API Access: ${API_ACCESS}
Certificate: ${CLIENT_NAME}.crt
Private Key: ${CLIENT_NAME}.key
Generated: $(date)
EOF

echo "Client certificate generated for ${CLIENT_NAME}"
echo "Files created in: clients/${CLIENT_NAME}/"
echo "API Access: ${API_ACCESS}"

# Clean up CSR
rm clients/${CLIENT_NAME}/${CLIENT_NAME}.csr
```

---

## 4. Nginx Security Configuration

### Main Configuration
**File: `nginx/nginx.conf`**
```nginx
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Security headers
    server_tokens off;
    
    # Logging format for HIPAA compliance
    log_format hipaa_format '$remote_addr - $remote_user [$time_local] '
                           '"$request" $status $body_bytes_sent '
                           '"$http_referer" "$http_user_agent" '
                           'ssl_client_s_dn="$ssl_client_s_dn" '
                           'ssl_client_verify="$ssl_client_verify" '
                           'request_time=$request_time';
    
    # Performance optimizations
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    
    # Security settings
    client_max_body_size 10M;
    client_body_timeout 12;
    client_header_timeout 12;
    send_timeout 10;
    
    # Include server configurations
    include /etc/nginx/conf.d/*.conf;
}
```

### Server Configuration with mTLS and Access Control
**File: `nginx/conf.d/healthcare.conf`**
```nginx
# Client certificate to API access mapping
map $ssl_client_s_dn $client_access {
    default "none";
    "CN=hospital1-client,O=Hospital One,C=US" "api1";
    "CN=clinic2-client,O=Clinic Two,C=US" "api2";
    "CN=admin-client,O=Healthcare Admin,C=US" "api1,api2,admin";
    "CN=partner3-client,O=Health Partner 3,C=US" "api1,api2";
}

# IP whitelisting
geo $allowed_ip {
    default 0;
    10.0.0.0/8 1;        # Internal network
    192.168.0.0/16 1;    # Private networks
    172.16.0.0/12 1;     # Docker networks
    # Add specific client IPs
    # 203.0.113.5/32 1;    # Hospital 1
    # 198.51.100.10/32 1;  # Clinic 2
}

# Rate limiting zones
limit_req_zone $ssl_client_s_dn zone=api1_rate:10m rate=10r/s;
limit_req_zone $ssl_client_s_dn zone=api2_rate:10m rate=5r/s;
limit_req_zone $ssl_client_s_dn zone=admin_rate:10m rate=2r/s;

# Upstream backends
upstream api1_backend {
    server 172.20.0.10:6001;
    keepalive 32;
}

upstream api2_backend {
    server 172.20.0.10:6002;
    keepalive 32;
}

upstream admin_backend {
    server 172.20.0.10:6003;
    keepalive 16;
}

# HTTPS server with mTLS
server {
    listen 443 ssl http2;
    server_name your-healthcare-domain.com;
    
    # SSL/TLS Configuration
    ssl_certificate /etc/ssl/certs/server.crt;
    ssl_certificate_key /etc/ssl/private/server.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Client Certificate Authentication (mTLS)
    ssl_client_certificate /etc/ssl/certs/client-ca.crt;
    ssl_verify_client on;
    ssl_verify_depth 2;
    
    # HIPAA Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'" always;
    
    # HIPAA Audit Logging
    access_log /var/log/nginx/hipaa_access.log hipaa_format;
    error_log /var/log/nginx/hipaa_error.log;
    
    # IP Access Control
    if ($allowed_ip = 0) {
        return 403 "Access denied - IP not allowed";
    }
    
    # Block requests without proper client certificates
    if ($ssl_client_verify != SUCCESS) {
        return 403 "Client certificate required";
    }
    
    # Health check endpoint (no auth required for monitoring)
    location = /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # API1 Endpoint - Hospital data exchange
    location /api1/ {
        # Check client authorization
        if ($client_access !~ "api1") {
            return 403 "Access denied to API1";
        }
        
        # Rate limiting
        limit_req zone=api1_rate burst=20 nodelay;
        
        # Content type validation
        if ($request_method = POST) {
            if ($content_type !~ "application/(json|xml)") {
                return 400 "Invalid content type for API1";
            }
        }
        
        # Forward to backend
        proxy_pass http://api1_backend/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Client-DN $ssl_client_s_dn;
        proxy_set_header X-Client-Verify $ssl_client_verify;
        
        # Timeouts for healthcare data processing
        proxy_connect_timeout 60s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
        
        # Separate logging for API1
        access_log /var/log/nginx/api1_access.log hipaa_format;
    }
    
    # API2 Endpoint - Clinic data exchange
    location /api2/ {
        if ($client_access !~ "api2") {
            return 403 "Access denied to API2";
        }
        
        limit_req zone=api2_rate burst=15 nodelay;
        
        if ($request_method = POST) {
            if ($content_type !~ "application/(json|xml)") {
                return 400 "Invalid content type for API2";
            }
        }
        
        proxy_pass http://api2_backend/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Client-DN $ssl_client_s_dn;
        proxy_set_header X-Client-Verify $ssl_client_verify;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
        
        access_log /var/log/nginx/api2_access.log hipaa_format;
    }
    
    # Admin Endpoint - Administrative functions
    location /admin/ {
        if ($client_access !~ "admin") {
            return 403 "Admin access denied";
        }
        
        limit_req zone=admin_rate burst=5 nodelay;
        
        proxy_pass http://admin_backend/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Client-DN $ssl_client_s_dn;
        proxy_set_header X-Client-Verify $ssl_client_verify;
        
        access_log /var/log/nginx/admin_access.log hipaa_format;
    }
    
    # Block all other paths
    location / {
        return 404 "Endpoint not found";
    }
}

# HTTP to HTTPS redirect
server {
    listen 80;
    server_name your-healthcare-domain.com;
    return 301 https://$server_name$request_uri;
}
```

---

## 5. Deployment Scripts

### Startup Script
**File: `scripts/start-healthcare-stack.sh`**
```bash
#!/bin/bash
set -e

echo "Starting HIPAA-compliant Healthcare Stack..."

# Create external network if it doesn't exist
echo "Creating healthcare network..."
docker network create --driver bridge --subnet=172.20.0.0/24 healthcare-network 2>/dev/null || true

# Create log directories
mkdir -p logs
mkdir -p ssl
mkdir -p clients

# Set proper permissions for HIPAA compliance
chmod 750 logs
chmod 700 ssl
chmod 750 clients

# Start bridgelink application stack
echo "Starting BridgeLink application..."
docker-compose -f bridgelink-docker-compose.yml up -d

# Wait for bridgelink to be healthy
echo "Waiting for BridgeLink to be ready..."
sleep 15

# Check bridgelink health
if ! docker exec bridgelink-app curl -f http://localhost:6001/health >/dev/null 2>&1; then
    echo "Warning: BridgeLink health check failed"
fi

# Start nginx proxy stack
echo "Starting Nginx proxy..."
docker-compose -f nginx-docker-compose.yml up -d

# Wait for nginx to be ready
sleep 10

# Verify nginx configuration
if docker exec nginx-proxy nginx -t; then
    echo "Nginx configuration is valid"
else
    echo "Error: Nginx configuration test failed"
    exit 1
fi

echo "Healthcare stack deployed successfully!"
echo "Services running:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "Access URLs:"
echo "- Health Check: https://your-domain.com/health"
echo "- API1: https://your-domain.com/api1/"
echo "- API2: https://your-domain.com/api2/"
echo "- Admin: https://your-domain.com/admin/ (restricted)"
```

### Shutdown Script
**File: `scripts/stop-healthcare-stack.sh`**
```bash
#!/bin/bash
set -e

echo "Stopping Healthcare Stack..."

# Stop nginx proxy stack
echo "Stopping Nginx proxy..."
docker-compose -f nginx-docker-compose.yml down

# Stop bridgelink application stack
echo "Stopping BridgeLink application..."
docker-compose -f bridgelink-docker-compose.yml down

echo "All services stopped successfully!"

# Optional: Remove the network (uncomment if needed)
# echo "Removing healthcare network..."
# docker network rm healthcare-network 2>/dev/null || true
```

### Log Rotation Configuration
**File: `scripts/logrotate.conf`**
```
/var/log/nginx/*.log {
    daily
    missingok
    rotate 365
    compress
    delaycompress
    notifempty
    create 644 nginx nginx
    sharedscripts
    postrotate
        if [ -f /var/run/nginx.pid ]; then
            kill -USR1 `cat /var/run/nginx.pid`
        fi
    endscript
}
```

---

## 6. Client Configuration Examples

### Hospital Client Configuration
```bash
# Generate certificate for Hospital 1
./scripts/generate-client-cert.sh hospital1-client "Hospital One" "api1"

# Client connection test
curl -X GET https://your-domain.com/api1/patients \
  --cert clients/hospital1-client/hospital1-client.crt \
  --key clients/hospital1-client/hospital1-client.key \
  --cacert ssl/server.crt
```

### Clinic Client Configuration
```bash
# Generate certificate for Clinic 2
./scripts/generate-client-cert.sh clinic2-client "Clinic Two" "api2"

# Client connection test
curl -X POST https://your-domain.com/api2/appointments \
  --cert clients/clinic2-client/clinic2-client.crt \
  --key clients/clinic2-client/clinic2-client.key \
  --cacert ssl/server.crt \
  --header "Content-Type: application/json" \
  --data '{"patient_id": "12345", "appointment_date": "2024-01-15"}'
```

---

## 7. Monitoring and Compliance

### Log Analysis Script
**File: `scripts/analyze-logs.sh`**
```bash
#!/bin/bash
# HIPAA compliance log analysis

LOG_DIR="/var/log/nginx"
DATE=$(date +%Y-%m-%d)

echo "HIPAA Compliance Log Analysis - $DATE"
echo "========================================="

# Failed authentication attempts
echo "Failed Authentication Attempts:"
grep "403" $LOG_DIR/hipaa_access.log | grep $(date +%d/%b/%Y) | wc -l

# Unique clients accessed today
echo "Unique Clients Accessed Today:"
grep $(date +%d/%b/%Y) $LOG_DIR/hipaa_access.log | \
  grep -o 'ssl_client_s_dn="[^"]*"' | sort | uniq | wc -l

# API endpoint usage
echo "API Endpoint Usage:"
echo "- API1: $(grep '/api1/' $LOG_DIR/api1_access.log | grep $(date +%d/%b/%Y) | wc -l) requests"
echo "- API2: $(grep '/api2/' $LOG_DIR/api2_access.log | grep $(date +%d/%b/%Y) | wc -l) requests"
echo "- Admin: $(grep '/admin/' $LOG_DIR/admin_access.log | grep $(date +%d/%b/%Y) | wc -l) requests"

# Error rate
echo "Error Rate:"
TOTAL_REQUESTS=$(grep $(date +%d/%b/%Y) $LOG_DIR/hipaa_access.log | wc -l)
ERROR_REQUESTS=$(grep $(date +%d/%b/%Y) $LOG_DIR/hipaa_access.log | grep -E " (4|5)[0-9]{2} " | wc -l)
if [ $TOTAL_REQUESTS -gt 0 ]; then
    ERROR_RATE=$(echo "scale=2; ($ERROR_REQUESTS * 100) / $TOTAL_REQUESTS" | bc)
    echo "- Total Requests: $TOTAL_REQUESTS"
    echo "- Error Requests: $ERROR_REQUESTS"
    echo "- Error Rate: $ERROR_RATE%"
fi
```

### Health Check Script
**File: `scripts/health-check.sh`**
```bash
#!/bin/bash
# Health check for all services

echo "Healthcare Stack Health Check"
echo "============================="

# Check Docker containers
echo "Container Status:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(nginx-proxy|bridgelink-app|nginx-logrotate)"

# Check nginx configuration
echo ""
echo "Nginx Configuration Test:"
if docker exec nginx-proxy nginx -t 2>/dev/null; then
    echo "✓ Nginx configuration is valid"
else
    echo "✗ Nginx configuration has errors"
fi

# Check SSL certificate expiry
echo ""
echo "SSL Certificate Status:"
CERT_FILE="ssl/server.crt"
if [ -f "$CERT_FILE" ]; then
    EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$CERT_FILE" | cut -d= -f2)
    EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
    CURRENT_EPOCH=$(date +%s)
    DAYS_LEFT=$(( ($EXPIRY_EPOCH - $CURRENT_EPOCH) / 86400 ))
    
    if [ $DAYS_LEFT -gt 30 ]; then
        echo "✓ SSL certificate expires in $DAYS_LEFT days"
    elif [ $DAYS_LEFT -gt 0 ]; then
        echo "⚠ SSL certificate expires in $DAYS_LEFT days (renewal needed)"
    else
        echo "✗ SSL certificate has expired"
    fi
else
    echo "✗ SSL certificate file not found"
fi

# Test endpoints
echo ""
echo "Endpoint Tests:"
if curl -s -o /dev/null -w "%{http_code}" https://localhost/health | grep -q "200"; then
    echo "✓ Health endpoint accessible"
else
    echo "✗ Health endpoint not accessible"
fi
```

---

## 8. Security Checklist

### Pre-Deployment
- [ ] Generate CA and server certificates
- [ ] Create client certificates for all authorized clients
- [ ] Configure IP whitelisting for known client networks
- [ ] Set up log rotation for HIPAA compliance
- [ ] Test mTLS authentication with sample clients
- [ ] Verify rate limiting configuration
- [ ] Validate nginx configuration syntax

### Post-Deployment
- [ ] Verify all containers are running and healthy
- [ ] Test each API endpoint with authorized clients
- [ ] Confirm unauthorized access is properly blocked
- [ ] Check log files are being created and rotated
- [ ] Monitor certificate expiration dates
- [ ] Set up automated log analysis
- [ ] Document all client certificates and their access levels

### Ongoing Maintenance
- [ ] Regular security audits and penetration testing
- [ ] Certificate renewal before expiration
- [ ] Log analysis and anomaly detection
- [ ] Update client access permissions as needed
- [ ] Regular backup of configuration and certificates
- [ ] Monitor for security vulnerabilities in Docker images

---

## 9. Troubleshooting

### Common Issues

#### mTLS Authentication Failures
```bash
# Check client certificate validity
openssl x509 -in client.crt -text -noout

# Verify certificate chain
openssl verify -CAfile client-ca.crt client.crt

# Test connection with verbose output
curl -v --cert client.crt --key client.key https://your-domain.com/health
```

#### Rate Limiting Issues
```bash
# Check rate limit zones
docker exec nginx-proxy cat /proc/meminfo | grep -i shared

# Monitor rate limiting in logs
tail -f logs/hipaa_access.log | grep "limiting requests"
```

#### Container Communication Issues
```bash
# Check network connectivity
docker exec nginx-proxy ping 172.20.0.10

# Verify network configuration
docker network inspect healthcare-network
```

### Log Locations
- **Main Access Log**: `logs/hipaa_access.log`
- **Error Log**: `logs/hipaa_error.log`
- **API1 Log**: `logs/api1_access.log`
- **API2 Log**: `logs/api2_access.log`
- **Admin Log**: `logs/admin_access.log`

---

## 10. Compliance Notes

This configuration addresses key HIPAA requirements:

- **§164.312(a)(1)** - Access control through mTLS and role-based routing
- **§164.312(b)** - Audit controls via comprehensive logging
- **§164.312(c)(1)** - Integrity controls through SSL/TLS and checksums
- **§164.312(d)** - Person or entity authentication via client certificates
- **§164.312(e)(1)** - Transmission security through encrypted channels

**Important**: This guide provides technical implementation. Ensure you also have:
- Business Associate Agreements with all vendors
- Regular risk assessments
- Staff training programs
- Incident response procedures
- Physical safeguards for servers and devices

---

## Support and Updates

For questions or updates to this configuration:
1. Review nginx error logs for configuration issues
2. Check Docker container logs for application errors
3. Verify client certificates and network connectivity
4. Consult HIPAA compliance documentation for regulatory requirements

Last Updated: $(date)
