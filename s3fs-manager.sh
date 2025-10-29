#!/bin/bash

# S3FS Manager Script - Complete MinIO/S3 bucket mount management
# Version 2.0 - Multi-bucket support with duplicate prevention
# Usage: ./s3fs-manager.sh [command] [options]

# Detect color support
if [ -t 1 ] && [ -n "$TERM" ] && which tput >/dev/null 2>&1; then
    ncolors=$(tput colors 2>/dev/null || echo 0)
    if [ "$ncolors" -ge 8 ]; then
        USE_COLOR=true
    else
        USE_COLOR=false
    fi
else
    USE_COLOR=false
fi

# Color definitions with proper escaping
if [ "$USE_COLOR" = true ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    PURPLE=''
    CYAN=''
    BOLD=''
    NC=''
fi

# Functions for colored output using printf
print_success() { printf "%b✓ %s%b\n" "$GREEN" "$1" "$NC"; }
print_error() { printf "%b✗ %s%b\n" "$RED" "$1" "$NC"; }
print_info() { printf "%b→ %s%b\n" "$YELLOW" "$1" "$NC"; }
print_header() { printf "%b%s%b\n" "$BLUE" "$1" "$NC"; }
print_detail() { printf "%b  ▪ %s%b\n" "$CYAN" "$1" "$NC"; }
print_warning() { printf "%b⚠ %s%b\n" "$YELLOW" "$1" "$NC"; }

# Default values
DEFAULT_URL=""
DEFAULT_BUCKET=""
COMMAND=""

# Variables for arguments
URL=""
ACCESS_KEY=""
SECRET_KEY=""
BUCKET=""
MOUNT_POINT=""
USER=""
AUTO_MOUNT=""
FORCE=""
NON_INTERACTIVE=""
NO_COLOR=""
REMOVE_DIR=""
ALL_INSTANCES=""

# Show usage
show_usage() {
    cat << EOF
$(printf "%b═══════════════════════════════════════════════════════%b\n" "$PURPLE" "$NC")
$(printf "%b     S3FS Manager v2.0 - Multi-Bucket Mount Tool      %b\n" "$BLUE" "$NC")
$(printf "%b═══════════════════════════════════════════════════════%b\n" "$PURPLE" "$NC")

$(printf "%bUsage:%b %s <command> [options]\n" "$YELLOW" "$NC" "$0")

$(printf "%bCommands:%b\n" "$YELLOW" "$NC")
  $(printf "%bmount%b       Mount a bucket (creates if not exists)\n" "$GREEN" "$NC")
  $(printf "%bunmount%b     Unmount a bucket or path\n" "$GREEN" "$NC")
  $(printf "%blist%b        List all s3fs mounts with relationships\n" "$GREEN" "$NC")
  $(printf "%bhelp%b        Show this help\n" "$GREEN" "$NC")

$(printf "%bOptions:%b\n" "$YELLOW" "$NC")
  -u, --url URL              MinIO/S3 server URL (default: $DEFAULT_URL)
  -a, --access-key KEY       Access key ID
  -s, --secret-key KEY       Secret access key
  -b, --bucket NAME          Bucket name (default: $DEFAULT_BUCKET)
  -p, --path PATH            Mount point path (alias for -m)
  -m, --mount-point PATH     Mount point path
  -o, --owner USER           Mount owner (use 'current' for current user)
  --auto-mount               Add to /etc/fstab for boot persistence
  --all                      Unmount all instances of a bucket
  --non-interactive          Run without prompts
  --no-color                 Disable colored output
  -f, --force                Force operation (override/unmount)

$(printf "%bExamples:%b\n" "$YELLOW" "$NC")
  $(printf "%b# Mount bucket to default location%b\n" "$CYAN" "$NC")
  $0 mount -a mykey -s mysecret -b mybucket

  $(printf "%b# Mount same bucket to multiple locations%b\n" "$CYAN" "$NC")
  $0 mount -b mybucket -p /mnt/data1 --auto-mount
  $0 mount -b mybucket -p /mnt/data2 --auto-mount

  $(printf "%b# Unmount specific path%b\n" "$CYAN" "$NC")
  $0 unmount -p /mnt/data1

  $(printf "%b# Unmount all instances of a bucket%b\n" "$CYAN" "$NC")
  $0 unmount -b mybucket --all

  $(printf "%b# List all mounts and relationships%b\n" "$CYAN" "$NC")
  $0 list

EOF
}

# Parse command line arguments
parse_args() {
    COMMAND="$1"
    shift
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--url)
                URL="$2"
                shift 2
                ;;
            -a|--access-key)
                ACCESS_KEY="$2"
                shift 2
                ;;
            -s|--secret-key)
                SECRET_KEY="$2"
                shift 2
                ;;
            -b|--bucket)
                BUCKET="$2"
                shift 2
                ;;
            -p|--path|-m|--mount-point)
                MOUNT_POINT="$2"
                shift 2
                ;;
            -o|--owner)
                USER="$2"
                shift 2
                ;;
            --auto-mount)
                AUTO_MOUNT="yes"
                shift
                ;;
            --all)
                ALL_INSTANCES="yes"
                shift
                ;;
            --non-interactive)
                NON_INTERACTIVE="yes"
                shift
                ;;
            --no-color)
                RED=''
                GREEN=''
                YELLOW=''
                BLUE=''
                PURPLE=''
                CYAN=''
                BOLD=''
                NC=''
                USE_COLOR=false
                shift
                ;;
            -f|--force)
                FORCE="yes"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo "Please run this script with sudo or as root"
        exit 1
    fi
}

