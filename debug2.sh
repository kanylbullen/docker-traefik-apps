#!/bin/bash

# Extract just the functions we need to test
get_instance_dir() {
    local role_name="$1"
    local instance_name="$2"
    echo "/opt/homelab/instances/${role_name}-${instance_name}"
}

# Test the function
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
