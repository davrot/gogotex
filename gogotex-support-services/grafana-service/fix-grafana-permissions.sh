#!/bin/bash
# Fix permissions for Grafana data directory
# Run this before starting Grafana

# Create directory if it doesn't exist
mkdir -p ./data-grafana

# Set proper permissions
sudo chmod -R 777 ./data-grafana

echo "Grafana data directory permissions fixed!"

