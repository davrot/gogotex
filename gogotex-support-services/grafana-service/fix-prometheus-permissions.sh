#!/bin/bash
# Fix permissions for Prometheus data directory
# Run this before starting Prometheus

# Create directory if it doesn't exist
mkdir -p ./data-prometheus

# Set proper permissions
sudo chmod -R 777 ./data-prometheus

echo "Prometheus data directory permissions fixed!"

