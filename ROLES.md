# Role-Based Multi-Instance Container Management

This document describes the role-based architecture and multi-instance container management system for the docker-traefik-apps project.

## Overview

The role-based system allows you to:
- Deploy multiple isolated instances of the same service type
- Manage database, application, and web services as reusable templates
- Configure instance-specific settings like subdomains and data directories
- Scale services horizontally with proper isolation

## Role Management Script

The `install-role.sh` script provides comprehensive management for role-based deployments:

```bash
./install-role.sh <action> <role> [instance] [env_vars...]
```

### Actions
- `install` - Deploy a new role instance
- `uninstall` - Remove a role instance and optionally its data
- `status` - Show status of role instances
- `logs` - View logs for a role instance
- `config` - Show configuration for a role instance

### Examples

```bash
# Install default mysql instance
./install-role.sh install mysql

# Install named mysql instance for project-a
./install-role.sh install mysql project-a

# Install mysql with custom configuration
./install-role.sh install mysql dev MYSQL_ROOT_PASSWORD=dev123 EXPOSE_MYSQL=true

# Install multiple wordpress instances
./install-role.sh install wordpress blog
./install-role.sh install wordpress shop WORDPRESS_SUBDOMAIN=store

# Check status of all instances
./install-role.sh status mysql
./install-role.sh status wordpress

# View logs for specific instance
./install-role.sh logs mysql project-a

# Uninstall instance (keeps data)
./install-role.sh uninstall wordpress blog

# Uninstall instance and remove data
./install-role.sh uninstall wordpress blog --remove-data
```

## Available Roles

### MySQL Database (`mysql`)
- **Services**: MySQL 8.0, phpMyAdmin
- **Ports**: 3306 (MySQL), 80 (phpMyAdmin web interface)
- **Data**: Stored in `/opt/homelab/instances/mysql-<instance>/data`
- **Management**: Web-based phpMyAdmin interface
- **Key Variables**:
  - `MYSQL_ROOT_PASSWORD` - Root database password
  - `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DATABASE` - Application database
  - `EXPOSE_MYSQL` - Whether to expose MySQL port externally
  - `MYSQL_DASHBOARD_AUTH` - HTTP basic auth for phpMyAdmin

### PostgreSQL Database (`postgresql`)
- **Services**: PostgreSQL 15, pgAdmin
- **Ports**: 5432 (PostgreSQL), 80 (pgAdmin web interface)
- **Data**: Stored in `/opt/homelab/instances/postgresql-<instance>/data`
- **Management**: Web-based pgAdmin interface
- **Key Variables**:
  - `POSTGRES_PASSWORD` - Database superuser password
  - `POSTGRES_USER`, `POSTGRES_DB` - Application database
  - `EXPOSE_POSTGRES` - Whether to expose PostgreSQL port externally
  - `POSTGRES_DASHBOARD_AUTH` - HTTP basic auth for pgAdmin

### WordPress (`wordpress`)
- **Services**: WordPress with PHP-FPM, WP-CLI
- **Ports**: 80 (WordPress web interface)
- **Data**: Stored in `/opt/homelab/instances/wordpress-<instance>/data`
- **Management**: WordPress admin interface, WP-CLI commands
- **Key Variables**:
  - `WORDPRESS_DB_HOST` - Database host (default: mysql)
  - `WORDPRESS_DB_NAME`, `WORDPRESS_DB_USER`, `WORDPRESS_DB_PASSWORD` - Database connection
  - `WORDPRESS_SUBDOMAIN` - Custom subdomain (default: uses instance name)

## Instance Management

### Instance Isolation
Each instance is completely isolated with:
- **Unique container names**: `<role>-<instance>-<service>`
- **Separate data directories**: `/opt/homelab/instances/<role>-<instance>/`
- **Instance-specific subdomains**: `<instance>.<service>.yourdomain.com`
- **Isolated Docker networks**: Each instance uses the shared proxy network but has unique service names
- **Separate Docker Compose projects**: `<role>-<instance>` project names

### Instance Configuration
Instance configuration is managed through environment variables:
- `INSTANCE_NAME` - The instance identifier
- `INSTANCE_SUBDOMAIN` - Subdomain prefix (includes trailing dot if not empty)
- `COMPOSE_PROJECT_NAME` - Docker Compose project name for isolation

### Default vs Named Instances
- **Default instance**: Uses role name as instance name (e.g., `mysql`, `wordpress`)
- **Named instance**: Uses custom name (e.g., `project-a`, `dev`, `staging`)

## Network Architecture

All role instances connect to the shared `proxy` network created by the main Traefik setup. This allows:
- Centralized SSL certificate management
- Consistent routing rules
- Service discovery between instances
- Proper isolation while maintaining connectivity

