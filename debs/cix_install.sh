#!/bin/bash
set -e  # Exit immediately if any command fails
set -u  # Treat unset variables as an error
set -o pipefail  # Treat any failure in a pipeline as an error

# ====================== Version Alias Configuration (Core Modification) ======================
# Ubuntu version number → official alias mapping
declare -A UBUNTU_CODENAMES=(
    ["22.04"]="jammy"
    ["24.04"]="noble"
    ["25.04"]="plucky"
)
# Alias → version number reverse mapping (for log display)
declare -A UBUNTU_VERSIONS=(
    ["jammy"]="22.04"
    ["noble"]="24.04"
    ["plucky"]="25.04"
)

# ====================== Common Configuration ======================
# Base URL for all downloads
BASE_URL="."

# ====================== Utility Functions ======================
# Print colored logs
log_info() {
    echo -e "\033[32m[INFO] $1\033[0m" >&2
}
log_warn() {
    echo -e "\033[33m[WARN] $1\033[0m" >&2
}
log_error() {
    echo -e "\033[31m[ERROR] $1\033[0m" >&2
    exit 1
}

# Check for root privileges
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "Please run the script with root privileges (sudo ./script.sh)"
    fi
}

# Get Ubuntu version codename (core function)
get_ubuntu_codename() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        # Prefer official codename (UBUNTU_CODENAME)
        if [ -n "$UBUNTU_CODENAME" ]; then
            local codename="$UBUNTU_CODENAME"
            # Verify if codename is in supported list
            if [[ -z "${UBUNTU_VERSIONS[$codename]}" ]]; then
                log_error "Unsupported Ubuntu codename: $codename (only jammy/noble/oceanic are supported)"
            fi
            log_info "Detected Ubuntu version: ${UBUNTU_VERSIONS[$codename]} ($codename)"
            echo "$codename"
            return 0
        fi
        
        # Fallback: derive codename from version number
        local ver=$(echo "$VERSION_ID" | cut -d. -f1-2)
        if [[ -n "${UBUNTU_CODENAMES[$ver]}" ]]; then
            local codename="${UBUNTU_CODENAMES[$ver]}"
            log_info "Detected Ubuntu version: $ver (${codename})"
            echo "$codename"
            return 0
        else
            log_error "Unrecognized Ubuntu version: $ver (only 22.04/24.04/25.04 are supported)"
        fi
    else
        log_error "Could not detect system version, not an Ubuntu system"
    fi
}

# Install deb package (automatically handles dependencies)
install_deb() {
    local deb_file="$1"
    log_info "Installing deb package: $deb_file"
    if ! dpkg -i "$deb_file"; then
        log_warn "dpkg failed to install $deb_file, attempting to fix dependencies and retry"
        apt-get install -f -y
        dpkg -i "$deb_file" || log_error "Final failure to install $deb_file"
    fi
}

