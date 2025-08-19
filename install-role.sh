#!/bin/bash

# =============================================================================
# Homelab Role Installation Script
# =============================================================================
# Install and manage additional services using a role-based approach
# Usage: ./install-role.sh <role-name> [instance-name] [action]
# Actions: install, uninstall, update, status, logs

set -uo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Show usage information
show_usage() {
    echo -e "${BLUE}Homelab Role Manager - Multi-Instance Support${NC}"
    echo ""
    echo "Usage: $0 <role-name> [instance-name] [action]"
    echo ""
    echo "Available roles:"
    if [[ -d "roles" ]]; then
        for role in roles/*/; do
            if [[ -d "$role" ]]; then
                role_name=$(basename "$role")
                echo "  • $role_name"
            fi
        done
    else
        echo "  No roles available (roles/ directory not found)"
    fi
    echo ""
    echo "Available actions:"
    echo "  • install       - Install a specific role instance"
    echo "  • install-all   - Install all instances declared in .env.example"
    echo "  • uninstall     - Remove a specific role instance"
    echo "  • uninstall-all - Remove all instances declared in .env.example"
    echo "  • status        - Show specific role instance status"
    echo "  • status-all    - Show status of all declared instances"
    echo "  • logs          - Show specific role instance logs"
    echo "  • update        - Update a specific role instance"
    echo "  • config        - Edit specific role instance configuration"
    echo "  • list          - List all instances of a role"
    echo ""
    echo "Examples:"
    echo "  $0 mysql install-all              # Install all declared mysql instances"
    echo "  $0 mysql status-all               # Check status of all mysql instances"
    echo "  $0 mysql                          # Install default mysql instance"
    echo "  $0 mysql prod install             # Install mysql instance named 'prod'"
    echo "  $0 mysql dev status               # Check status of mysql 'dev' instance"
    echo "  $0 wordpress install-all          # Install all declared wordpress instances"
    echo "  $0 mysql list                     # List all mysql instances"
    echo ""
    echo "Multi-Instance Management:"
    echo "  • Configure instances in roles/<role>/.env.example"
    echo "  • Use INSTANCES variable to declare instance names"
    echo "  • Use <instance>_<VARIABLE> format for instance-specific settings"
    echo "  • Each instance gets its own data directory and subdomain"
}

# Check if role exists
check_role_exists() {
    local role_name="$1"
    if [[ ! -d "roles/$role_name" ]]; then
        print_error "Role '$role_name' not found in roles/ directory"
        return 1
    fi
    return 0
}

# Get instance directory path
get_instance_dir() {
    local role_name="$1"
    local instance_name="$2"
    echo "/opt/homelab/instances/${role_name}-${instance_name}"
}

# Get instance compose project name
get_instance_project_name() {
    local role_name="$1"
    local instance_name="$2"
    local base_project="${COMPOSE_PROJECT_NAME:-homelab}"
    echo "${base_project}-${role_name}-${instance_name}"
}

# Load role environment with instance-specific variables
load_role_env() {
    local role_name="$1"
    local instance_name="$2"
    local instance_dir=$(get_instance_dir "$role_name" "$instance_name")
    local role_env="$instance_dir/.env"
    
    # Load main environment first
    if [[ -f ".env" ]]; then
        set -a
        source .env
        set +a
    fi
    
    # Load instance environment
    if [[ -f "$role_env" ]]; then
        set -a
        source "$role_env"
        set +a
        print_info "Loaded instance environment: $role_env"
    fi
    
    # Set instance-specific variables
    export INSTANCE_NAME="$instance_name"
    export INSTANCE_DIR="$instance_dir"
    export COMPOSE_PROJECT_NAME=$(get_instance_project_name "$role_name" "$instance_name")
    
    # Set instance-specific domain prefix
    if [[ "$instance_name" != "default" ]]; then
        export INSTANCE_SUBDOMAIN="${instance_name}-"
    else
        export INSTANCE_SUBDOMAIN=""
    fi
}

# List instances of a role
list_role_instances() {
    local role_name="$1"
    
    print_header "Instances of Role: $role_name"
    
    if [[ ! -d "/opt/homelab/instances" ]]; then
        print_info "No instances directory found"
        return 0
    fi
    
    local found_instances=false
    for instance_dir in /opt/homelab/instances/${role_name}-*/; do
        if [[ -d "$instance_dir" ]]; then
            local instance_name=$(basename "$instance_dir" | sed "s/^${role_name}-//")
            local project_name=$(get_instance_project_name "$role_name" "$instance_name")
            
            echo -e "  • ${GREEN}$instance_name${NC}"
            echo -e "    Directory: $instance_dir"
            echo -e "    Project: $project_name"
            
            # Check if running
            load_role_env "$role_name" "$instance_name"
            if docker compose -f "$instance_dir/docker-compose.yml" ps -q &>/dev/null; then
                local running_containers=$(docker compose -f "$instance_dir/docker-compose.yml" ps --format "table {{.Service}}\t{{.Status}}" | tail -n +2)
                if [[ -n "$running_containers" ]]; then
                    echo -e "    Status: ${GREEN}Running${NC}"
                else
                    echo -e "    Status: ${YELLOW}Stopped${NC}"
                fi
            else
                echo -e "    Status: ${RED}Not deployed${NC}"
            fi
            echo ""
            found_instances=true
        fi
    done
    
    if [[ "$found_instances" == "false" ]]; then
        print_info "No instances found for role '$role_name'"
    fi
}