# Function to check for duplicate fstab entries
check_fstab_duplicate() {
    local bucket="$1"
    local mount_point="$2"
    
    # Check for exact duplicate (same bucket and same mount point)
    if grep -q "^s3fs#$bucket $mount_point " /etc/fstab 2>/dev/null; then
        return 0  # Duplicate found
    fi
    
    return 1  # No duplicate
}

# Function to add to fstab with duplicate checking
add_to_fstab_safe() {
    local bucket="$1"
    local mount_point="$2"
    local passwd_file="$3"
    local url="$4"
    local uid="$5"
    local gid="$6"
    
    # Build the fstab line
    local fstab_line="s3fs#$bucket $mount_point fuse _netdev,passwd_file=$passwd_file,url=$url,use_path_request_style,allow_other,uid=$uid,gid=$gid 0 0"
    
    # Check if this exact line already exists
    if grep -Fxq "$fstab_line" /etc/fstab 2>/dev/null; then
        print_info "Exact entry already exists in /etc/fstab (skipping)"
        return 0
    fi
    
    # Check if same mount point is used for different bucket
    if grep -qE "^[^#].*[[:space:]]${mount_point}[[:space:]]" /etc/fstab 2>/dev/null; then
        local existing_entry=$(grep -E "^[^#].*[[:space:]]${mount_point}[[:space:]]" /etc/fstab | head -1)
        
        # Check if it's an s3fs mount
        if echo "$existing_entry" | grep -q "s3fs#"; then
            local existing_bucket=$(echo "$existing_entry" | cut -d'#' -f2 | cut -d' ' -f1)
            if [ "$existing_bucket" != "$bucket" ]; then
                if [ "$FORCE" = "yes" ]; then
                    print_warning "Replacing existing mount of $existing_bucket at $mount_point"
                    sed -i "\|${mount_point}[[:space:]]|d" /etc/fstab
                else
                    print_error "Mount point $mount_point already used for bucket $existing_bucket"
                    print_info "Use --force to override"
                    return 1
                fi
            else
                # Same bucket, same mount point but different options - update
                print_info "Updating existing entry for $bucket at $mount_point"
                sed -i "\|^s3fs#$bucket $mount_point |d" /etc/fstab
            fi
        else
            print_error "Mount point $mount_point already used by non-s3fs filesystem"
            return 1
        fi
    fi
    
    # Safe to add
    echo "$fstab_line" >> /etc/fstab
    print_success "Added to /etc/fstab for auto-mount at boot"
    return 0
}

