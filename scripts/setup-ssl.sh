#!/bin/bash

# SSL Setup Script for Docker Nginx-Bridgelink Stack
# This script creates SSL certificates for HTTPS support

set -e

SSL_DIR="./ssl"
DOMAIN=${1:-localhost}
COUNTRY=${2:-US}
STATE=${3:-FL}
CITY=${4:-Tampa}
ORG=${5:-"Lunix Solutions"}

echo "Setting up SSL certificates for domain: $DOMAIN"

# Create SSL directory
mkdir -p "$SSL_DIR"

# Generate private key
echo "Generating private key..."
openssl genrsa -out "$SSL_DIR/private.key" 2048

# Generate certificate signing request
echo "Generating certificate signing request..."
openssl req -new -key "$SSL_DIR/private.key" -out "$SSL_DIR/cert.csr" -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/CN=$DOMAIN"

# Generate self-signed certificate (valid for 365 days)
echo "Generating self-signed certificate..."
openssl x509 -req -days 365 -in "$SSL_DIR/cert.csr" -signkey "$SSL_DIR/private.key" -out "$SSL_DIR/cert.crt" \
    -extensions v3_req -extfile <(cat <<EOF
[v3_req]
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment, keyAgreement
extendedKeyUsage = critical, serverAuth
subjectAltName = @alt_names
nsCertType = server

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = www.$DOMAIN
DNS.3 = api.$DOMAIN
IP.1 = 127.0.0.1
IP.2 = ::1
EOF
)

# Generate Diffie-Hellman parameters for enhanced security
echo "Generating Diffie-Hellman parameters (this may take a while)..."
openssl dhparam -out "$SSL_DIR/dhparam.pem" 2048

# Set appropriate permissions
chmod 600 "$SSL_DIR/private.key"
chmod 644 "$SSL_DIR/cert.crt"
chmod 644 "$SSL_DIR/dhparam.pem"

echo "SSL certificates generated successfully!"
echo "Certificate: $SSL_DIR/cert.crt"
echo "Private Key: $SSL_DIR/private.key"
echo "DH Params: $SSL_DIR/dhparam.pem"
echo ""
echo "To trust the certificate on macOS:"
echo "sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $SSL_DIR/cert.crt"
echo ""
echo "To view certificate details:"
echo "openssl x509 -in $SSL_DIR/cert.crt -text -noout"
