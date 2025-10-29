# 🪣 S3FS Manager

**A powerful, production-ready bash script for managing MinIO and S3 bucket mounts with multi-mount support, automatic configuration, and zero-downtime operations.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![s3fs](https://img.shields.io/badge/s3fs--fuse-compatible-orange.svg)](https://github.com/s3fs-fuse/s3fs-fuse)
[![MinIO](https://img.shields.io/badge/MinIO-Ready-red.svg)](https://min.io/)

---

## ✨ Why S3FS Manager?

Stop wrestling with manual s3fs configurations, cryptic mount commands, and fstab syntax. S3FS Manager is your Swiss Army knife for S3/MinIO bucket mounting—whether you're mounting one bucket or orchestrating dozens across multiple locations.

**Built for:** DevOps engineers, system administrators, data engineers, and anyone tired of `mount` command headaches.

### 🎯 Key Features

- 🔄 **Multi-Mount Support** - Mount the same bucket to multiple locations simultaneously without conflicts
- 🛡️ **Duplicate Prevention** - Intelligent detection and prevention of conflicting mount configurations
- 🤖 **Auto-Installation** - Dependencies installed automatically (s3fs-fuse, MinIO client)
- 🚀 **Boot Persistence** - Optional fstab integration for auto-mounting on system startup
- 🎨 **Beautiful CLI** - Color-coded output with clear status indicators and progress tracking
- 📊 **Comprehensive Listing** - Visualize all mounts with bucket-to-path relationships at a glance
- 🔐 **Secure Credentials** - Per-bucket credential management with proper permissions
- 💪 **Force Operations** - Override existing mounts and handle busy filesystems
- 🌐 **MinIO Integration** - Built-in bucket creation and validation using MinIO client
- 🔧 **Interactive & Non-Interactive** - Full support for both manual and automated workflows
- 🎯 **Smart Unmounting** - Unmount by bucket name, path, or all instances at once

---

## 📦 Installation

### Quick Start

```bash
# Download the script
curl -O https://raw.githubusercontent.com/SethBurkart123/S3FS_Manager/main/s3fs-manager.sh

# Make it executable
chmod +x s3fs-manager.sh

# Run with sudo (dependencies auto-install on first run)
sudo ./s3fs-manager.sh mount
```

### System Requirements

- **OS:** Ubuntu/Debian-based Linux distributions
- **Privileges:** Root/sudo access required
- **Network:** Access to your MinIO/S3 server
- **Dependencies:** Auto-installed on first run
  - s3fs-fuse
  - MinIO client (mc)
  - wget

---

## 🚀 Quick Examples

### Mount a Bucket (Interactive)

```bash
sudo ./s3fs-manager.sh mount
```

The script will guide you through:
- Server URL configuration
- Credential input
- Bucket selection/creation
- Mount point selection
- Auto-mount preferences

### Mount a Bucket (Non-Interactive)

```bash
sudo ./s3fs-manager.sh mount \
  --url http://minio_url:9000 \
  --access-key minioadmin \
  --secret-key minioadmin123 \
  --bucket my-data \
  --path /mnt/s3-data \
  --owner current \
  --auto-mount \
  --non-interactive
```

### Mount Same Bucket to Multiple Locations

```bash
# Mount to primary location
sudo ./s3fs-manager.sh mount -b shared-data -p /mnt/primary --auto-mount

# Mount to secondary location (no conflicts!)
sudo ./s3fs-manager.sh mount -b shared-data -p /mnt/secondary --auto-mount

# Mount to user home directory
sudo ./s3fs-manager.sh mount -b shared-data -p /home/user/data
```

### List All Mounts

```bash
./s3fs-manager.sh list
```

**Output:**
```
═══════════════════════════════════════════════════════
     S3FS Manager v2.0 - Multi-Bucket Mount Tool      
═══════════════════════════════════════════════════════

● Active Mounts:
  ► shared-data         → /mnt/primary
    ▪ Size: 1.0T, Used: 234G (24%)
    ▪ Owner: datauser

● Boot Mounts (fstab):
  ► shared-data         → /mnt/primary          [active]
  ► shared-data         → /mnt/secondary        [active]

● Bucket Summary:
  shared-data (2 mount points):
    ✓ /mnt/primary
    ✓ /mnt/secondary
```

### Unmount Operations

```bash
# Unmount specific path
sudo ./s3fs-manager.sh unmount --path /mnt/primary

# Unmount all instances of a bucket
sudo ./s3fs-manager.sh unmount --bucket shared-data --all

# Force unmount busy filesystem
sudo ./s3fs-manager.sh unmount --path /mnt/data --force
```

---

## 📖 Command Reference

### Commands

| Command | Description |
|---------|-------------|
| `mount` | Mount an S3/MinIO bucket to a local directory |
| `unmount` | Unmount a bucket or specific mount point |
| `list` | Display all active and configured mounts |
| `help` | Show usage information |

### Options

| Option | Alias | Description | Default |
|--------|-------|-------------|---------|
| `--url URL` | `-u` | MinIO/S3 server URL | `http://minio_url:9000` |
| `--access-key KEY` | `-a` | S3 access key ID | (required) |
| `--secret-key KEY` | `-s` | S3 secret access key | (required) |
| `--bucket NAME` | `-b` | Bucket name | `clp-archives` |
| `--path PATH` | `-p`, `-m` | Mount point path | `$HOME/bucket-name` |
| `--owner USER` | `-o` | Mount owner (use 'current' for current user) | (interactive) |
| `--auto-mount` | - | Add to /etc/fstab for boot persistence | (not set) |
| `--all` | - | Unmount all instances of a bucket | (not set) |
| `--non-interactive` | - | Run without prompts | (not set) |
| `--no-color` | - | Disable colored output | (not set) |
| `--force` | `-f` | Force operation (override conflicts) | (not set) |
| `--help` | `-h` | Show help message | - |

---

## 🔧 Advanced Usage

### Custom MinIO Server

```bash
sudo ./s3fs-manager.sh mount \
  -u https://s3.company.com:9000 \
  -a ACCESS_KEY \
  -s SECRET_KEY \
  -b production-logs \
  -p /var/log/s3-logs \
  --auto-mount
```

### Multiple Buckets Setup

```bash
# Mount multiple buckets for different purposes
sudo ./s3fs-manager.sh mount -b backups -p /mnt/backups --auto-mount
sudo ./s3fs-manager.sh mount -b media -p /mnt/media --auto-mount
sudo ./s3fs-manager.sh mount -b databases -p /mnt/databases --auto-mount
```

### CI/CD Pipeline Integration

```bash
#!/bin/bash
# deploy.sh

# Mount application data bucket
sudo ./s3fs-manager.sh mount \
  --url "$S3_ENDPOINT" \
  --access-key "$S3_ACCESS_KEY" \
  --secret-key "$S3_SECRET_KEY" \
  --bucket "$APP_BUCKET" \
  --path /app/data \
  --owner www-data \
  --non-interactive \
  --force

# Deploy application
./deploy-app.sh
```

### Docker Container Data Volumes

```bash
# Mount S3 bucket for container persistent storage
sudo ./s3fs-manager.sh mount \
  -b docker-volumes \
  -p /var/lib/docker/volumes/s3data \
  --owner root \
  --auto-mount

# Use in docker-compose.yml
# volumes:
#   - /var/lib/docker/volumes/s3data:/data
```

---

## 🏗️ Architecture

### How It Works

1. **Dependency Check** - Auto-installs s3fs-fuse and MinIO client if missing
2. **Credential Management** - Creates secure per-bucket credential files (`~/.passwd-s3fs-bucket`)
3. **Bucket Validation** - Connects to MinIO/S3 and creates bucket if it doesn't exist
4. **Mount Operation** - Mounts using s3fs with optimized parameters
5. **Persistence** - Optionally adds to /etc/fstab for automatic mounting at boot
6. **Verification** - Tests write access and confirms successful mount

### Security Features

- Credential files created with `600` permissions (owner read/write only)
- Per-bucket credential isolation
- User ownership control for mounted filesystems
- Secure credential handling (no passwords in process lists)

### Multi-Mount Intelligence

S3FS Manager prevents conflicts by:
- Tracking bucket-to-mountpoint relationships
- Detecting duplicate fstab entries before adding
- Allowing same bucket at different paths
- Preventing different buckets at same path (unless `--force`)

---

## 🐛 Troubleshooting

### Mount Fails with "Transport endpoint is not connected"

```bash
# Force unmount the stale mount
sudo ./s3fs-manager.sh unmount -p /mnt/bucket --force

# Remount
sudo ./s3fs-manager.sh mount -b bucket
```

### Permission Denied When Accessing Files

```bash
# Ensure correct ownership
sudo ./s3fs-manager.sh unmount -b bucket
sudo ./s3fs-manager.sh mount -b bucket --owner your-username
```

### Bucket Not Found

The script will automatically create the bucket if you have permissions. If it fails:
- Verify your access/secret keys have bucket creation permissions
- Check network connectivity to MinIO/S3 server
- Ensure bucket name follows S3 naming conventions

### Check Mount Status

```bash
# List all mounts
./s3fs-manager.sh list

# Check with system tools
mount | grep s3fs
df -h | grep s3fs
```

---

## 📝 Changelog

### Version 2.0 (Current)
- ✨ Multi-mount support for same bucket
- 🛡️ Duplicate prevention system
- 📊 Enhanced list command with relationships
- 🎯 Smart unmount by bucket or path
- 🔧 Improved error handling
- 🎨 Better color support detection

## 🙏 Acknowledgments

- [s3fs-fuse](https://github.com/s3fs-fuse/s3fs-fuse) - FUSE-based file system backed by Amazon S3
- [MinIO](https://min.io/) - High-performance object storage
- All contributors who have helped improve this tool

---

**Made with ❤️ for the DevOps community**

*Stop fighting with mount commands. Start mounting smarter.*