# Get all mount points for a specific bucket
get_bucket_mounts() {
    local bucket="$1"
    
    # Check both mounted filesystems and fstab
    local mounts=""
    
    # From currently mounted
    while read -r line; do
        local mp=$(echo "$line" | awk '{print $3}')
        # Check if this mount point is for our bucket
        if mount | grep "$mp" | grep -qE "s3fs.*$bucket|s3fs#$bucket"; then
            mounts="${mounts}${mp}\n"
        elif [ "$(basename "$mp")" = "$bucket" ]; then
            # Check if mount point ends with bucket name
            if mount | grep -q "$mp.*fuse.s3fs"; then
                mounts="${mounts}${mp}\n"
            fi
        fi
    done < <(mount | grep -E "s3fs|fuse.s3fs")
    
    # From fstab
    while read -r line; do
        local mp=$(echo "$line" | awk '{print $2}')
        mounts="${mounts}${mp}\n"
    done < <(grep "^s3fs#$bucket " /etc/fstab 2>/dev/null)
    
    # Remove duplicates and empty lines
    echo -e "$mounts" | sort -u | grep -v '^$'
}

# Install dependencies (same as before)
install_dependencies() {
    local deps_installed=false
    
    if ! command -v s3fs &> /dev/null; then
        print_info "Installing s3fs-fuse..."
        apt-get update -qq
        if apt-get install -y -qq s3fs > /dev/null 2>&1; then
            print_success "s3fs installed"
            deps_installed=true
        else
            print_error "Failed to install s3fs"
            exit 1
        fi
    fi
    
    if [ -f /etc/fuse.conf ]; then
        if ! grep -q '^user_allow_other' /etc/fuse.conf; then
            cp /etc/fuse.conf /etc/fuse.conf.backup 2>/dev/null
            sed -i 's/^#user_allow_other/user_allow_other/' /etc/fuse.conf 2>/dev/null || echo "user_allow_other" >> /etc/fuse.conf
            print_success "FUSE configured for user_allow_other"
        fi
    else
        echo "user_allow_other" > /etc/fuse.conf
        print_success "Created /etc/fuse.conf with user_allow_other"
    fi
    
    if ! command -v mc &> /dev/null; then
        print_info "Installing MinIO client (mc)..."
        
        ARCH=$(uname -m)
        case $ARCH in
            x86_64|amd64)
                MC_URL="https://dl.min.io/client/mc/release/linux-amd64/mc"
                ;;
            aarch64|arm64)
                MC_URL="https://dl.min.io/client/mc/release/linux-arm64/mc"
                ;;
            *)
                print_error "Unsupported architecture for mc: $ARCH"
                return
                ;;
        esac
        
        if wget -q "$MC_URL" -O /usr/local/bin/mc 2>/dev/null; then
            chmod +x /usr/local/bin/mc
            if command -v mc &> /dev/null; then
                print_success "MinIO client (mc) installed"
                deps_installed=true
            fi
        fi
    fi
    
    if ! command -v wget &> /dev/null; then
        apt-get install -y -qq wget > /dev/null 2>&1
    fi
    
    if [ "$deps_installed" = true ]; then
        print_success "All dependencies installed"
    fi
}

# Setup bucket (same as before)
setup_bucket() {
    local url="$1"
    local access_key="$2"
    local secret_key="$3"
    local bucket="$4"
    local user="$5"
    
    if ! command -v mc &> /dev/null; then
        print_info "MinIO client not available, skipping bucket creation check"
        return 1
    fi
    
    print_info "Configuring MinIO connection..."
    
    if sudo -u "$user" mc alias set myminio "$url" "$access_key" "$secret_key" --api s3v4 &>/dev/null; then
        print_success "MinIO connection configured"
    else
        print_error "Failed to configure MinIO connection"
        return 1
    fi
    
    print_info "Checking bucket '$bucket'..."
    
    if sudo -u "$user" mc ls myminio/"$bucket" &>/dev/null; then
        print_success "Bucket '$bucket' exists"
        return 0
    else
        print_info "Bucket '$bucket' not found, creating..."
        
        if sudo -u "$user" mc mb myminio/"$bucket" 2>/dev/null; then
            print_success "Bucket '$bucket' created successfully"
            return 0
        else
            local error_output
            error_output=$(sudo -u "$user" mc mb myminio/"$bucket" 2>&1)
            
            if echo "$error_output" | grep -qi "bucket.*already.*exist"; then
                print_success "Bucket '$bucket' already exists"
                return 0
            else
                print_error "Failed to create bucket '$bucket'"
                return 1
            fi
        fi
    fi
}