# ====================== Main Process ======================
main() {
    # Pre-checks
    check_root
    UBUNTU_CODENAME=$(get_ubuntu_codename)  # Core: use version codename

    # ====================== Step 1: Ubuntu 22.04 (jammy) Exclusive Operations ======================
    if [ "$UBUNTU_CODENAME" = "jammy" ]; then  # Use codename for judgment
        MAKEFILE_PATH="/usr/src/linux-headers-6.6.89-cix-build-generic/Makefile"
        if [ -f "$MAKEFILE_PATH" ]; then
            log_info "Ubuntu ${UBUNTU_VERSIONS[$UBUNTU_CODENAME]} ($UBUNTU_CODENAME): Removing specified line from Makefile"
            # Backup original file
            cp "$MAKEFILE_PATH" "${MAKEFILE_PATH}.bak"
            # Remove target line (supports space matching)
            sed -i '/KBUILD_CFLAGS[[:space:]]*+= -ftrivial-auto-var-init=zero/d' "$MAKEFILE_PATH"
            log_info "Removed line 'KBUILD_CFLAGS   += -ftrivial-auto-var-init=zero' from $MAKEFILE_PATH"
        else
            log_warn "Makefile $MAKEFILE_PATH does not exist, skipping removal operation"
        fi
    fi

    # ====================== Step 2: Download Common Files ======================
    log_info "===== Starting download of common files ====="
    # Define common download list
    COMMON_URLS=(
        "${BASE_URL}/cix-env_1.0.0_arm64.deb"
        "${BASE_URL}/cix-firmware_1.0.0_arm64.deb"
        "${BASE_URL}/cix-go-2025q3.tar.gz"
        "${BASE_URL}/cix-npu-driver_2.0.1_arm64.deb"
        "${BASE_URL}/cix-noe-umd_2.0.4_arm64.deb"
        "${BASE_URL}/cix-vpu-driver-dkms_1.0.0_arm64.deb"
        "${BASE_URL}/cix-vpu-test_1.0.0_arm64.deb"
    )

    # ====================== Step 3: Execute Common Commands ======================
    log_info "===== Executing common system configuration commands ====="
    # Replace sh with bash
    log_info "Replacing /bin/sh with bash"
    rm -rf /bin/sh
    ln -sf /bin/bash /bin/sh

    # Update sources and install dependency packages
    log_info "Updating apt sources and installing dependencies"
    apt update -y
    apt install -y libxcb-dri2-0 dkms python3-pip ffmpeg mpv gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-tools

    # Extract and install cix-go (core fix: cd to cix-go directory first then execute install.sh)
    log_info "Extracting and installing cix-go"
    CIX_GO_TAR=$(ls cix-go-*.tar.gz 2>/dev/null)
    if [ -z "$CIX_GO_TAR" ]; then
        log_error "cix-go archive not found"
    fi
    # Extract the archive
    tar -xvf "$CIX_GO_TAR"
    # Check if cix-go directory exists
    if [ ! -d "cix-go" ]; then
        log_error "cix-go directory not found after extracting $CIX_GO_TAR"
    fi
    # Enter cix-go directory and execute install.sh
    log_info "Entering cix-go directory to execute install.sh"
    cd cix-go || log_error "Failed to switch to cix-go directory"
    ./install.sh --dkms || log_error "cix-go's install.sh execution failed"
    # Return to working directory to continue subsequent operations
    cd ..

    # Install common deb packages
    log_info "Installing common deb packages"
    dpkg -i *.deb || {
        log_warn "deb package installation failed, automatically fixing dependencies"
        apt install -f -y
        dpkg -i *.deb || log_error "Final failure to install common deb packages"
    }

    # Install aipu dkms
    log_info "Installing aipu DKMS driver"
    dkms add -m aipu -v 5.11.0 || log_warn "dkms add aipu may already exist, continuing execution"
    dkms build -m aipu -v 5.11.0 || log_error "dkms build aipu failed"
    dkms install -m aipu -v 5.11.0 --force || log_error "dkms install aipu failed"

    # ====================== Step 4: Ubuntu 24.04 (noble) Exclusive Installation ======================
    if [ "$UBUNTU_CODENAME" = "noble" ]; then  # Use codename for judgment
        log_info "===== Ubuntu ${UBUNTU_VERSIONS[$UBUNTU_CODENAME]} ($UBUNTU_CODENAME) exclusive package installation ====="
        UBUNTU_2404_URLS=(
            "${BASE_URL}/ffmpeg/ffmpeg_6.1.1-3ubuntu5+cix_arm64.deb"
            "${BASE_URL}/ffmpeg/libavutil58_6.1.1-3ubuntu5+cix_arm64.deb"
            "${BASE_URL}/ffmpeg/libavcodec60_6.1.1-3ubuntu5+cix_arm64.deb"
            "${BASE_URL}/ffmpeg/libavformat60_6.1.1-3ubuntu5+cix_arm64.deb"
            "${BASE_URL}/gstreamer/cix-gstreamer_1.24.2_arm64.deb"
        )

        # Download and install 24.04 exclusive packages
        for url in "${UBUNTU_2404_URLS[@]}"; do
            install_deb "$url"
        done
    fi

    # ====================== Step 5: Ubuntu 25.04 (oceanic) Exclusive Installation ======================
    if [ "$UBUNTU_CODENAME" = "plucky" ]; then  # Use codename for judgment
        log_info "===== Ubuntu ${UBUNTU_VERSIONS[$UBUNTU_CODENAME]} ($UBUNTU_CODENAME) exclusive package installation ====="
        UBUNTU_2504_URLS=(
            "${BASE_URL}/ffmpeg/ffmpeg_7.1.1-1ubuntu1+cix_arm64.deb"
            "${BASE_URL}/ffmpeg/libavutil59_7.1.1-1ubuntu1+cix_arm64.deb"
            "${BASE_URL}/ffmpeg/libavcodec61_7.1.1-1ubuntu1+cix_arm64.deb"
            "${BASE_URL}/ffmpeg/libavformat61_7.1.1-1ubuntu1+cix_arm64.deb"
            "${BASE_URL}/ffmpeg/libavfilter10_7.1.1-1ubuntu1+cix_arm64.deb"
            "${BASE_URL}/ffmpeg/libavdevice61_7.1.1-1ubuntu1+cix_arm64.deb"
            "${BASE_URL}/ffmpeg/libswscale8_7.1.1-1ubuntu1+cix_arm64.deb"
            "${BASE_URL}/gstreamer/cix-gstreamer_1.26.2_arm64.deb"
        )

        # Download and install 25.04 exclusive packages
        for url in "${UBUNTU_2504_URLS[@]}"; do
            install_deb "$url"
        done
    fi

    # ====================== Step 6: Install Final Batch of Common deb Packages ======================
    log_info "===== Installing final batch of common deb packages ====="
    FINAL_DEB_URLS=(
        "${BASE_URL}/cix-alsa-conf_1.0.0_arm64.deb"
        "${BASE_URL}/cix-bt-driver_1.0.0_arm64.deb"
        "${BASE_URL}/cix-wlan_1.0.0_arm64.deb"
    )

    # Download and install final batch of deb packages
    for url in "${FINAL_DEB_URLS[@]}"; do
        install_deb "$url"
    done

    # Execute depmod
    log_info "Executing depmod -a to update module dependencies"
    depmod -a

    # ====================== Custom Operations (After All DEB Installations) ======================
    log_info "Performing custom operations after all deb packages installation"
    
    # Modify udev network rules
    log_info "Updating udev network rules"
    sudo sed -i 's/NAME=\"$env{ID_NET_NAME}\"/NAME=\"$env{ID_NET_SLOT}\"/' /usr/lib/udev/rules.d/80-net-setup-link.rules 
    sudo sed -i "/ACTION!=\"add|change|move\",/aENV{INTERFACE}==\"*p2p*\", ENV{NM_UNMANAGED}=\"1\"" /usr/lib/udev/rules.d/85-nm-unmanaged.rules 

    # Install older version of snapd
    log_info "Installing specified version of snapd"
    # Download specified version of Snapd 
    snap download snapd --revision=24724 
    # Install and lock the version 
    sudo snap ack snapd_24724.assert 
    sudo snap install snapd_24724.snap 
    sudo snap refresh --hold snapd

    # ====================== Reboot Confirmation ======================
    log_info "All installation steps completed. A system reboot is required for configurations to take effect"
    read -p "Would you like to reboot the system now? (y/N): " REBOOT_CONFIRM
    if [[ "$REBOOT_CONFIRM" =~ ^[Yy]$ ]]; then
        log_info "System will reboot in 10 seconds..."
        sleep 10
        reboot
    else
        log_info "Reboot cancelled. Please manually execute the reboot command for configurations to take effect"
    fi

    log_info "Script execution completed"
}

# Execute main process
main
