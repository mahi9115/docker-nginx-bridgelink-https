# Docker Nginx-Bridgelink Stack

This Docker stack sets up an nginx proxy server that forwards traffic to the Innovar Healthcare Bridgelink application.

## Architecture

- **Nginx Proxy**: `172.20.0.5` - Listens on port 80
- **Bridgelink App**: `172.20.0.10` - Runs on internal port 6006, exposed on port 8443

## Quick Start

### 1. Clone and Start
```bash
# Clone the repository
git clone <your-repo-url>
cd docker-nginx-stack

# Start the stack
docker-compose up -d
```

### 2. Verify Deployment
```bash
# Check container status
docker-compose ps

# Test health endpoint
curl http://localhost/health
```

## Using Makefile (Recommended)

For easier management, use the provided Makefile:

```bash
# Start the stack
make up

# Check status
make status

# Run tests
make test

# View logs
make logs

# Stop the stack
make down

# See all available commands
make help
```

## Access Points

1. **Via Nginx proxy (recommended)**: 
   - API: `http://localhost/api/`
   - Root: `http://localhost/`

2. **Direct access to Bridgelink**:
   - `http://localhost:8443`

3. **Health check**:
   - `http://localhost/health`

### Stop the stack
```bash
docker-compose down
```

### View logs
```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f nginx
docker-compose logs -f bridgelink
```

## Configuration

### Nginx Configuration
- Main config: `nginx/nginx.conf`
- Proxy config: `nginx/conf.d/bridgelink.conf`

### SSL Setup (Optional)
To enable HTTPS, you'll need to generate SSL certificates:

```bash
# Create SSL directory
mkdir -p ssl

# Generate self-signed certificate (for development)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ssl/nginx-selfsigned.key \
  -out ssl/nginx-selfsigned.crt \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"

# Update docker-compose.yml to mount SSL certificates
# Add to nginx volumes:
# - ./ssl:/etc/ssl/certs
# - ./ssl:/etc/ssl/private
```

## Network Details

- Network: `proxy-network` (172.20.0.0/24)
- Nginx: 172.20.0.5
- Bridgelink: 172.20.0.10

## Ports

- **80**: HTTP access to nginx proxy (redirects to HTTPS when SSL is enabled)
- **443**: HTTPS access to nginx proxy (when SSL is configured)
- **8443**: Direct access to bridgelink application

## HTTPS/SSL Setup

### Development SSL (Self-Signed Certificates)

For development and testing, you can use self-signed certificates:

```bash
# Generate and setup SSL certificates
make ssl-dev

# Test HTTPS endpoint
curl -k https://localhost/health

# Trust certificate on macOS (optional)
make trust-cert
```

**Access Points with SSL:**
- **HTTPS API**: `https://localhost/api/`
- **HTTPS Health**: `https://localhost/health`
- **HTTP**: Automatically redirects to HTTPS

### Production SSL (Let's Encrypt)

For production deployments with a real domain:

```bash
# Setup Let's Encrypt SSL
make ssl-prod DOMAIN=api.yourdomain.com EMAIL=admin@yourdomain.com

# Or manually:
./scripts/setup-letsencrypt.sh api.yourdomain.com admin@yourdomain.com
```

**Production Requirements:**
- Domain name pointing to your server
- Ports 80 and 443 open and accessible
- Valid email address for Let's Encrypt notifications

### SSL Configuration Features

