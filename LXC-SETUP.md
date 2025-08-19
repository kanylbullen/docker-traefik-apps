# 🐧 LXC Container Setup Guide

This guide explains how to run the homelab setup in LXC containers (like Proxmox VE).

## 🔍 LXC Detection

The setup script automatically detects when running in an LXC container and adapts accordingly:

- ✅ **Works automatically**: Traefik, Portainer, Cloudflare Tunnel
- ⚠️ **Requires configuration**: Tailscale (needs TUN device access)
- 🔧 **Alternative solutions**: Use Cloudflare Tunnel for remote access

## 🚀 Quick Start (LXC-Compatible)

The enhanced setup automatically handles LXC environments:

```bash
# Run the setup - it will detect LXC and adapt
./setup.sh

# Tailscale will be automatically disabled if TUN device is unavailable
# All other services will work normally
```

## 🌐 Remote Access Options in LXC

### Option 1: Cloudflare Tunnel (Recommended for LXC)

Cloudflare Tunnel works perfectly in LXC containers:

```bash
# Configure in .env
CLOUDFLARED_TOKEN=your-cloudflare-tunnel-token

# The setup will automatically enable it
```

**Benefits:**
- ✅ No TUN device required
- ✅ Zero-trust security
- ✅ Works through NAT/firewalls
- ✅ Free tier available

### Option 2: Enable Tailscale in LXC (Recommended Method)

**Use the Proxmox Community Script** (easiest and most reliable):

```bash
# On the Proxmox VE host, run:
bash -c "$(wget -qLO - https://github.com/community-scripts/ProxmoxVE/raw/main/misc/add-tailscale-lxc.sh)"

# Follow the script prompts to:
# 1. Select your container
# 2. Configure TUN device access
# 3. Restart the container
```

**Benefits:**
- ✅ Automated configuration
- ✅ Proper security settings
- ✅ Community maintained
- ✅ Works with both privileged and unprivileged containers

**More info:** https://community-scripts.github.io/ProxmoxVE/scripts?id=add-tailscale-lxc

#### Manual Configuration (Advanced Users)

If you prefer manual configuration:

#### For Proxmox VE:

```bash
# On the Proxmox host, edit the container config
nano /etc/pve/lxc/CONTAINER_ID.conf

# Add these lines:
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file

# Restart the container
pct restart CONTAINER_ID
```

#### For other LXC hosts:

```bash
# Add to container config
echo "lxc.cgroup2.devices.allow: c 10:200 rwm" >> /var/lib/lxc/CONTAINER_NAME/config
echo "lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file" >> /var/lib/lxc/CONTAINER_NAME/config

# Restart container
lxc-stop -n CONTAINER_NAME
lxc-start -n CONTAINER_NAME
```

### Option 3: Port Forwarding (Simple)

Forward ports from the LXC host:

```bash
# On Proxmox/LXC host
iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination CONTAINER_IP:80
iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination CONTAINER_IP:443
```

## 🔧 LXC-Specific Configuration

### Recommended LXC Settings

For optimal Docker performance in LXC:

```bash
# In container config
lxc.apparmor.profile: unconfined
lxc.cap.drop: 
lxc.cgroup2.devices.allow: a
lxc.mount.auto: "proc:rw sys:rw"
```

### Container Requirements

**Minimum resources:**
- RAM: 1GB (2GB recommended)
- Disk: 8GB (20GB recommended)
- CPU: 1 core (2 cores recommended)

**Required features:**
- Unprivileged container: ✅ Supported
- Privileged container: ✅ Supported (easier setup)
- Nesting: ✅ Enable for Docker support

### Proxmox VE Container Creation

```bash
# Create container with Docker support
pct create 100 local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst \
  --hostname homelab \
  --memory 2048 \
  --rootfs local-lvm:8 \
  --cores 2 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --features nesting=1 \
  --unprivileged 1

# Start container
pct start 100

# Enter container
pct enter 100
```

## 🛠️ Troubleshooting LXC Issues

### Docker Won't Start

```bash
# Check if Docker daemon is running
systemctl status docker

# If failed, check logs
journalctl -u docker.service

# Common fix: enable cgroup delegation
mkdir -p /etc/systemd/system/user@.service.d
echo -e "[Delegate]\nDelegate=yes" > /etc/systemd/system/user@.service.d/delegate.conf
systemctl daemon-reload
systemctl restart docker
```

### Permission Issues

```bash
# Add user to docker group
usermod -aG docker $USER
newgrp docker

# Or run as root (in container)
sudo su -
```

### Network Issues

```bash
# Check if container can reach internet
ping 8.8.8.8

# Check DNS resolution
nslookup google.com

# Restart networking if needed
systemctl restart networking
```

### TUN Device Issues

```bash
# Check if TUN device exists
ls -la /dev/net/tun

# Check kernel module
lsmod | grep tun

# If missing, configure on host (see Tailscale section above)
```

## 📊 Monitoring LXC Performance

```bash
# Container resource usage (from host)
pct status CONTAINER_ID
pct config CONTAINER_ID

# Inside container
./health-check.sh resources
htop
```

## 🔐 Security Considerations

### LXC Security Benefits
- ✅ Container isolation
- ✅ Resource limits
- ✅ Reduced attack surface
- ✅ Easy backup/restore

### Additional Security
- Use unprivileged containers when possible
- Limit capabilities and devices
- Regular updates of container and host
- Monitor resource usage

## 🚀 Performance Optimization

### Container Settings
```bash
# Optimize for Docker workloads
echo "vm.max_map_count=262144" >> /etc/sysctl.conf
sysctl -p
```

### Host Settings
```bash
# On Proxmox host - optimize for containers
echo "net.bridge.bridge-nf-call-iptables = 1" >> /etc/sysctl.conf
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p
```

## 🔄 Backup and Migration

### Container Backup (Proxmox)
```bash
# Backup container
vzdump CONTAINER_ID --storage local --mode snapshot

# Restore container
pct restore CONTAINER_ID /var/lib/vz/dump/vzdump-lxc-CONTAINER_ID-*.tar.lz4
```

### Application Backup
```bash
# Inside container - backup homelab data
./backup.sh backup

# Copy backup to host
scp backups/*.tar.gz host:/backup/location/
```

## 💡 Pro Tips for LXC

1. **Use unprivileged containers** for better security
2. **Enable nesting** for Docker support
3. **Set proper resource limits** to prevent resource exhaustion
4. **Use Cloudflare Tunnel** instead of Tailscale for simplicity
5. **Regular backups** - LXC makes this easy
6. **Monitor logs** - `journalctl -f` for real-time monitoring
7. **Keep host updated** - LXC security depends on host security

## 🎯 Recommended LXC Setup

```bash
# Optimal LXC container for homelab
pct create 100 local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst \
  --hostname homelab \
  --memory 2048 \
  --rootfs local-lvm:20 \
  --cores 2 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --features nesting=1,keyctl=1 \
  --unprivileged 1 \
  --onboot 1

# Configure for Docker
echo "lxc.apparmor.profile: unconfined" >> /etc/pve/lxc/100.conf
echo "lxc.cgroup2.devices.allow: a" >> /etc/pve/lxc/100.conf

# Start and enter
pct start 100
pct enter 100

# Run homelab setup
git clone <your-repo>
cd docker-traefik-apps
./setup.sh
```

This configuration provides the best balance of security, performance, and compatibility for running Docker-based homelabs in LXC containers.