## Data Persistence

Instance data is stored in `/opt/homelab/instances/<role>-<instance>/`:
- Database files and configuration
- Application uploads and content
- Service-specific configuration files
- Backup and restore points

Data directories are automatically created and properly configured with appropriate permissions.

## SSL and Domain Configuration

Each instance gets its own SSL certificate through Traefik's Let's Encrypt integration:
- Database management interfaces: `<instance>phpmyadmin.yourdomain.com`, `<instance>pgadmin.yourdomain.com`
- WordPress sites: `<instance>.yourdomain.com` or custom subdomain
- Automatic certificate renewal and management

## Role Development

### Creating New Roles
To create a new role:

1. Create role directory: `roles/<role-name>/`
2. Add `docker-compose.yml` with multi-instance support
3. Create `.env.example` with instance variables
4. Add optional scripts: `pre-install.sh`, `post-install.sh`
5. Create `access-info.txt` template for user information

### Multi-Instance Requirements
Roles must support multi-instance deployment:
- Use `${INSTANCE_NAME}` in container names and labels
- Use `${INSTANCE_SUBDOMAIN}` for domain routing
- Use `${COMPOSE_PROJECT_NAME}` for Docker Compose project naming
- Store data in mounted volumes that map to instance directories
- Ensure service names are unique across instances

### Environment Variable Template
All roles should include these standard variables in `.env.example`:
```bash
# Instance configuration (automatically set by install-role.sh)
INSTANCE_NAME=default
INSTANCE_SUBDOMAIN=
COMPOSE_PROJECT_NAME=role-default

# Global configuration (inherited from main .env)
DOMAIN=localhost
PUID=1000
PGID=1000
TZ=UTC
COMPOSE_FILE=docker-compose.yml

# Role-specific configuration
# Add role-specific variables here...
```

## Troubleshooting

### Common Issues
1. **Port conflicts**: Each instance uses unique container names and external routes
2. **Data persistence**: Ensure volume mounts point to instance-specific directories
3. **SSL certificates**: Verify domain DNS points to your server
4. **Service discovery**: Use container names for inter-service communication

### Debugging Commands
```bash
# Check container status
docker ps -a | grep <role>-<instance>

# View logs
./install-role.sh logs <role> <instance>

# Check network connectivity
docker network inspect proxy

# Verify environment configuration
./install-role.sh config <role> <instance>
```

## Migration and Backup

### Backup Instance Data
```bash
# Backup entire instance
tar -czf backup-<role>-<instance>-$(date +%Y%m%d).tar.gz /opt/homelab/instances/<role>-<instance>/

# Backup specific service data
tar -czf backup-mysql-data-$(date +%Y%m%d).tar.gz /opt/homelab/instances/mysql-<instance>/data/
```

### Restore Instance Data
```bash
# Stop instance
./install-role.sh uninstall <role> <instance>

# Restore data
tar -xzf backup-<role>-<instance>-YYYYMMDD.tar.gz

# Reinstall instance
./install-role.sh install <role> <instance>
```

This role-based architecture provides a scalable, maintainable way to deploy and manage multiple instances of containerized services with proper isolation and configuration management.

## Domain Configuration

Roles automatically use your main domain configuration:
- MySQL: `mysql.yourdomain.com` (if exposed)
- phpMyAdmin: `phpmyadmin.yourdomain.com`
- pgAdmin: `pgadmin.yourdomain.com`
- WordPress: `blog.yourdomain.com` (configurable subdomain)

## Security

- **Authentication**: Web interfaces can require authentication
- **SSL**: All web services get automatic SSL certificates
- **Network isolation**: Services only accessible through Traefik
- **Credential management**: Secure password generation and storage

## Backup and Maintenance

Each role can include its own backup scripts and maintenance procedures. Use the role management commands to:
- View logs for troubleshooting
- Update containers to latest versions
- Monitor service health

## Creating Custom Roles

To create a new role:

1. Create a directory in `roles/`
2. Add required files (at minimum `docker-compose.yml`)
3. Follow the standard role structure
4. Test with `./install-role.sh your-role install`

## Best Practices

1. **Always configure before installing**: Run `config` action first
2. **Use strong passwords**: Generate secure credentials for databases
3. **Check dependencies**: Some roles require others (WordPress needs MySQL)
4. **Monitor resources**: Check logs and status regularly
5. **Backup data**: Important data should be backed up regularly

## Troubleshooting

- **Check logs**: `./install-role.sh <role> logs`
- **Verify status**: `./install-role.sh <role> status`
- **Check networking**: Ensure proxy network exists
- **Validate configuration**: Review `.env` files for errors