- ✅ **TLS 1.2 & 1.3** support
- ✅ **HTTP/2** enabled
- ✅ **HSTS** (HTTP Strict Transport Security)
- ✅ **Security Headers** (XSS, Content-Type, Frame-Options)
- ✅ **OCSP Stapling** (production)
- ✅ **Perfect Forward Secrecy**
- ✅ **Automatic HTTP to HTTPS redirect**
- ✅ **Certificate auto-renewal** (Let's Encrypt)

## API Testing with Postman

### 1. Basic Setup in Postman

**Create a new Collection:**
1. Open Postman
2. Click "New" → "Collection"
3. Name it "Bridgelink API Tests"

**Set up Environment Variables:**
1. Click the gear icon (⚙️) → "Manage Environments"
2. Add New Environment called "Bridgelink Local"
3. Add these variables:
   - `base_url_proxy_http`: `http://localhost/api`
   - `base_url_proxy_https`: `https://localhost/api`
   - `base_url_direct`: `http://localhost:8443`

**SSL Certificate Settings (for HTTPS):**
1. Go to Postman Settings (⚙️) → "Certificates"
2. Turn OFF "SSL certificate verification" for development
3. Or add the certificate file (`ssl/cert.crt`) if using trusted certificates

### 2. Test API Connectivity

**Test 1: Health Check via Proxy**
```
Method: GET
URL: http://localhost/health
Headers: (none required)
Expected: "healthy"
```

**Test 2: Root Endpoint via Proxy**
```
Method: GET
URL: {{base_url_proxy}}/
Headers: 
- Content-Type: application/json
```

**Test 3: Direct Access to Bridgelink**
```
Method: GET
URL: {{base_url_direct}}/
Headers: 
- Content-Type: application/json
```

### 3. Common API Endpoints to Test

**Test 4: API Status/Info**
```
Method: GET
URL: {{base_url_proxy}}/status
# or
URL: {{base_url_proxy}}/info
Headers:
- Content-Type: application/json
```

**Test 5: Health Check (Direct)**
```
Method: GET
URL: {{base_url_direct}}/health
Headers:
- Content-Type: application/json
```

### 4. POST Request Examples

**Test 6: Sample POST Request**
```
Method: POST
URL: {{base_url_proxy}}/data
Headers:
- Content-Type: application/json
- Accept: application/json

Body (JSON):
{
  "message": "test",
  "timestamp": "2025-07-26T22:48:00Z",
  "data": {
    "key": "value"
  }
}
```

**Test 7: Authentication Test (if required)**
```
Method: POST
URL: {{base_url_proxy}}/auth
Headers:
- Content-Type: application/json

Body (JSON):
{
  "username": "test",
  "password": "test"
}
```

### 5. Testing Different Content Types

**Test 8: XML Data**
```
Method: POST
URL: {{base_url_proxy}}/xml-endpoint
Headers:
- Content-Type: application/xml
- Accept: application/xml

Body (XML):
<?xml version="1.0" encoding="UTF-8"?>
<root>
  <message>test</message>
  <timestamp>2025-07-26T22:48:00Z</timestamp>
</root>
```

**Test 9: Form Data**
```
Method: POST
URL: {{base_url_proxy}}/form-endpoint
Headers:
- Content-Type: application/x-www-form-urlencoded

Body (form-data):
key1=value1
key2=value2
message=test
```

### 6. Load Testing

**Test 10: Multiple Requests**
1. Use Postman Collection Runner
2. Set iterations to 10-100
3. Monitor response times and success rates

### 7. Expected Response Formats

Depending on the Bridgelink application, you might expect:

**Success Response:**
```json
{
  "status": "success",
  "data": {...},
  "timestamp": "2025-07-26T22:48:00Z"
}
```

**Error Response:**
```json
{
  "status": "error",
  "message": "Error description",
  "code": 400,
  "timestamp": "2025-07-26T22:48:00Z"
}
```

### 8. Monitoring and Debugging

**Check Proxy Logs:**
```bash
# Real-time nginx logs
docker-compose logs -f nginx

# Bridgelink application logs
docker-compose logs -f bridgelink
```

**Network Testing:**
```bash
# Test connectivity
curl -v http://localhost/api/
curl -v http://localhost:8443/

# Test with data
curl -X POST http://localhost/api/test \
  -H "Content-Type: application/json" \
  -d '{"message":"test"}'
```

## Troubleshooting

1. **Check if containers are running**:
   ```bash
   docker-compose ps
   ```

2. **Check container logs**:
   ```bash
   docker-compose logs nginx
   docker-compose logs bridgelink
   ```

3. **Test nginx configuration**:
   ```bash
   docker-compose exec nginx nginx -t
   ```

4. **Restart services**:
   ```bash
   docker-compose restart nginx
   docker-compose restart bridgelink
   ```
