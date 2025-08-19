#!/bin/bash

# Source the install-role.sh functions
source ./install-role.sh

# Test the functions
echo "Testing get_instance_dir function:"
instance_dir=$(get_instance_dir "mysql" "dev")
echo "Instance dir: $instance_dir"

echo "Checking if docker-compose.yml exists:"
if [[ -f "$instance_dir/docker-compose.yml" ]]; then
    echo "✓ docker-compose.yml exists at: $instance_dir/docker-compose.yml"
else
    echo "✗ docker-compose.yml NOT found at: $instance_dir/docker-compose.yml"
fi

echo "Listing contents of instance directory:"
ls -la "$instance_dir"
