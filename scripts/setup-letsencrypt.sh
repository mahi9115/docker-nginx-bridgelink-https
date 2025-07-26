#!/bin/bash

# Let's Encrypt Setup Script for Production
# Usage: ./setup-letsencrypt.sh your-domain.com your-email@domain.com

set -e

DOMAIN=${1}
EMAIL=${2}

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    echo "Usage: $0 <domain> <email>"
    echo "Example: $0 api.yourdomain.com admin@yourdomain.com"
    exit 1
fi

echo "Setting up Let's Encrypt for domain: $DOMAIN"
echo "Email: $EMAIL"

# Create directories
mkdir -p ./certbot/conf
mkdir -p ./certbot/www

# Update production nginx config with actual domain
sed -i.bak "s/your-domain.com/$DOMAIN/g" nginx/conf.d/bridgelink.prod.conf

# Stop any running containers
echo "Stopping any running containers..."
docker-compose -f docker-compose.prod.yml down 2>/dev/null || true

# Start nginx with temporary config for ACME challenge
echo "Starting nginx for ACME challenge..."
docker-compose -f docker-compose.prod.yml up -d nginx

# Wait for nginx to be ready
sleep 5

# Request Let's Encrypt certificate
echo "Requesting Let's Encrypt certificate..."
docker-compose -f docker-compose.prod.yml run --rm certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email $EMAIL \
    --agree-tos \
    --no-eff-email \
    -d $DOMAIN

# Replace temporary config with production config
echo "Updating nginx configuration..."
cp nginx/conf.d/bridgelink.prod.conf nginx/conf.d/bridgelink.conf

# Restart nginx with SSL configuration
echo "Restarting nginx with SSL configuration..."
docker-compose -f docker-compose.prod.yml restart nginx

# Test SSL configuration
echo "Testing SSL configuration..."
sleep 5
if curl -f https://$DOMAIN/health >/dev/null 2>&1; then
    echo "✅ SSL setup successful! Your site is now available at https://$DOMAIN"
else
    echo "❌ SSL setup may have issues. Check the logs:"
    echo "docker-compose -f docker-compose.prod.yml logs nginx"
fi

echo ""
echo "Certificate renewal is automated and will run every 12 hours."
echo "To manually renew: docker-compose -f docker-compose.prod.yml exec certbot certbot renew"
