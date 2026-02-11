#!/bin/bash
# Generate self-signed SSL certificates for nginx

set -e

echo "Generating self-signed SSL certificates..."

# Create SSL directory
mkdir -p ./config-nginx/ssl

# Generate private key
openssl genrsa -out ./config-nginx/ssl/server.key 4096

# Generate certificate signing request
openssl req -new -key ./config-nginx/ssl/server.key \
    -out ./config-nginx/ssl/server.csr \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=IT/CN=localhost"

# Generate self-signed certificate (valid for 365 days)
openssl x509 -req -days 365 \
    -in ./config-nginx/ssl/server.csr \
    -signkey ./config-nginx/ssl/server.key \
    -out ./config-nginx/ssl/server.crt

# Set proper permissions
chmod 600 ./config-nginx/ssl/server.key
chmod 644 ./config-nginx/ssl/server.crt

# Remove CSR (no longer needed)
rm ./config-nginx/ssl/server.csr

echo ""
echo "SSL certificates generated successfully!"
echo "Location: ./config-nginx/ssl/"
echo ""
echo "Certificate: server.crt"
echo "Private Key: server.key"
echo ""
echo "Note: These are self-signed certificates. Your browser will show a security warning."
echo "You can safely proceed past the warning for internal/development use."