# Install a role instance
install_role() {
    local role_name="$1"
    local instance_name="$2"
    local instance_dir=$(setup_instance_dir "$role_name" "$instance_name")
    
    print_header "Installing Role: $role_name (Instance: $instance_name)"
    print_info "Instance directory: $instance_dir"
    print_info "Current working directory: $(pwd)"
    
    # Check if role has required files
    if [[ ! -f "$instance_dir/docker-compose.yml" ]]; then
        print_error "Role missing docker-compose.yml file"
        print_error "Looking for: $instance_dir/docker-compose.yml"
        print_info "Contents of instance directory:"
        ls -la "$instance_dir" || print_error "Directory does not exist"
        return 1
    fi
    
    # Load environment with instance-specific variables
    load_role_env "$role_name" "$instance_name"
    
    # Run pre-install script if it exists
    if [[ -f "$instance_dir/pre-install.sh" ]]; then
        print_info "Running pre-install script..."
        cd "$instance_dir" && bash pre-install.sh
        cd - > /dev/null
    fi
    
    # Create role-specific directories
    if [[ -f "$instance_dir/directories.txt" ]]; then
        print_info "Creating instance directories..."
        while IFS= read -r dir; do
            if [[ -n "$dir" && ! "$dir" =~ ^# ]]; then
                # Make directory paths relative to instance directory
                mkdir -p "$instance_dir/$dir"
            fi
        done < "$instance_dir/directories.txt"
    fi
    
    # Start the role services
    print_info "Starting $role_name ($instance_name) services..."
    docker compose -f "$instance_dir/docker-compose.yml" up -d
    
    if [[ $? -eq 0 ]]; then
        print_success "Role '$role_name' instance '$instance_name' installed successfully"
        
        # Run post-install script if it exists
        if [[ -f "$instance_dir/post-install.sh" ]]; then
            print_info "Running post-install script..."
            cd "$instance_dir" && bash post-install.sh
            cd - > /dev/null
        fi
        
        # Show access information
        if [[ -f "$instance_dir/access-info.txt" ]]; then
            print_header "Access Information"
            # Process the template with instance variables
            envsubst < "$instance_dir/access-info.txt"
        fi
    else
        print_error "Failed to install role '$role_name' instance '$instance_name'"
        return 1
    fi
}

# Uninstall a role instance
uninstall_role() {
    local role_name="$1"
    local instance_name="$2"
    local instance_dir=$(get_instance_dir "$role_name" "$instance_name")
    
    print_header "Uninstalling Role: $role_name (Instance: $instance_name)"
    
    if [[ ! -d "$instance_dir" ]]; then
        print_error "Instance '$instance_name' of role '$role_name' not found"
        return 1
    fi
    
    # Load environment
    load_role_env "$role_name" "$instance_name"
    
    # Run pre-uninstall script if it exists
    if [[ -f "$instance_dir/pre-uninstall.sh" ]]; then
        print_info "Running pre-uninstall script..."
        cd "$instance_dir" && bash pre-uninstall.sh
        cd - > /dev/null
    fi
    
    # Stop and remove services
    print_info "Stopping $role_name ($instance_name) services..."
    docker compose -f "$instance_dir/docker-compose.yml" down --volumes
    
    # Ask if user wants to remove data
    echo ""
    read -p "Remove instance data directory? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$instance_dir"
        print_success "Instance data removed"
    else
        print_info "Instance data preserved in: $instance_dir"
    fi
    
    # Run post-uninstall script if it exists
    if [[ -f "$instance_dir/post-uninstall.sh" ]] && [[ -d "$instance_dir" ]]; then
        print_info "Running post-uninstall script..."
        cd "$instance_dir" && bash post-uninstall.sh
        cd - > /dev/null
    fi
    
    print_success "Role '$role_name' instance '$instance_name' uninstalled"
}

# Show role instance status
show_role_status() {
    local role_name="$1"
    local instance_name="$2"
    local instance_dir=$(get_instance_dir "$role_name" "$instance_name")
    
    print_header "Role Status: $role_name (Instance: $instance_name)"
    
    if [[ ! -d "$instance_dir" ]]; then
        print_error "Instance '$instance_name' of role '$role_name' not found"
        return 1
    fi
    
    load_role_env "$role_name" "$instance_name"
    docker compose -f "$instance_dir/docker-compose.yml" ps
}

# Show role instance logs
show_role_logs() {
    local role_name="$1"
    local instance_name="$2"
    local instance_dir=$(get_instance_dir "$role_name" "$instance_name")
    
    print_header "Role Logs: $role_name (Instance: $instance_name)"
    
    if [[ ! -d "$instance_dir" ]]; then
        print_error "Instance '$instance_name' of role '$role_name' not found"
        return 1
    fi
    
    load_role_env "$role_name" "$instance_name"
    docker compose -f "$instance_dir/docker-compose.yml" logs -f
}

# Update role instance
update_role() {
    local role_name="$1"
    local instance_name="$2"
    local instance_dir=$(get_instance_dir "$role_name" "$instance_name")
    
    print_header "Updating Role: $role_name (Instance: $instance_name)"
    
    if [[ ! -d "$instance_dir" ]]; then
        print_error "Instance '$instance_name' of role '$role_name' not found"
        return 1
    fi
    
    load_role_env "$role_name" "$instance_name"
    
    # Pull latest images
    docker compose -f "$instance_dir/docker-compose.yml" pull
    
    # Restart services
    docker compose -f "$instance_dir/docker-compose.yml" up -d
    
    print_success "Role '$role_name' instance '$instance_name' updated"
}

# Edit role instance configuration
edit_role_config() {
    local role_name="$1"
    local instance_name="$2"
    local instance_dir=$(get_instance_dir "$role_name" "$instance_name")
    local role_env="$instance_dir/.env"
    
    print_header "Editing Role Configuration: $role_name (Instance: $instance_name)"
    
    # Setup instance directory if it doesn't exist
    if [[ ! -d "$instance_dir" ]]; then
        setup_instance_dir "$role_name" "$instance_name" > /dev/null
    fi
    
    if [[ ! -f "$role_env" ]]; then
        if [[ -f "$instance_dir/.env.example" ]]; then
            cp "$instance_dir/.env.example" "$role_env"
            print_info "Created .env from .env.example"
        else
            print_error "No .env or .env.example found for role"
            return 1
        fi
    fi
    
    # Use preferred editor
    local editor="${EDITOR:-nano}"
    $editor "$role_env"
}

# Parse instances from environment file
parse_instances() {
    local role_name="$1"
    local role_env_example="roles/$role_name/.env.example"
    
    if [[ -f "$role_env_example" ]]; then
        # Extract INSTANCES variable from .env.example
        local instances_line=$(grep "^INSTANCES=" "$role_env_example" | head -1)
        if [[ -n "$instances_line" ]]; then
            # Extract value after =, remove quotes
            local instances_value=$(echo "$instances_line" | sed 's/^INSTANCES=//; s/"//g; s/'\''//g')
            echo "$instances_value"
            return 0
        fi
    fi
    
    # Fall back to "default" if no INSTANCES declaration found
    echo "default"
}

# Get instance-specific variable value
get_instance_var() {
    local instance_name="$1"
    local var_name="$2"
    local role_name="$3"
    local role_env_example="roles/$role_name/.env.example"
    
    # Try instance-specific variable first
    local instance_var="${instance_name}_${var_name}"
    if [[ -f "$role_env_example" ]]; then
        local instance_value=$(grep "^${instance_var}=" "$role_env_example" | head -1 | sed 's/^[^=]*=//; s/"//g; s/'\''//g')
        if [[ -n "$instance_value" ]]; then
            echo "$instance_value"
            return 0
        fi
    fi
    
    # Fall back to global variable
    if [[ -f "$role_env_example" ]]; then
        local global_value=$(grep "^${var_name}=" "$role_env_example" | head -1 | sed 's/^[^=]*=//; s/"//g; s/'\''//g')
        if [[ -n "$global_value" ]]; then
            echo "$global_value"
            return 0
        fi
    fi
    
    # No value found
    echo ""
}

# Create instance-specific environment file
create_instance_env() {
    local role_name="$1"
    local instance_name="$2"
    local instance_dir="$3"
    local role_env_example="roles/$role_name/.env.example"
    local instance_env="$instance_dir/.env"
    
    if [[ ! -f "$role_env_example" ]]; then
        print_warning "No .env.example found for role $role_name" >&2
        return 1
    fi
    
    print_info "Creating instance-specific environment for $instance_name" >&2
    
    # Start with the example file as a base
    cp "$role_env_example" "$instance_env"
    
    # Override with instance-specific variables
    local temp_file=$(mktemp)
    
    # Process each line in the env file
    while IFS= read -r line; do
        # Skip comments, empty lines, and instance declarations
        if [[ "$line" =~ ^#.*$ ]] || [[ -z "$line" ]] || [[ "$line" =~ ^INSTANCES= ]] || [[ "$line" =~ ^[a-zA-Z0-9_]+_[A-Z_]+=.*$ ]]; then
            echo "$line" >> "$temp_file"
            continue
        fi
        
        # Check if this is a variable assignment
        if [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local default_value="${BASH_REMATCH[2]}"
            
            # Get instance-specific value if available
            local instance_value=$(get_instance_var "$instance_name" "$var_name" "$role_name")
            
            if [[ -n "$instance_value" ]]; then
                echo "${var_name}=${instance_value}" >> "$temp_file"
            else
                echo "$line" >> "$temp_file"
            fi
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$role_env_example"
    
    # Add instance-specific variables
    echo "" >> "$temp_file"
    echo "# Instance-specific variables (auto-generated)" >> "$temp_file"
    echo "INSTANCE_NAME=$instance_name" >> "$temp_file"
    echo "COMPOSE_PROJECT_NAME=$(get_instance_project_name "$role_name" "$instance_name")" >> "$temp_file"
    
    if [[ "$instance_name" != "default" ]]; then
        echo "INSTANCE_SUBDOMAIN=${instance_name}-" >> "$temp_file"
    else
        echo "INSTANCE_SUBDOMAIN=" >> "$temp_file"
    fi
    
    # Replace the instance env file
    mv "$temp_file" "$instance_env"
    
    print_success "Created instance environment: $instance_env" >&2
}

# Install all declared instances
install_all_instances() {
    local role_name="$1"
    local instances=$(parse_instances "$role_name")
    
    print_header "Installing All Instances for Role: $role_name"
    print_info "Declared instances: $instances"
    
    # Convert comma-separated list to array
    IFS=',' read -ra INSTANCE_ARRAY <<< "$instances"
    
    local success_count=0
    local total_count=${#INSTANCE_ARRAY[@]}
    
    for instance in "${INSTANCE_ARRAY[@]}"; do
        # Trim whitespace
        instance=$(echo "$instance" | xargs)
        
        print_header "Installing Instance: $instance"
        
        if install_role "$role_name" "$instance"; then
            ((success_count++))
            print_success "Instance '$instance' installed successfully"
        else
            print_error "Failed to install instance '$instance'"
        fi
        echo ""
    done
    
    print_header "Installation Summary"
    print_info "Successfully installed: $success_count/$total_count instances"
    
    if [[ $success_count -eq $total_count ]]; then
        print_success "All instances installed successfully!"
        return 0
    else
        print_warning "Some instances failed to install"
        return 1
    fi
}

# Show status of all declared instances
status_all_instances() {
    local role_name="$1"
    local instances=$(parse_instances "$role_name")
    
    print_header "Status of All Instances for Role: $role_name"
    print_info "Declared instances: $instances"
    
    # Convert comma-separated list to array
    IFS=',' read -ra INSTANCE_ARRAY <<< "$instances"
    
    for instance in "${INSTANCE_ARRAY[@]}"; do
        # Trim whitespace
        instance=$(echo "$instance" | xargs)
        
        echo ""
        show_role_status "$role_name" "$instance"
    done
}

# Uninstall all declared instances
uninstall_all_instances() {
    local role_name="$1"
    local instances=$(parse_instances "$role_name")
    
    print_header "Uninstalling All Instances for Role: $role_name"
    print_info "Declared instances: $instances"
    
    # Convert comma-separated list to array
    IFS=',' read -ra INSTANCE_ARRAY <<< "$instances"
    
    echo ""
    read -p "Are you sure you want to uninstall ALL instances? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Operation cancelled"
        return 0
    fi
    
    local success_count=0
    local total_count=${#INSTANCE_ARRAY[@]}
    
    for instance in "${INSTANCE_ARRAY[@]}"; do
        # Trim whitespace
        instance=$(echo "$instance" | xargs)
        
        print_header "Uninstalling Instance: $instance"
        
        if uninstall_role "$role_name" "$instance"; then
            ((success_count++))
            print_success "Instance '$instance' uninstalled successfully"
        else
            print_error "Failed to uninstall instance '$instance'"
        fi
        echo ""
    done
    
    print_header "Uninstallation Summary"
    print_info "Successfully uninstalled: $success_count/$total_count instances"
    
    if [[ $success_count -eq $total_count ]]; then
        print_success "All instances uninstalled successfully!"
        return 0
    else
        print_warning "Some instances failed to uninstall"
        return 1
    fi
}

# Setup instance directory with enhanced environment processing
setup_instance_dir() {
    local role_name="$1"
    local instance_name="$2"
    local instance_dir=$(get_instance_dir "$role_name" "$instance_name")
    
    # Create instance directory structure
    mkdir -p "$instance_dir"/{data,config,logs}
    
    # Copy role files to instance directory
    cp -r "roles/$role_name/"* "$instance_dir/"
    
    # Create instance-specific .env
    create_instance_env "$role_name" "$instance_name" "$instance_dir"
    
    echo "$instance_dir"
}

# Main script logic
main() {
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 0
    fi
    
    local role_name="$1"
    local instance_name="default"
    local action="install"
    
    # Parse arguments - flexible argument order with new multi-instance actions
    case $# in
        1)
            # ./install-role.sh mysql
            action="install"
            ;;
        2)
            # ./install-role.sh mysql install OR ./install-role.sh mysql prod OR ./install-role.sh mysql install-all
            if [[ "$2" =~ ^(install|uninstall|status|logs|update|config|list|install-all|status-all|uninstall-all)$ ]]; then
                action="$2"
            else
                instance_name="$2"
                action="install"
            fi
            ;;
        3)
            # ./install-role.sh mysql prod install
            instance_name="$2"
            action="$3"
            ;;
        *)
            print_error "Too many arguments"
            show_usage
            exit 1
            ;;
    esac
    
    # Check if we're in the right directory
    if [[ ! -f "docker-compose.yml" ]] || [[ ! -d "traefik" ]]; then
        print_error "This script must be run from the homelab root directory"
        exit 1
    fi
    
    # Validate role exists
    if ! check_role_exists "$role_name"; then
        show_usage
        exit 1
    fi
    
    # Special case for actions that don't need instance validation
    if [[ "$action" =~ ^(list|install-all|status-all|uninstall-all)$ ]]; then
        case "$action" in
            list)
                list_role_instances "$role_name"
                ;;
            install-all)
                install_all_instances "$role_name"
                ;;
            status-all)
                status_all_instances "$role_name"
                ;;
            uninstall-all)
                uninstall_all_instances "$role_name"
                ;;
        esac
        exit $?
    fi
    
    # Create instances directory if it doesn't exist
    mkdir -p /opt/homelab/instances
    
    case "$action" in
        install)
            install_role "$role_name" "$instance_name"
            ;;
        uninstall)
            uninstall_role "$role_name" "$instance_name"
            ;;
        status)
            show_role_status "$role_name" "$instance_name"
            ;;
        logs)
            show_role_logs "$role_name" "$instance_name"
            ;;
        update)
            update_role "$role_name" "$instance_name"
            ;;
        config)
            edit_role_config "$role_name" "$instance_name"
            ;;
        *)
            print_error "Unknown action: $action"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