# Enhanced list function showing all relationships
list_mounts() {
    print_header "S3FS Mount Overview"
    printf "%b═══════════════════════════════════════════════════════%b\n" "$PURPLE" "$NC"
    
    # Create a mapping of buckets to mount points
    declare -A bucket_map
    
    # Parse currently mounted filesystems
    local mounts
    mounts=$(mount | grep -E "s3fs|fuse.s3fs")
    
    if [ -n "$mounts" ]; then
        printf "\n%b● Active Mounts:%b\n" "$GREEN" "$NC"
        echo "$mounts" | while read -r line; do
            local mountpoint=$(echo "$line" | awk '{print $3}')
            local source=$(echo "$line" | awk '{print $1}')
            
            # Extract bucket name
            local bucket=""
            if echo "$source" | grep -q "s3fs#"; then
                bucket=$(echo "$source" | sed 's/s3fs#//')
            else
                bucket=$(basename "$mountpoint")
            fi
            
            # Get mount details
            local size=$(df -h "$mountpoint" 2>/dev/null | tail -1 | awk '{print "Size: "$2", Used: "$3" ("$5")"}')
            local owner=$(stat -c '%U' "$mountpoint" 2>/dev/null)
            
            printf "  %b►%b %b%-20s%b → %s\n" "$CYAN" "$NC" "$BOLD" "$bucket" "$NC" "$mountpoint"
            [ -n "$size" ] && print_detail "$size"
            [ -n "$owner" ] && print_detail "Owner: $owner"
        done
    else
        print_info "No active s3fs mounts"
    fi
    
    # Parse fstab entries
    local fstab_entries
    fstab_entries=$(grep -E "^s3fs#" /etc/fstab 2>/dev/null)
    
    if [ -n "$fstab_entries" ]; then
        printf "\n%b● Boot Mounts (fstab):%b\n" "$BLUE" "$NC"
        echo "$fstab_entries" | while read -r line; do
            local source=$(echo "$line" | awk '{print $1}')
            local mountpoint=$(echo "$line" | awk '{print $2}')
            local bucket=$(echo "$source" | sed 's/s3fs#//')
            
            # Check if currently mounted
            local status="[configured]"
            if mount | grep -q " $mountpoint "; then
                status="${GREEN}[active]${NC}"
            else
                status="${YELLOW}[inactive]${NC}"
            fi
            
            printf "  %b►%b %b%-20s%b → %-30s %b\n" "$CYAN" "$NC" "$BOLD" "$bucket" "$NC" "$mountpoint" "$status"
        done
    else
        print_info "No entries in /etc/fstab"
    fi
    
    # Show bucket-centric view
    printf "\n%b● Bucket Summary:%b\n" "$PURPLE" "$NC"
    
    # Collect all unique buckets
    local all_buckets=""
    all_buckets+=$(mount | grep -E "s3fs|fuse.s3fs" | awk '{print $3}' | xargs -I {} basename {} 2>/dev/null)
    all_buckets+=$'\n'
    all_buckets+=$(grep "^s3fs#" /etc/fstab 2>/dev/null | cut -d'#' -f2 | cut -d' ' -f1)
    
    local unique_buckets=$(echo "$all_buckets" | sort -u | grep -v '^$')
    
    if [ -n "$unique_buckets" ]; then
        echo "$unique_buckets" | while read -r bucket; do
            [ -z "$bucket" ] && continue
            
            local mount_points=$(get_bucket_mounts "$bucket")
            local mount_count=$(echo "$mount_points" | grep -c .)
            
            printf "  %b%s%b (%d mount point%s):\n" "$BOLD" "$bucket" "$NC" "$mount_count" "$([ $mount_count -ne 1 ] && echo 's')"
            echo "$mount_points" | while read -r mp; do
                [ -z "$mp" ] && continue
                local status=""
                if mount | grep -q " $mp "; then
                    status="${GREEN}✓${NC}"
                else
                    status="${YELLOW}○${NC}"
                fi
                printf "    %b %s\n" "$status" "$mp"
            done
        done
    else
        print_info "No buckets configured"
    fi
    
    echo ""
}

# Select user (same as before)
select_user() {
    if [ "$USER" = "current" ]; then
        USER=$(who am i | awk '{print $1}')
        [ -z "$USER" ] && USER=$(logname 2>/dev/null)
        [ -z "$USER" ] && USER="$SUDO_USER"
        [ -z "$USER" ] && USER="root"
        return
    fi
    
    if [ -n "$USER" ]; then
        if ! id -u "$USER" &> /dev/null; then
            print_error "User '$USER' does not exist"
            exit 1
        fi
        return
    fi
    
    printf "%bSelect User for Mount Ownership%b\n" "$YELLOW" "$NC"
    
    local USERS
    mapfile -t USERS < <(getent passwd | awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' | sort)
    
    CURRENT_USER=$(who am i | awk '{print $1}')
    [ -z "$CURRENT_USER" ] && CURRENT_USER=$(logname 2>/dev/null)
    [ -z "$CURRENT_USER" ] && CURRENT_USER="$SUDO_USER"
    
    if [ -n "$CURRENT_USER" ]; then
        local found=0
        for user in "${USERS[@]}"; do
            if [ "$user" = "$CURRENT_USER" ]; then
                found=1
                break
            fi
        done
        if [ $found -eq 0 ]; then
            USERS=("$CURRENT_USER" "${USERS[@]}")
        fi
    fi
    
    if [ ${#USERS[@]} -eq 0 ]; then
        USERS=("root")
    fi
    
    PS3="Select user (enter number): "
    select USER in "${USERS[@]}"; do
        if [ -n "$USER" ]; then
            print_success "Selected: $USER"
            break
        fi
    done
}

# Mount function with duplicate checking
mount_bucket() {
    print_header "Mount S3/MinIO Bucket"
    printf "%b═══════════════════════════════════════════════════════%b\n" "$PURPLE" "$NC"
    echo ""
    
    install_dependencies
    
    # Interactive mode parameter collection
    if [ "$NON_INTERACTIVE" != "yes" ]; then
        if [ -z "$URL" ]; then
            printf "%bMinIO/S3 Server URL%b\n" "$YELLOW" "$NC"
            echo "Default: $DEFAULT_URL"
            read -r -p "Press Enter for default or type URL: " URL
            [ -z "$URL" ] && URL="$DEFAULT_URL"
        fi
        
        if [ -z "$ACCESS_KEY" ]; then
            while true; do
                read -r -p "Access Key ID: " ACCESS_KEY
                [ -n "$ACCESS_KEY" ] && break
                print_error "Access Key cannot be empty"
            done
        fi
        
        if [ -z "$SECRET_KEY" ]; then
            while true; do
                read -r -s -p "Secret Access Key: " SECRET_KEY
                echo ""
                [ -n "$SECRET_KEY" ] && break
                print_error "Secret Key cannot be empty"
            done
        fi
        
        if [ -z "$BUCKET" ]; then
            printf "%bBucket Name%b\n" "$YELLOW" "$NC"
            echo "Default: $DEFAULT_BUCKET"
            read -r -p "Press Enter for default or type name: " BUCKET
            [ -z "$BUCKET" ] && BUCKET="$DEFAULT_BUCKET"
        fi
        
        if [ -z "$USER" ]; then
            select_user
        fi
        
        if [ -z "$MOUNT_POINT" ]; then
            USER_HOME=$(getent passwd "$USER" | cut -d: -f6)
            [ -z "$USER_HOME" ] && USER_HOME="/home/$USER"
            DEFAULT_MOUNT="$USER_HOME/$BUCKET"
            
            printf "%bMount Point%b\n" "$YELLOW" "$NC"
            echo "Default: $DEFAULT_MOUNT"
            
            # Show existing mounts of this bucket if any
            local existing_mounts=$(get_bucket_mounts "$BUCKET" 2>/dev/null)
            if [ -n "$existing_mounts" ]; then
                print_info "This bucket is already mounted at:"
                echo "$existing_mounts" | while read -r mp; do
                    [ -n "$mp" ] && echo "  • $mp"
                done
            fi
            
            read -r -p "Press Enter for default or type path: " MOUNT_POINT
            [ -z "$MOUNT_POINT" ] && MOUNT_POINT="$DEFAULT_MOUNT"
        fi
        
        if [ -z "$AUTO_MOUNT" ]; then
            read -r -p "Add to /etc/fstab for auto-mount at boot? (y/N): " AUTO_MOUNT
            [[ "$AUTO_MOUNT" =~ ^[Yy]$ ]] && AUTO_MOUNT="yes" || AUTO_MOUNT="no"
        fi
    else
        # Non-interactive mode defaults
        [ -z "$URL" ] && URL="$DEFAULT_URL"
        [ -z "$BUCKET" ] && BUCKET="$DEFAULT_BUCKET"
        
        if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
            print_error "Non-interactive mode requires --access-key and --secret-key"
            exit 1
        fi
        
        if [ -z "$USER" ] || [ "$USER" = "current" ]; then
            USER=$(who am i | awk '{print $1}')
            [ -z "$USER" ] && USER=$(logname 2>/dev/null)
            [ -z "$USER" ] && USER="$SUDO_USER"
            [ -z "$USER" ] && USER="root"
        fi
        
        if [ -z "$MOUNT_POINT" ]; then
            USER_HOME=$(getent passwd "$USER" | cut -d: -f6)
            [ -z "$USER_HOME" ] && USER_HOME="/home/$USER"
            MOUNT_POINT="$USER_HOME/$BUCKET"
        fi
    fi
    
    # Check if already mounted at this location
    if mount | grep -q " $MOUNT_POINT "; then
        if [ "$FORCE" != "yes" ]; then
            print_warning "Mount point $MOUNT_POINT is already in use"
            print_info "Use --force to remount"
            exit 1
        else
            print_info "Unmounting existing mount at $MOUNT_POINT..."
            umount "$MOUNT_POINT" 2>/dev/null
        fi
    fi
    
    setup_bucket "$URL" "$ACCESS_KEY" "$SECRET_KEY" "$BUCKET" "$USER"
    
    # Create credentials file
    USER_HOME=$(getent passwd "$USER" | cut -d: -f6)
    PASSWD_FILE="$USER_HOME/.passwd-s3fs-$BUCKET"
    
    print_info "Setting up mount for $BUCKET at $MOUNT_POINT..."
    
    echo "${ACCESS_KEY}:${SECRET_KEY}" > "$PASSWD_FILE"
    chmod 600 "$PASSWD_FILE"
    chown "$USER:$USER" "$PASSWD_FILE"
    print_success "Credentials file created"
    
    if [ ! -d "$MOUNT_POINT" ]; then
        mkdir -p "$MOUNT_POINT"
        print_success "Mount directory created"
    fi
    chown "$USER:$USER" "$MOUNT_POINT" 2>/dev/null
    
    print_info "Mounting filesystem..."
    
    MOUNT_OUTPUT=$(sudo -u "$USER" s3fs "$BUCKET" "$MOUNT_POINT" \
        -o passwd_file="$PASSWD_FILE" \
        -o url="$URL" \
        -o use_path_request_style \
        -o allow_other \
        -o uid="$(id -u "$USER")" \
        -o gid="$(id -g "$USER")" 2>&1)
    
    if mount | grep -q "$MOUNT_POINT"; then
        print_success "Successfully mounted $BUCKET at $MOUNT_POINT"
        
        TEST_FILE="$MOUNT_POINT/.s3fs_test_$$"
        if sudo -u "$USER" touch "$TEST_FILE" 2>/dev/null; then
            sudo -u "$USER" rm "$TEST_FILE" 2>/dev/null
            print_success "Write access verified"
        else
            print_info "Note: Mount is read-only or write test failed"
        fi
        
        if [ "$AUTO_MOUNT" = "yes" ]; then
            if add_to_fstab_safe "$BUCKET" "$MOUNT_POINT" "$PASSWD_FILE" "$URL" "$(id -u "$USER")" "$(id -g "$USER")"; then
                print_success "Persistent mount configured"
            fi
        fi
        
        echo ""
        printf "%b═══════════════════════════════════════════════════════%b\n" "$GREEN" "$NC"
        print_success "Mount complete! Access your files at: $MOUNT_POINT"
        
        # Show all mount points for this bucket
        local all_mounts=$(get_bucket_mounts "$BUCKET")
        local mount_count=$(echo "$all_mounts" | grep -c .)
        if [ $mount_count -gt 1 ]; then
            printf "\n%bBucket '$BUCKET' is now mounted at %d locations:%b\n" "$CYAN" "$mount_count" "$NC"
            echo "$all_mounts" | while read -r mp; do
                [ -n "$mp" ] && echo "  • $mp"
            done
        fi
        printf "%b═══════════════════════════════════════════════════════%b\n" "$GREEN" "$NC"
    else
        print_error "Failed to mount $BUCKET"
        echo ""
        print_error "Mount failed with output:"
        echo "$MOUNT_OUTPUT"
        exit 1
    fi
}

# Enhanced unmount function supporting both bucket and path
unmount_bucket() {
    print_header "Unmount S3/MinIO Bucket"
    printf "%b═══════════════════════════════════════════════════════%b\n" "$PURPLE" "$NC"
    echo ""
    
    # If path is specified, unmount that specific path
    if [ -n "$MOUNT_POINT" ]; then
        # Unmount by specific path
        if ! mount | grep -q " $MOUNT_POINT "; then
            print_error "Path $MOUNT_POINT is not mounted"
            exit 1
        fi
        
        # Get bucket name for cleanup
        local mount_line=$(mount | grep " $MOUNT_POINT ")
        if echo "$mount_line" | grep -q "s3fs#"; then
            BUCKET=$(echo "$mount_line" | sed 's/.*s3fs#\([^ ]*\).*/\1/')
        else
            BUCKET=$(basename "$MOUNT_POINT")
        fi
        
        print_info "Unmounting $BUCKET from $MOUNT_POINT..."
        
        if umount "$MOUNT_POINT" 2>/dev/null; then
            print_success "Successfully unmounted $MOUNT_POINT"
        elif [ "$FORCE" = "yes" ]; then
            print_info "Forcing unmount..."
            if umount -f "$MOUNT_POINT" 2>/dev/null || umount -l "$MOUNT_POINT" 2>/dev/null; then
                print_success "Force unmounted $MOUNT_POINT"
            else
                print_error "Failed to unmount even with force"
                exit 1
            fi
        else
            print_error "Failed to unmount $MOUNT_POINT (may be busy)"
            print_info "Use -f or --force to force unmount"
            if command -v lsof &> /dev/null; then
                print_info "Processes using the mount:"
                lsof "$MOUNT_POINT" 2>/dev/null | head -10
            fi
            exit 1
        fi
        
        # Clean up fstab
        if grep -q " $MOUNT_POINT " /etc/fstab; then
            print_info "Removing from /etc/fstab..."
            cp /etc/fstab /etc/fstab.backup
            sed -i "\|${MOUNT_POINT}[[:space:]]|d" /etc/fstab
            print_success "Removed from /etc/fstab"
        fi
        
        # Clean up directory if empty
        if [ -d "$MOUNT_POINT" ] && [ -z "$(ls -A "$MOUNT_POINT" 2>/dev/null)" ]; then
            rmdir "$MOUNT_POINT" 2>/dev/null && print_success "Removed empty mount directory"
        fi
        
    elif [ -n "$BUCKET" ]; then
        # Unmount by bucket name - handle multiple mounts
        local mount_points=$(get_bucket_mounts "$BUCKET")
        
        if [ -z "$mount_points" ]; then
            print_error "Bucket $BUCKET is not mounted"
            exit 1
        fi
        
        local mount_count=$(echo "$mount_points" | grep -c .)
        
        if [ $mount_count -eq 1 ]; then
            # Only one mount point, unmount it
            MOUNT_POINT=$(echo "$mount_points" | head -1)
            $0 unmount -p "$MOUNT_POINT" $([ "$FORCE" = "yes" ] && echo "-f")
        elif [ "$ALL_INSTANCES" = "yes" ]; then
            # Unmount all instances
            print_info "Unmounting all $mount_count instances of bucket $BUCKET..."
            echo "$mount_points" | while read -r mp; do
                [ -z "$mp" ] && continue
                print_info "Unmounting $mp..."
                $0 unmount -p "$mp" $([ "$FORCE" = "yes" ] && echo "-f")
            done
            print_success "All instances of $BUCKET unmounted"
        else
            # Multiple mount points, ask which one
            if [ "$NON_INTERACTIVE" = "yes" ]; then
                print_error "Bucket $BUCKET is mounted at multiple locations"
                print_info "Specify --path to unmount a specific location or use --all"
                echo "$mount_points" | while read -r mp; do
                    [ -n "$mp" ] && echo "  • $mp"
                done
                exit 1
            else
                print_info "Bucket $BUCKET is mounted at multiple locations:"
                local MOUNTS
                mapfile -t MOUNTS < <(echo "$mount_points")
                
                PS3="Select mount to unmount (or 0 for all): "
                select MOUNT_POINT in "${MOUNTS[@]}" "All mounts"; do
                    if [ "$MOUNT_POINT" = "All mounts" ]; then
                        ALL_INSTANCES="yes"
                        $0 unmount -b "$BUCKET" --all $([ "$FORCE" = "yes" ] && echo "-f")
                        break
                    elif [ -n "$MOUNT_POINT" ]; then
                        $0 unmount -p "$MOUNT_POINT" $([ "$FORCE" = "yes" ] && echo "-f")
                        break
                    fi
                done
            fi
        fi
        
    else
        # No bucket or path specified - interactive selection
        if [ "$NON_INTERACTIVE" = "yes" ]; then
            print_error "Specify --bucket or --path for unmounting"
            exit 1
        fi
        
        mapfile -t MOUNTS < <(mount | grep -E "s3fs|fuse.s3fs" | awk '{print $3}')
        
        if [ ${#MOUNTS[@]} -eq 0 ]; then
            print_error "No s3fs mounts found"
            exit 1
        fi
        
        print_info "Select mount to unmount:"
        PS3="Enter number: "
        select MOUNT_POINT in "${MOUNTS[@]}"; do
            if [ -n "$MOUNT_POINT" ]; then
                $0 unmount -p "$MOUNT_POINT" $([ "$FORCE" = "yes" ] && echo "-f")
                break
            fi
        done
    fi
    
    # Clean up credentials if no more mounts for this bucket
    if [ -n "$BUCKET" ]; then
        local remaining_mounts=$(get_bucket_mounts "$BUCKET")
        if [ -z "$remaining_mounts" ]; then
            # No more mounts, clean up credentials
            for user_home in /home/* /root; do
                [ -d "$user_home" ] || continue
                PASSWD_FILE="$user_home/.passwd-s3fs-$BUCKET"
                if [ -f "$PASSWD_FILE" ]; then
                    rm -f "$PASSWD_FILE"
                    print_success "Cleaned up credentials for $BUCKET"
                    break
                fi
            done
        fi
    fi
    
    echo ""
    printf "%b═══════════════════════════════════════════════════════%b\n" "$GREEN" "$NC"  # FIXED: Removed extra )
    print_success "Unmount complete!"
    printf "%b═══════════════════════════════════════════════════════%b\n" "$GREEN" "$NC"
}

# Main execution
main() {
    parse_args "$@"
    
    case "$COMMAND" in
        mount)
            check_root
            mount_bucket
            ;;
        unmount|umount)
            check_root
            unmount_bucket
            ;;
        list|ls)
            list_mounts
            ;;
        help|--help|-h|"")
            show_usage
            ;;
        *)
            print_error "Unknown command: $COMMAND"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
