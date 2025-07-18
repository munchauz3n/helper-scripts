#!/bin/bash
#
# Configure and automate the process of installing Arch Linux.
#
# Copyright (C) 2020, 2023-2025  Petar G. Georgiev <petr.blake@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# Dependencies.
declare -a DEPENDNECIES=(
  "awk" "grep" "sed" "sfdisk" "sgdisk" "lscpu" "lspci" "lsblk" "bc" "openssl" "wipefs"
  "arch-chroot" "pacstrap" "genfstab" "whiptail" "mkfs.vfat" "mkfs.btrfs"
)

# Temp work directory.
declare TMPDIR="/mnt"

# Global variables.
declare -a TMPLIST=()

# List of additional bootloader kernel parameters.
declare -a KERNELPARAMS=(
  "acpi_osi=Linux" "Tell BIOS that it's running Linux" "off"
  "acpi_backlight=vendor" "First probe vendor specific display backlight drivers" "off"
)

# List of available user environments.
declare -a ENVIRONMENTS=(
  "Console" "Bare console environment" "on"
  "GNOME" "Modern and simple desktop - minimal installation" "off"
  "KDE" "Flashy desktop with many features - minimal installation" "off"
  "XFCE" "Reliable and fast desktop - minimal installation" "off"
)

# List of available display managers.
declare -a DISPLAYMANAGERS=(
  "GDM" "GNOME Display Manager" "off"
  "SDDM" "Simple Desktop Display Manager. QML-based and successor to KDM" "off"
  "LightDM(GTK)" "Light Display Manager with GTK greeter" "off"
  "LightDM(slick)" "Light Display Manager with slick greeter" "off"
  "LXDM" "Lightweight X11 Display Manager, does not support the XDMCP" "off"
)

# List of possible inteternet browsers.
declare -a BROWSERS=(
  "Vivaldi" "An advanced browser made with the power user in mind" "on"
  "Firefox" "Fast, Private & Safe Web Browser" "off"
)

# List of possible processor microcodes.
declare -a MICROCODES=(
  "AMD" "Install and enable AMD CPUs microcode updates in bootloader" "off"
  "Intel" "Install and enable Intel CPUs microcode updates in bootloader" "off"
)

# List of possible GPU drivers.
declare -a GPUDRIVERS=(
  "AMD" "Intall for AMD GPUs from GCN 3 and newer (Radeon Rx 300 or higher)" "off"
  "ATI" "Intall for AMD GPUs from GCN 2 and older" "off"
  "NVidia" "Intall for NVidia GPUs" "off"
  "Intel" "Intall for Intel integrated graphics" "off"
)

# List of possible hardware video acceleration drivers.
declare -a HWVIDEOACCELERATION=(
  "Mesa VA-API" "Video Acceleration API drivers for Nvidia and AMD GPUs" "off"
  "Mesa VDPAU" "Video Decode and Presentation API for Unix drivers for Nvidia and AMD GPUs" "off"
  "Intel VA-API(>= Broadwell)" "Video Acceleration API drivers for Intel GPUs (>= Broadwell)" "off"
  "Intel VA-API(<= Haswell)" "Video Acceleration API drivers for Intel GPUs (<= Haswell)" "off"
)

# List of possible additional packages.
declare -a EXTRAPKGS=(
  "Touchpad" "Touchpad support via the libinput driver" "off"
  "Touchscreen" "Touchscreen support via the libinput driver" "off"
  "Wacom" "Wacom stylus support" "off"
  "Bluetooth" "Bluetooth support" "off"
)

declare TITLE="Arch Linux Installer"
declare DESCRIPTION=""

declare -i HEIGHT=0
declare -i LISTHEIGHT=0
declare -a FLAGS=()

declare CMD=""
declare ITEM=""
declare DRIVE=""
declare CONFIGURATION=""

declare -a DELPARTITIONS=()
declare EFIPARTITION=""
declare SWAPPARTITION=""
declare SYSPARTITION=""

declare TOTALSIZE=""
declare FREESPACE=""
declare EFISIZE="512000"
declare SWAPSIZE=""
declare SYSTEMSIZE="0"

declare SWAPPASSWORD=""
declare SYSTEMPASSWORD=""
declare PASSWORD=""
declare ROOTPASSWORD="root"
declare CONFIRMPASSWORD=""

declare USERNAME=""
declare FULLNAME=""
declare USERGROUPS=""
declare HOSTNAME="arhlinux"
declare ENVIRONMENT=""
declare DISPLAYMANAGER=""

declare -a DEVICES=()
declare DEVICE=""
declare -a TIMEZONES=()
declare TIMEZONE=""
declare -a LOCALES=()
declare LANG=""
declare -a CLIKEYMAPS=()
declare CLIKEYMAP=""
declare -a CLIFONTS=()
declare CLIFONT=""


# =================================================================================================
# Functions
# =================================================================================================
function msg() {
  declare -A types=(
    ['error']='red'
    ['warning']='yellow'
    ['info']='green'
    ['log']='blue'
  )
  declare -A colors=(
    ['black']='\E[1;47m'
    ['red']='\E[1;31m'
    ['green']='\E[1;32m'
    ['yellow']='\E[1;33m'
    ['blue']='\E[1;34m'
    ['magenta']='\E[1;35m'
    ['cyan']='\E[1;36m'
    ['white']='\E[1;37m'
  )
  local bold="\E[1;1m"
  local default="\E[1;0m"

  # First argument is the type and 2nd is the actual message.
  local type=$1
  local message=$2

  local color=${colors[${types[${type}]}]}

  if [[ ${type} == "info" ]]; then
    printf "${color}==>${default}${bold} ${message}${default}\n" "$@" >&2
  elif [[ ${type} == "log" ]]; then
    printf "${color}  ->${default}${bold} ${message}${default}\n" "$@" >&2
  elif [[ ${type} == "warning" ]]; then
    printf "${color}==>WARNING:${default}${bold} ${message}${default}\n" "$@" >&2
  elif [[ ${type} == "error" ]]; then
    printf "${color}==>ERROR:${default}${bold} ${message}${default}\n" "$@" >&2
  fi
}

function cleanup() {
  msg info "Cleanup..."

  umount -R ${TMPDIR} 1> /dev/null 2>&1
  swapoff -L swap 1> /dev/null 2>&1

  msg log "Done"
}

function prepare() {
  local partitions
  local partition

  local mountpoint

  msg info "Getting ${DRIVE} ready..."
  partitions=($(lsblk ${DRIVE} -no KNAME | grep -E ${DEVICE}.*[0-9]+))

  for partition in ${partitions[@]}; do
    while [ $(mount | grep -c "/dev/${partition}") != 0 ]; do
      mountpoint=$(mount | grep "/dev/${partition}" | head -1 | awk '{ print $3 }')

      msg log "umount partition /dev/${partition} from ${mountpoint} ..."
      umount /dev/${partition} 1> /dev/null 2>&1

      # Check umount return value.
      [[ $? == +(1|255) ]] && { msg error "Failed to umount previous partition!"; exit 1; }
    done

    if [[ $(swapon --show --noheadings | grep -c "/dev/${partition}") != 0 ]]; then
      msg log "Deactivate swap partition /dev/${partition} ..."
      swapoff /dev/${partition} 1> /dev/null 2>&1

      # Check swapoff return value.
      [[ $? == +(1|255) ]] && { msg error "Failed to deactivate swap partition!"; exit 1; }
    fi
  done

  if [ ${#DELPARTITIONS[@]} == ${#partitions[@]} ]; then
    msg log "Removing any lingering information from previous partitions..."
    sgdisk --clear --zap-all ${DRIVE} 1> /dev/null 2>&1

    # Check sgdisk return value.
    [[ $? -ne 0 ]] && { msg error "Failed to clear GPT/MBR data!"; exit 1; }

    # Wipe filesystem information.
    wipefs -a ${DRIVE} 1> /dev/null 2>&1
  else
    for ITEM in ${DELPARTITIONS[@]//\"}; do
      msg log "Deleting partition /dev/${ITEM}..."
      sgdisk -d $(echo ${ITEM} | grep -Eo '[0-9]+$') ${DRIVE} 1> /dev/null 2>&1

      # Check sgdisk return value.
      [[ $? -ne 0 ]] && { msg error "Failed to delete /dev/${ITEM} partition!"; exit 1; }
    done

    # Sort partition table entries
    sgdisk -s ${DRIVE} 1> /dev/null 2>&1
  fi

  if [ -z ${EFIPARTITION} ]; then
    msg log "Creating EFI partition..."
    sgdisk --new=0:0:+${EFISIZE}KiB --typecode=0:ef00 --change-name=0:EFI \
           ${DRIVE} 1> /dev/null 2>&1

    # Check sgdisk return value.
    [[ $? -ne 0 ]] && { msg error "Failed to create EFI partition!"; exit 1; }

    EFIPARTITION=/dev/$(lsblk ${DRIVE} -no KNAME | grep -E ${DEVICE}.*[0-9]+ | tail -1)

    msg log "Formating EFI partition..."
    mkfs.vfat ${EFIPARTITION} -F 32 -n EFI 1> /dev/null 2>&1

    # Check mkfs return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to format EFI partition!"; exit 1; }
  fi

  local syslength="0"
  local swapname="swap"
  local sysname="system"

  [[ ${SYSTEMSIZE} != 0 ]] && syslength="+${SYSTEMSIZE}KiB"
  [[ ! -z ${SWAPPASSWORD} ]] && swapname="cryptswap"
  [[ ! -z ${SYSTEMPASSWORD} ]] && sysname="cryptsystem"

  msg log "Creating swap partition..."
  sgdisk --new=0:0:+${SWAPSIZE}KiB --typecode=0:8200 --change-name=0:${swapname} \
         ${DRIVE} 1> /dev/null 2>&1

  # Check sgdisk return value.
  [[ $? -ne 0 ]] && { msg error "Failed to create swap partition!"; exit 1; }

  SWAPPARTITION=/dev/$(lsblk ${DRIVE} -no KNAME | grep -E ${DEVICE}.*[0-9]+ | tail -1)

  msg log "Creating system partition..."
  sgdisk --new=0:0:${syslength} --typecode=0:8300 --change-name=0:${sysname} \
         ${DRIVE} 1> /dev/null 2>&1

  # Check sgdisk return value.
  [[ $? -ne 0 ]] && { msg error "Failed to create system partition!"; exit 1; }

  SYSPARTITION=/dev/$(lsblk ${DRIVE} -no KNAME | grep -E ${DEVICE}.*[0-9]+ | tail -1)

  partitions=($(lsblk ${DRIVE} -no KNAME | grep -E ${DEVICE}.*[0-9]+))

  if [ ! -z ${SWAPPASSWORD} ]; then
    msg log "Encrypting Swap partition..."
    echo -n "${SWAPPASSWORD}" | cryptsetup luksFormat --type luks1 --align-payload=8192 \
                                           ${SWAPPARTITION} - 1> /dev/null 2>&1
    echo -n "${SWAPPASSWORD}" | cryptsetup open ${SWAPPARTITION} swap - \
                                          1> /dev/null 2>&1

    msg log "Initializing encrypted Swap partition..."
    mkswap -L swap /dev/mapper/swap 1> /dev/null 2>&1
  else
    msg log "Initializing Swap partition..."
    mkswap -L swap ${SWAPPARTITION} 1> /dev/null 2>&1
  fi

  # Check mkswap return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to create swap volume!"; exit 1; }

  swapon -L swap 1> /dev/null 2>&1

  # Check swapon return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to enable swap volume!"; exit 1; }

  if [ ! -z ${SYSTEMPASSWORD} ]; then
    msg log "Encrypting System partition..."
    echo -n "${SYSTEMPASSWORD}" | cryptsetup luksFormat --type luks1 --iter-time 5000 \
                                            --align-payload=8192 ${SYSPARTITION} - \
                                            1> /dev/null 2>&1
    echo -n "${SYSTEMPASSWORD}" | cryptsetup open ${SYSPARTITION} system - 1> /dev/null 2>&1

    msg log "Creating and mounting encrypted System BTRFS Subvolumes..."
    mkfs.btrfs --force --label system /dev/mapper/system 1> /dev/null 2>&1

    # Check mkfs return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to create encypted system volume!"; exit 1; }
  else
    msg log "Creating and mounting System BTRFS Subvolumes..."
    mkfs.btrfs --force --label system ${SYSPARTITION} 1> /dev/null 2>&1

    # Check mkfs return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to create system volume!"; exit 1; }
  fi

  msg log "Mount system volume..."
  mount -t btrfs LABEL=system ${TMPDIR} 1> /dev/null 2>&1

  # Check mount return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to mount system volume!"; exit 1; }

  msg log "Create root subvolume..."
  btrfs subvolume create ${TMPDIR}/root 1> /dev/null 2>&1

  # Check btrfs return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to create root subvolume!"; exit 1; }

  msg log "Create home subvolume..."
  btrfs subvolume create ${TMPDIR}/home 1> /dev/null 2>&1

  # Check btrfs return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to create home subvolume!"; exit 1; }

  msg log "Create snapshots subvolume..."
  btrfs subvolume create ${TMPDIR}/snapshots 1> /dev/null 2>&1

  # Check btrfs return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to create snapshosts subvolume!"; exit 1; }

  msg log "Umount system volume..."
  umount -R ${TMPDIR}  1> /dev/null 2>&1

  # Check umount return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to umount system volume!"; exit 1; }

  local options="defaults,x-mount.mkdir,compress=zstd,noatime"

  msg log "Mount root subvolume..."
  mount -t btrfs -o subvol=root,${options} LABEL=system ${TMPDIR}  1> /dev/null 2>&1

  # Check mount return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to mount root subvolume!"; exit 1; }

  msg log "Mount home subvolume..."
  mount -t btrfs -o subvol=home,${options} LABEL=system ${TMPDIR}/home  1> /dev/null 2>&1

  # Check mount return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to mount home subvolume!"; exit 1; }

  msg log "Mount snapshots subvolume..."
  mount -t btrfs -o subvol=snapshots,${options} LABEL=system ${TMPDIR}/.snapshots  1> /dev/null 2>&1

  # Check mount return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to mount snapshots subvolume!"; exit 1; }

  msg log "Mounting EFI partition..."
  mkdir ${TMPDIR}/efi  1> /dev/null 2>&1
  mount ${EFIPARTITION} ${TMPDIR}/efi 1> /dev/null 2>&1

  # Check mount return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to mount EFI partition!"; exit 1; }

  msg log "Done"
}

function setup_console_environment() {
  msg log "Installing ACPI daemon..."
  pacstrap ${TMPDIR} acpid 1> /dev/null 2>&1

  # Check pacstrap return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to install ACPI daemon!"; exit 1; }

  msg log "Enabling ACPI daemon service..."
  arch-chroot ${TMPDIR} systemctl enable acpid.service 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to enable ACPI service!"; exit 1; }

  msg log "Enabling volume/mic controls in /etc/acpi/events/ ..."
  msg warning "Disable volume/mic controls in Xorg to prevent conflicts!"

  echo "event=button/volumeup" > ${TMPDIR}/etc/acpi/events/vol-up
  echo "action=amixer set Master 5+" >> ${TMPDIR}/etc/acpi/events/vol-up

  echo "event=button/volumedown" > ${TMPDIR}/etc/acpi/events/vol-down
  echo "action=amixer set Master 5-" >> ${TMPDIR}/etc/acpi/events/vol-down

  echo "event=button/mute" > ${TMPDIR}/etc/acpi/events/vol-mute
  echo "action=amixer set Master toggle" >> ${TMPDIR}/etc/acpi/events/vol-mute

  echo "event=button/f20" > ${TMPDIR}/etc/acpi/events/mic-mute
  echo "action=amixer set Capture toggle" >> ${TMPDIR}/etc/acpi/events/mic-mute

  msg log "Setting wired and wireless DHCP configurations..."
	cat <<-__EOF__ > ${TMPDIR}/etc/systemd/network/99-ethernet.network
		[Match]
		Name=en*
		Name=eth*

		[Network]
		DHCP=true
		IPv6PrivacyExtensions=true

		[DHCP]
		RouteMetric=512
	__EOF__

	cat <<-__EOF__ > ${TMPDIR}/etc/systemd/network/99-wireless.network
		[Match]
		Name=wlp*
		Name=wlan*

		[Network]
		DHCP=true
		IPv6PrivacyExtensions=true

		[DHCP]
		RouteMetric=1024
	__EOF__

  msg log "Enabling networkd service..."
  arch-chroot ${TMPDIR} systemctl enable systemd-networkd.service 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to enable network daemon service!"; exit 1; }

  msg log "Enabling resolved service..."
  arch-chroot ${TMPDIR} systemctl enable systemd-resolved.service 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to enable resolve daemon service!"; exit 1; }
}

function setup_common_environment() {
  if [[ ${GPUDRIVERS[@]} == *"AMD"* ]]; then
    msg log "Installing GPU drivers for AMD..."
    pacstrap ${TMPDIR} mesa vulkan-icd-loader vulkan-radeon 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to install drivers for AMD!"; exit 1; }
  fi

  if [[ ${GPUDRIVERS[@]} == *"ATI"* ]]; then
    msg log "Installing GPU drivers for ATI..."
    pacstrap ${TMPDIR} mesa-amber 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to install drivers for ATI!"; exit 1; }
  fi

  if [[ ${GPUDRIVERS[@]} == *"NVidia"* ]]; then
    msg log "Installing GPU drivers for NVidia..."
    pacstrap ${TMPDIR} mesa vulkan-icd-loader vulkan-nouveau 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to install drivers for NVidia!"; exit 1; }
  fi

  if [[ ${GPUDRIVERS[@]} == *"Intel"* ]]; then
    msg log "Installing GPU drivers for Intel..."
    pacstrap ${TMPDIR} mesa vulkan-icd-loader vulkan-intel 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to install drivers for Intel!"; exit 1; }
  fi

  if [[ ${HWVIDEOACCELERATION[@]} == *"Mesa VA-API"* ]]; then
    msg log "Installing Mesa VA-API drivers..."
    pacstrap ${TMPDIR} libva-mesa-driver libva-utils 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to install VA-API drivers!"; exit 1; }
  fi

  if [[ ${HWVIDEOACCELERATION[@]} == *"Mesa VDPAU"* ]]; then
    msg log "Installing Mesa VDPAU drivers..."
    pacstrap ${TMPDIR} mesa-vdpau vdpauinfo 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to install VDPAU drivers!"; exit 1; }
  fi

  if [[ ${HWVIDEOACCELERATION[@]} == *"Intel VA-API(>= Broadwell)"* ]]; then
    msg log "Installing Intel VA-API drivers for Broadwell and newer graphics..."
    pacstrap ${TMPDIR} intel-media-driver libva-utils 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to install VA-API drivers for Broadwell!"; exit 1; }
  fi

  if [[ ${HWVIDEOACCELERATION[@]} == *"Intel VA-API(<= Haswell)"* ]]; then
    msg log "Installing Intel VA-API drivers for Haswell and older graphics..."
    pacstrap ${TMPDIR} libva-intel-driver libva-utils 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to install VA-API drivers for Haswell!"; exit 1; }
  fi

  if [[ ${EXTRAPKGS[@]} == *"Touchscreen"* || ${EXTRAPKGS[@]} == *"Touchpad"* ]]; then
    msg log "Installing touchscreen/touchpad packages..."
    pacstrap ${TMPDIR} xf86-input-libinput 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to install touchscreen/touchpad packages!"; exit 1; }
  fi

  if [[ ${EXTRAPKGS[@]} == *"Wacom"* ]]; then
    msg log "Installing Wacom packages..."
    pacstrap ${TMPDIR} xf86-input-wacom 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to install Wacom packages!"; exit 1; }
  fi

  if [[ ${EXTRAPKGS[@]} == *"Bluetooth"* ]]; then
    msg log "Installing Bluetooth packages..."
    pacstrap ${TMPDIR} bluez bluez-utils 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to install Bluetooth packages!"; exit 1; }

    msg log "Enabling the Bluetooth service..."
    arch-chroot ${TMPDIR} systemctl enable bluetooth.service 1> /dev/null 2>&1

    # Check arch-chroot return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to enable Bluetooth service!"; exit 1; }
  fi

  if [[ ${DISPLAYMANAGER} == "GDM" ]]; then
    msg log "Installing GDM package..."
    pacstrap ${TMPDIR} gdm 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to install GDM package!"; exit 1; }

    msg log "Enabling the GDM service..."
    arch-chroot ${TMPDIR} systemctl enable gdm.service 1> /dev/null 2>&1

    # Check arch-chroot return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to enable GDM service!"; exit 1; }
  elif [[ ${DISPLAYMANAGER} == "SDDM" ]]; then
    msg log "Installing SDDM package..."
    pacstrap ${TMPDIR} sddm 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to install SDDM package!"; exit 1; }

    msg log "Enabling the SDDM service..."
    arch-chroot ${TMPDIR} systemctl enable sddm.service 1> /dev/null 2>&1

    # Check arch-chroot return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to enable SDDM service!"; exit 1; }
  elif [[ ${DISPLAYMANAGER} == "LightDM(GTK)" || ${DISPLAYMANAGER} == "LightDM(slick)" ]]; then
    msg log "Installing LightDM and greeter packages..."

    if [[ ${DISPLAYMANAGER} == "LightDM(GTK)" ]]; then
      pacstrap ${TMPDIR} lightdm lightdm-gtk-greeter lightdm-gtk-greeter-settings 1> /dev/null 2>&1

      # Check pacstrap return value.
      [[ $? == +(1|255) ]] && { msg error "Failed to install LightDM packages!"; exit 1; }

      # Setup the greeter to use.
      sed -i 's/#greeter-session=example-gtk-gnome/greeter-session=lightdm-gtk-greeter/' \
          ${TMPDIR}/etc/lightdm/lightdm.conf 1> /dev/null 2>&1;

      # Configure a themes and background.
      echo "[greeter]" > ${TMPDIR}/etc/lightdm/lightdm-gtk-greeter.conf
      echo "theme-name = Adwaita-dark" >> ${TMPDIR}/etc/lightdm/lightdm-gtk-greeter.conf
      echo "icon-theme-name = Adwaita" >> ${TMPDIR}/etc/lightdm/lightdm-gtk-greeter.conf

      if [[ ${ENVIRONMENT} == "GNOME" ]]; then
        echo "background = /usr/share/backgrounds/gnome/adwaita-d.webp" >> \
            ${TMPDIR}/etc/lightdm/lightdm-gtk-greeter.conf
      elif [[ ${ENVIRONMENT} == "XFCE" ]]; then
        echo "background = /usr/share/backgrounds/xfce/xfce-shapes.svg" >> \
            ${TMPDIR}/etc/lightdm/lightdm-gtk-greeter.conf
      fi
    elif [[ ${DISPLAYMANAGER} == "LightDM(slick)" ]]; then
      pacstrap ${TMPDIR} lightdm lightdm-slick-greeter 1> /dev/null 2>&1\

      # Check pacstrap return value.
      [[ $? == +(1|255) ]] && { msg error "Failed to install LightDM packages!"; exit 1; }

      # Setup the greeter to use.
      sed -i 's/#greeter-session=example-gtk-gnome/greeter-session=lightdm-slick-greeter/' \
          ${TMPDIR}/etc/lightdm/lightdm.conf 1> /dev/null 2>&1;

      # Configure background.
      echo "[Greeter]" > ${TMPDIR}/etc/lightdm/slick-greeter.conf

      if [[ ${ENVIRONMENT} == "GNOME" ]]; then
        echo "background = /usr/share/backgrounds/gnome/adwaita-d.webp" >> \
            ${TMPDIR}/etc/lightdm/slick-greeter.conf
      elif [[ ${ENVIRONMENT} == "XFCE" ]]; then
        echo "background = /usr/share/backgrounds/xfce/xfce-shapes.svg" >> \
            ${TMPDIR}/etc/lightdm/slick-greeter.conf
      fi
    fi

    msg log "Enabling the LightDM service..."
    arch-chroot ${TMPDIR} systemctl enable lightdm.service 1> /dev/null 2>&1

    # Check arch-chroot return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to enable LightDM service!"; exit 1; }
  elif [[ ${DISPLAYMANAGER} == "LXDM" ]]; then
    msg log "Installing LXDM package..."
    pacstrap ${TMPDIR} lxdm-gtk3 librsvg 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to install LXDM package!"; exit 1; }

    # Setup default session.
    sed -i 's/# session=\/usr\/bin\/startlxde/session=\/usr\/bin\/startlxde/' \
        ${TMPDIR}/etc/lxdm/lxdm.conf 1> /dev/null 2>&1;

    if [[ ${ENVIRONMENT} == "GNOME" ]]; then
      sed -i 's/startlxde/gnome-session/' ${TMPDIR}/etc/lxdm/lxdm.conf 1> /dev/null 2>&1;
    elif [[ ${ENVIRONMENT} == "KDE" ]]; then
      sed -i 's/startlxde/startplasma-x11/' ${TMPDIR}/etc/lxdm/lxdm.conf 1> /dev/null 2>&1;
    elif [[ ${ENVIRONMENT} == "XFCE" ]]; then
      sed -i 's/startlxde/startxfce4/' ${TMPDIR}/etc/lxdm/lxdm.conf 1> /dev/null 2>&1;
    fi

    # Disable user list.
    sed -i 's/^disable=0/disable=1/' ${TMPDIR}/etc/lxdm/lxdm.conf 1> /dev/null 2>&1;
    # Change the theme.
    sed -i 's/^gtk_theme=Adwaita/gtk_theme=Adwaita-dark/' ${TMPDIR}/etc/lxdm/lxdm.conf 1> /dev/null 2>&1;
    # Place .Xauthority in /tmp.
    sed -i 's/^# xauth_path=\/tmp/xauth_path=\/tmp/' ${TMPDIR}/etc/lxdm/lxdm.conf 1> /dev/null 2>&1;
    # Disable language select control.
    sed -i 's/^lang=1/lang=0/' ${TMPDIR}/etc/lxdm/lxdm.conf 1> /dev/null 2>&1;

    msg log "Enabling the LXDM service..."
    arch-chroot ${TMPDIR} systemctl enable lxdm.service 1> /dev/null 2>&1

    # Check arch-chroot return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to enable LXDM service!"; exit 1; }
  fi

  if [[ ${BROWSERS[@]} == *"Vivaldi"* ]]; then
    msg log "Installing Vivaldi browser..."
    pacstrap ${TMPDIR} vivaldi vivaldi-ffmpeg-codecs 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to install Vivaldi browser!"; exit 1; }
  fi

  if [[ ${BROWSERS[@]} == *"Firefox"* ]]; then
    msg log "Installing Firefox browser..."
    pacstrap ${TMPDIR} firefox firefox-ublock-origin firefox-dark-reader 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to install Firefox browser!"; exit 1; }
  fi
}

function setup_gnome_environment() {
  msg log "Installing GNOME packages..."
  pacstrap ${TMPDIR} baobab eog evince file-roller gedit gnome-control-center gnome-backgrounds \
           gnome-calculator gnome-calendar gnome-clocks gnome-logs gnome-menus gnome-screenshot \
           gnome-remote-desktop gnome-screenshot gnome-session gnome-settings-daemon gnome-shell \
           gnome-shell-extensions gnome-system-monitor gnome-terminal gnome-tweaks gnome-weather \
           gnome-themes-extra gnome-user-docs gnome-user-share gnome-video-effects gnome-software \
           gnome-icon-theme-extras gnome-firmware gnome-keyring networkmanager mutter nautilus guake \
           power-profiles-daemon sushi gvfs yelp system-config-printer pulseaudio pavucontrol \
           wayland-protocols dav1d x265 vlc 1> /dev/null 2>&1

  # Check pacstrap return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to install GNOME packages!"; exit 1; }

  if [[ ${EXTRAPKGS[@]} == *"Bluetooth"* ]]; then
    msg log "Installing GNOME Bluetooth packages..."
    pacstrap ${TMPDIR} gnome-bluetooth-3.0 pulseaudio-bluetooth 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to install GNOME bluetooth packages!"; exit 1; }
  fi

  msg log "Configuring NetworkManager to use iwd as the Wi-Fi backend..."
  echo "[device]" > ${TMPDIR}/etc/NetworkManager/conf.d/wifi-backend.conf
  echo "wifi.backend=iwd" >> ${TMPDIR}/etc/NetworkManager/conf.d/wifi-backend.conf

  msg log "Disabling the wpa_supplicant service..."
  arch-chroot ${TMPDIR} systemctl disable wpa_supplicant.service 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to disable wpa_suplicant service!"; exit 1; }

  msg log "Enabling the NetworkManager service..."
  arch-chroot ${TMPDIR} systemctl enable NetworkManager.service 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to enable NetworkManager service!"; exit 1; }
}

function setup_kde_environment() {
  msg log "Installing KDE packages..."
  pacstrap ${TMPDIR} plasma-workspace plasma-desktop plasma-nm plasma-pa plasma-systemmonitor \
           plasma-wayland-protocols plasma-disks plasma-workspace-wallpapers plasma-thunderbolt \
           plasma-browser-integration plasma-firewall kdeplasma-addons kinfocenter kscreen kgamma \
           kjournald kdialog kcron konsole kweather ksystemlog krdp kjournald kdeconnect kwrited \
           kcrash kwallet kwalletmanager drkonqi kde-gtk-config dolphin breeze breeze-gtk oxygen \
           oxygen-sounds sweeper networkmanager discover wayland-protocols power-profiles-daemon \
           powerdevil spectacle vlc phonon-qt6-vlc phonon-qt6 dav1d x265 gwenview kate yakuake \
           pulseaudio pavucontrol partitionmanager print-manager system-config-printer kcalc ark \
           1> /dev/null 2>&1

  # Check pacstrap return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to install KDE packages!"; exit 1; }

  if [[ ${EXTRAPKGS[@]} == *"Bluetooth"* ]]; then
    msg log "Installing KDE Bluetooth packages..."
    pacstrap ${TMPDIR} bluedevil pulseaudio-bluetooth 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to install KDE bluetooth packages!"; exit 1; }
  fi

  if [[ ${DISPLAYMANAGER} == "SDDM" ]]; then
    msg log "Installing SDDM KConfig Module..."
    pacstrap ${TMPDIR} sddm-kcm 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to install SDDM KConfig Module!"; exit 1; }
  fi

  msg log "Configuring NetworkManager to use iwd as the Wi-Fi backend..."
  echo "[device]" > ${TMPDIR}/etc/NetworkManager/conf.d/wifi-backend.conf
  echo "wifi.backend=iwd" >> ${TMPDIR}/etc/NetworkManager/conf.d/wifi-backend.conf

  msg log "Disabling the wpa_supplicant service..."
  arch-chroot ${TMPDIR} systemctl disable wpa_supplicant.service 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to disable wpa_suplicant service!"; exit 1; }

  msg log "Enabling the NetworkManager service..."
  arch-chroot ${TMPDIR} systemctl enable NetworkManager.service 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to enable NetworkManager service!"; exit 1; }
}

function setup_xfce_environment() {
  msg log "Installing XFCE packages..."
  pacstrap ${TMPDIR} exo garcon mousepad thunar thunar-volman tumbler xfwm4 xfwm4-themes ristretto \
           xfce4-appfinder xfce4-panel xfce4-power-manager xfce4-session xfce4-pulseaudio-plugin \
           xfce4-taskmanager xfce4-screenshooter xfce4-notifyd xfce4-xkb-plugin xfce4-mount-plugin \
           xfce4-whiskermenu-plugin xfce4-battery-plugin xfce4-sensors-plugin xfce4-settings \
           xfce4-terminal xfce4-screensaver pulseaudio pavucontrol xfdesktop xfconf networkmanager \
           xarchiver thunar-archive-plugin network-manager-applet system-config-printer dav1d \
           x265 vlc 1> /dev/null 2>&1

  # Check pacstrap return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to install XFCE packages!"; exit 1; }

  if [[ ${EXTRAPKGS[@]} == *"Bluetooth"* ]]; then
    msg log "Installing XFCE Bluetooth packages..."
    pacstrap ${TMPDIR} blueman pulseaudio-bluetooth 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to install XFCE bluetooth packages!"; exit 1; }
  fi

  msg log "Configuring NetworkManager to use iwd as the Wi-Fi backend..."
  echo "[device]" > ${TMPDIR}/etc/NetworkManager/conf.d/wifi-backend.conf
  echo "wifi.backend=iwd" >> ${TMPDIR}/etc/NetworkManager/conf.d/wifi-backend.conf

  msg log "Disabling the wpa_supplicant service..."
  arch-chroot ${TMPDIR} systemctl disable wpa_supplicant.service 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to disable wpa_suplicant service!"; exit 1; }

  msg log "Enabling the NetworkManager service..."
  arch-chroot ${TMPDIR} systemctl enable NetworkManager.service 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to enable NetworkManager service!"; exit 1; }
}

function install() {
  msg info "Creating installation..."

  msg log "Installing base packages..."
  pacstrap ${TMPDIR} base base-devel linux linux-firmware util-linux usbutils man-db man-pages \
           bash-completion openssh sudo gptfdisk tree wget vim iwd cryptsetup grub efibootmgr lshw \
           btrfs-progs lm_sensors ntp dbus alsa-utils cronie terminus-font ttf-dejavu texinfo git \
           ttf-liberation acpi grub-btrfs inotify-tools timeshift ntfs-3g btop rocm-smi-lib nvtop \
           fwupd bc dosfstools mtools usbutils os-prober libxkbcommon xdg-user-dirs 1> /dev/null 2>&1

  # Check pacstrap return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to install base packages!"; exit 1; }

  # Enabling microcode updates, grub-mkconfig will automatically detect
  # microcode updates and configure appropriately.
  if [[ ${MICROCODES[@]} == *"AMD"* ]]; then
    msg log "Installing AMD microcode package..."
    pacstrap ${TMPDIR} amd-ucode 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to install AMD microcode!"; exit 1; }
  fi

  if [[ ${MICROCODES[@]} == *"Intel"* ]]; then
    msg log "Installing AMD microcode package..."
    pacstrap ${TMPDIR} intel-ucode 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to install Intel microcode!"; exit 1; }
  fi

  msg log "Generate fstab..."
  genfstab -L -p ${TMPDIR} >> ${TMPDIR}/etc/fstab

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to generate fstab!"; exit 1; }

  msg log "Setting password for root..."
  awk -i inplace -F: "BEGIN {OFS=FS;} \
      \$1 == \"root\" {\$2=\"$(openssl passwd -6 ${ROOTPASSWORD})\"} 1" \
      ${TMPDIR}/etc/shadow 1> /dev/null 2>&1

  # Check awk return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to configure the root password!"; exit 1; }

  msg log "Set timezone, locales, keyboard, fonts and hostname..."
  arch-chroot ${TMPDIR} ln -sf /usr/share/zoneinfo/"${TIMEZONE}" \
                               /etc/localtime 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to set time zone!"; exit 1; }

  msg log "Set hardware clock..."
  arch-chroot ${TMPDIR} hwclock --systohc 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to set HW clock!"; exit 1; }

  local locale

  msg log "Setting locales..."
  for locale in "${LOCALES[@]//\"}"; do
    sed -i s/^#${locale}/${locale}/g ${TMPDIR}/etc/locale.gen 1> /dev/null 2>&1

    # Check sed return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to set '${locale}'!"; exit 1; }
  done

  echo "LANG=${LANG}" > ${TMPDIR}/etc/locale.conf
  arch-chroot ${TMPDIR} locale-gen 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to generate locales!"; exit 1; }

  echo "KEYMAP=${CLIKEYMAP}" > ${TMPDIR}/etc/vconsole.conf
  echo "FONT=${CLIFONT}" >> ${TMPDIR}/etc/vconsole.conf

  echo ${HOSTNAME} > ${TMPDIR}/etc/hostname
  echo "127.0.0.1       localhost" >> ${TMPDIR}/etc/hosts
  echo "::1             localhost ipv6-localhost ipv6-loopback" >> ${TMPDIR}/etc/hosts
  echo "127.0.1.1       ${HOSTNAME}.localdomain ${HOSTNAME}" >> ${TMPDIR}/etc/hosts

  # Enable users of group 'wheel' to execute any command.
  sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' \
      ${TMPDIR}/etc/sudoers 1> /dev/null 2>&1

  # Check sed return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to add group 'wheel' to sudoers!"; exit 1; }

  if [ ! -z ${USERNAME} ]; then
    msg log "Setting user ${USERNAME}..."
    arch-chroot ${TMPDIR} useradd -m -G wheel,storage,optical,scanner \
                                  -s /bin/bash ${USERNAME} 1> /dev/null 2>&1

    # Check arch-chroot return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to add user!"; exit 1; }

    msg log "Setting password for user ${USERNAME} ..."
    awk -i inplace -F: "BEGIN {OFS=FS;} \
        \$1 == \"${USERNAME}\" {\$2=\"$(openssl passwd -6 ${PASSWORD})\"} 1" \
        ${TMPDIR}/etc/shadow 1> /dev/null 2>&1

    # Check awk return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to configure the user password!"; exit 1; }

    msg log "Adding groups '${USERGROUPS}' to user '${USERNAME}'..."
    arch-chroot ${TMPDIR} usermod -aG ${USERGROUPS} ${USERNAME} 1> /dev/null 2>&1

    # Check arch-chroot return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to modify user groups!"; exit 1; }

    msg log "Set fullname for '${USERNAME}'..."
    arch-chroot ${TMPDIR} chfn -f "${FULLNAME}" ${USERNAME} 1> /dev/null 2>&1

    # Check arch-chroot return value.
    [[ $? == +(1|255) ]] && { msg error "Failed to set full name!"; exit 1; }
  fi

  msg log "Configuring initramfs..."

  # The btrfs-check tool cannot be used on a mounted file system. To be able
  # to use btrfs-check without booting from a live USB, add it BINARIES.
  #
  # https://wiki.archlinux.org/index.php/Btrfs#Corruption_recovery
  sed -i 's/^BINARIES=\(.*\)/BINARIES=\(\/usr\/bin\/btrfs\)/g' \
      ${TMPDIR}/etc/mkinitcpio.conf 1> /dev/null 2>&1

  local hooks="base systemd autodetect keyboard sd-vconsole modconf block"
  hooks+=" sd-encrypt btrfs filesystems fsck"

  sed -i "s/^HOOKS=\(.*\)/HOOKS=\(${hooks}\)/g" \
      ${TMPDIR}/etc/mkinitcpio.conf 1> /dev/null 2>&1

  local module=""

  # For early loading of the KMS (Kernel Mode Setting) driver for video.
  if [[ ${GPUDRIVERS[@]} == *"AMD"* ]]; then
    [[ -z ${module} ]] && module+="amdgpu" || module+=" amdgpu"
  fi

  if [[ ${GPUDRIVERS[@]} == *"ATI"* ]]; then
    [[ -z ${module} ]] && module+="radeon" || module+=" radeon"
  fi

  if [[ ${GPUDRIVERS[@]} == *"NVidia"* ]]; then
    [[ -z ${module} ]] && module+="nouveau" || module+=" nouveau"
  fi

  if [[ ${GPUDRIVERS[@]} == *"Intel"* ]]; then
    [[ -z ${module} ]] && module+="i915" || module+=" i915"
  fi

  sed -i "s/^MODULES=\(.*\)/MODULES=\(${module}\)/g" \
      ${TMPDIR}/etc/mkinitcpio.conf 1> /dev/null 2>&1

  msg log "Configuring GRUB..."

  local cmdline="${KERNELPARAMS[@]//\"}"
  sed -i "/^GRUB_CMDLINE_LINUX=/ s/\(.*\)\"/\1${cmdline}\"/" \
      ${TMPDIR}/etc/default/grub 1> /dev/null 2>&1

  if [ ! -z ${SYSTEMPASSWORD} ]; then
    # Set the kernel parameters, so initramfs can unlock the encrypted partitions.
    [[ ! -z ${cmdline} ]] && cmdline=" rd.luks.name=$(lsblk -dno UUID ${SYSPARTITION})=system"
    [[ -z ${cmdline} ]] && cmdline="rd.luks.name=$(lsblk -dno UUID ${SYSPARTITION})=system"

    cmdline+=" root=/dev/mapper/system"

    sed -i "/^GRUB_CMDLINE_LINUX=/ s/\(.*\)\"/\1${cmdline//\//\\/}\"/" \
        ${TMPDIR}/etc/default/grub 1> /dev/null 2>&1
  fi

  if [ ! -z ${SWAPPASSWORD} ]; then
    [[ ! -z ${cmdline} ]] && cmdline=" rd.luks.name=$(lsblk -dno UUID ${SWAPPARTITION})=swap"
    [[ -z ${cmdline} ]] && cmdline="rd.luks.name=$(lsblk -dno UUID ${SWAPPARTITION})=swap"

    cmdline+=" resume=/dev/mapper/swap"

    sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/\(.*\)\"/\1${cmdline//\//\\/}\"/" \
        ${TMPDIR}/etc/default/grub 1> /dev/null 2>&1
  fi

  if [ ! -z ${SWAPPASSWORD} ] || [ ! -z ${SYSTEMPASSWORD} ]; then
    # Configure GRUB to allow booting from /boot on a LUKS1 encrypted partition.
    sed -i "s/^#GRUB_ENABLE_CRYPTODISK=y/GRUB_ENABLE_CRYPTODISK=y/g" \
        ${TMPDIR}/etc/default/grub 1> /dev/null 2>&1

    msg log "Creating crypt keys..."

    local cryptdir="/etc/cryptsetup-keys.d"
    mkdir ${TMPDIR}${cryptdir} && chmod 700 ${TMPDIR}${cryptdir} 1> /dev/null 2>&1

    local files=""

    if [ ! -z ${SWAPPASSWORD} ]; then
      dd bs=512 count=4 if=/dev/urandom of=${TMPDIR}${cryptdir}/cryptswap.key 1> /dev/null 2>&1
      chmod 600 ${TMPDIR}${cryptdir}/cryptswap.key 1> /dev/null 2>&1

      echo -n "${SWAPPASSWORD}" | cryptsetup -v luksAddKey -i 1 ${SWAPPARTITION} \
          ${TMPDIR}${cryptdir}/cryptswap.key - 1> /dev/null 2>&1

      # Add the keys to the grub configuration
      cmdline=" rd.luks.key=$(lsblk -dno UUID ${SWAPPARTITION})=${cryptdir}/cryptswap.key"
      sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/\(.*\)\"/\1 ${cmdline//\//\\/}\"/" \
          ${TMPDIR}/etc/default/grub 1> /dev/null 2>&1

      files+="${cryptdir}/cryptswap.key"
    fi

    if [ ! -z ${SYSTEMPASSWORD} ]; then
      dd bs=512 count=4 if=/dev/urandom of=${TMPDIR}${cryptdir}/cryptsystem.key 1> /dev/null 2>&1
      chmod 600 ${TMPDIR}${cryptdir}/cryptsystem.key 1> /dev/null 2>&1

      echo -n "${SYSTEMPASSWORD}" | cryptsetup -v luksAddKey -i 1 ${SYSPARTITION} \
          ${TMPDIR}${cryptdir}/cryptsystem.key - 1> /dev/null 2>&1

      cmdline="rd.luks.key=$(lsblk -dno UUID ${SYSPARTITION})=${cryptdir}/cryptsystem.key"
      sed -i "/^GRUB_CMDLINE_LINUX=/ s/\(.*\)\"/\1 ${cmdline//\//\\/}\"/" \
          ${TMPDIR}/etc/default/grub 1> /dev/null 2>&1

      [[ ! -z ${cmdline} ]] && files+=" ${cryptdir}/cryptsystem.key"
      [[ -z ${cmdline} ]] && files+="${cryptdir}/cryptsystem.key"
    fi

    # Add the keys to the initramfs.
    sed -i "s/^FILES=\(.*\)/FILES=\(${files//\//\\/}\)/g" \
        ${TMPDIR}/etc/mkinitcpio.conf 1> /dev/null 2>&1
  fi

  # Configure GRUB to allow automatic probing for other OS.
  sed -i "s/^\(#G\|G\)RUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/g" \
      ${TMPDIR}/etc/default/grub 1> /dev/null 2>&1

  # Restruct /boot permissions.
  chmod 700 ${TMPDIR}/boot

  msg log "Recreate initramfs..."
  arch-chroot ${TMPDIR} mkinitcpio -P 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to recreate initramfs!"; exit 1; }

  msg log "Installing GRUB in /efi..."
  arch-chroot ${TMPDIR} grub-install --target=x86_64-efi --efi-directory=/efi \
                                     --bootloader-id=GRUB --recheck 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to install GRUB!"; exit 1; }

  msg log "Creating GRUB configuration file..."
  arch-chroot ${TMPDIR} grub-mkconfig -o /boot/grub/grub.cfg

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to create GRUB configuration!"; exit 1; }

  msg log "Enabling NTP(Network Time Protocol) daemon service..."
  arch-chroot ${TMPDIR} systemctl enable ntpd 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to enable NTP daemon service!"; exit 1; }

  msg log "Enabling the iwd service..."
  arch-chroot ${TMPDIR} systemctl enable iwd.service 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to enable iw daemon service!"; exit 1; }

  msg log "Setup ${ENVIRONMENT} environment..."
  [[ ${ENVIRONMENT} == "Console" ]] && { setup_console_environment; }
  [[ ${ENVIRONMENT} == "GNOME" ]] && { setup_common_environment; setup_gnome_environment; }
  [[ ${ENVIRONMENT} == "KDE" ]] && { setup_common_environment; setup_kde_environment; }
  [[ ${ENVIRONMENT} == "XFCE" ]] && { setup_common_environment; setup_xfce_environment; }

  msg log "Install complete"
}


# =================================================================================================
# MAIN
# =================================================================================================
if [ "${EUID}" -ne 0 ]; then
  msg error "Script requires root privalages!"
  exit 1
fi

# Check for internet access.
ping -c 1 -q google.com >&/dev/null
[[ $? != 0 ]] && { msg error "Internet access is required for installation!"; exit 1; }

# Checks for dependencies
for CMD in "${DEPENDNECIES[@]}"; do
  if ! [[ -f "/bin/${CMD}" || -f "/sbin/${CMD}" || \
          -f "/usr/bin/${CMD}" || -f "/usr/sbin/${CMD}" ]] ; then
    msg error "'${CMD}' command is missing! Please install the relevant package."
    exit 1
  fi
done

# -------------------------------------------------------------------------------------------------
# Retrieve a list with curently available devices
TMPLIST=($(lsblk -dn -o NAME))

for ITEM in ${TMPLIST[@]}; do
  diskmodel=$(sfdisk -l /dev/${ITEM} | grep -E "Disk model" | cut -d' ' -f 3- | sed 's/\s*$//g')
  DEVICES+=("${ITEM} (${diskmodel})" " $(lsblk -dn -o SIZE /dev/${ITEM} | sed 's/^[[:space:]]*//g')")
done

DESCRIPTION="Choose drive - Be sure the correct device is selected!"
FLAGS=(--clear --title "${TITLE}" --menu "${DESCRIPTION}" 20 60 10)

DEVICE=$(whiptail "${FLAGS[@]}" "${DEVICES[@]}" 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

DEVICES=()

# Check if a device has been chosen.
[ -z "${DEVICE}" ] && { msg error "Empty value!"; exit 1; }

DEVICE=$(echo ${DEVICE} | awk '{ print $1 }')
DRIVE="/dev/${DEVICE}"
CONFIGURATION+="  Drive = ${DRIVE}\n"

# -------------------------------------------------------------------------------------------------
# Find out the total disk size (KiB).
TOTALSIZE=$(sfdisk -s ${DRIVE})

# Find out the total free space (KiB).
FREESPACE=$(sfdisk -F ${DRIVE} | awk '/Unpartitioned space/ { print $6 }')

# The above may fail if there is no partition table at all, use total size
[ -z ${FREESPACE} ] && FREESPACE=${TOTALSIZE} || FREESPACE=$(bc <<< "${FREESPACE} / 1024")

# Retrieve a list with curently available device partitions
TMPLIST=($(lsblk ${DRIVE} -no KNAME | grep -E ${DEVICE}.*[0-9]+))

for ITEM in ${TMPLIST[@]}; do
  description=$(printf "%-10s" "$(lsblk -no FSTYPE /dev/${ITEM})")
  description+=$(printf " %-30s" "$(lsblk -no PARTTYPENAME /dev/${ITEM})")
  description+=$(printf " %10s" "$(lsblk -no SIZE /dev/${ITEM})")

  DEVICES+=("${ITEM}" "${description}" "off")
done

if [[ ${#DEVICES[@]} != 0 ]]; then
  # Calculate the height based on the number of entries and increase by 10 for window compensation.
  HEIGHT=$((${#DEVICES[@]} / 3 + 10))
  LISTHEIGHT=$((${#DEVICES[@]} / 3))

  DESCRIPTION="Choose whether to delete existing partitions"
  FLAGS=(--clear --title "${TITLE}" --checklist "${DESCRIPTION}" ${HEIGHT} 80 ${LISTHEIGHT})

  DELPARTITIONS=($(whiptail "${FLAGS[@]}" "${DEVICES[@]}" 3>&1 1>&2 2>&3 3>&-))

  # Check whiptail window return value.
  [[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

  DEVICES=()
fi

# Increase the the free space with the sizes of the partitions for deletion.
for ITEM in ${DELPARTITIONS[@]//\"}; do
  FREESPACE=$(bc <<< "${FREESPACE} + $(sfdisk -s /dev/${ITEM})")
done

# -------------------------------------------------------------------------------------------------
# Find if there is are existing EFI partitions.
TMPLIST=($(lsblk ${DRIVE} -no KNAME | grep -E ${DEVICE}.*[0-9]+))

for ITEM in ${TMPLIST[@]}; do
  [[ "$(lsblk -no PTTYPE /dev/${ITEM})" != "gpt" ]] && continue
  [[ "$(lsblk -no FSTYPE /dev/${ITEM})" != "vfat" ]] && continue
  [[ "$(lsblk -no PARTTYPENAME /dev/${ITEM})" != *"EFI System"* ]] && continue

  # Skip if the partition is among the list for deletion.
  [[ "${DELPARTITIONS[*]}" =~ "${ITEM}" ]] && continue

  description=$(printf "%-10s" "$(lsblk -no LABEL /dev/${ITEM})")
  description+=$(printf " %-10s" "$(lsblk -no FSVER /dev/${ITEM})")
  description+=$(printf " %-10s" "$(lsblk -no MOUNTPOINT /dev/${ITEM})")
  description+=$(printf " %10s" "$(lsblk -no SIZE /dev/${ITEM})")

  # Found an EFI partition, add it to the list.
  DEVICES+=("${ITEM}" "${description}" "off")
done

if [[ ${#DEVICES[@]} != 0 ]]; then
  # Calculate the height based on the number of entries and increase by 10 for window compensation.
  HEIGHT=$((${#DEVICES[@]} / 3 + 10))
  LISTHEIGHT=$((${#DEVICES[@]} / 3))

  DESCRIPTION="Pick EFI partition to reuse or don't choose any in order to create a new partition"
  FLAGS=(--clear --title "${TITLE}" --radiolist "${DESCRIPTION}" ${HEIGHT} 80 ${LISTHEIGHT})

  EFIPARTITION=$(whiptail "${FLAGS[@]}" "${DEVICES[@]}" 3>&1 1>&2 2>&3 3>&-)

  # Check whiptail window return value.
  [[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }
fi

if [ -z ${EFIPARTITION} ]; then
  DESCRIPTION="EFI partition size: (KiB) (Free space: ${FREESPACE} KiB)"
  FLAGS=(--clear --title "${TITLE}" --inputbox "${DESCRIPTION}" 8 60)

  EFISIZE=$(whiptail "${FLAGS[@]}" ${EFISIZE} 3>&1 1>&2 2>&3 3>&-)

  # Check whiptail window return value.
  [[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

  # Check if a size has been chosen.
  [ -z "${EFISIZE}" ] && { msg error "Empty value!"; exit 1; }

  # Check if a size is zero.
  [[ "${EFISIZE}" -eq 0 ]] && { msg error "Zero value!"; exit 1; }

  if [[ ! "${EFISIZE}" =~ ^[0-9]+$ ]]; then
    msg error "EFI size contains invalid characters."; exit 1
  elif [[ ${EFISIZE} -gt ${FREESPACE} ]]; then
    msg error "Choosen EFI size is more than the available free space!"; exit 1
  fi

  # Update free space size.
  FREESPACE=$(bc <<< "${FREESPACE} - ${EFISIZE}")
  CONFIGURATION+="  EFI partition size = ${EFISIZE} (KiB)\n"
else
  EFIPARTITION="/dev/${EFIPARTITION}"
  CONFIGURATION+="  EFI partition = ${EFIPARTITION}\n"
fi

# -------------------------------------------------------------------------------------------------
# Calculate physical RAM size.
for ITEM in /sys/devices/system/memory/memory*; do
  [[ "$(cat ${ITEM}/online)" != "1" ]] && continue
  SWAPSIZE=$((SWAPSIZE + $((0x$(cat /sys/devices/system/memory/block_size_bytes)))));
done

# Convert the bytes to KiB.
SWAPSIZE=$(bc <<< "${SWAPSIZE} / 1024")

# Recommended swap sizes:
#
# RAM < 2 GB: [No Hibernation] - equal to RAM.
#             [With Hibernation] - double the size of RAM.
# RAM > 2 GB: [No Hibernation] - equal to the rounded square root of the RAM.
#             [With Hibernation] - RAM plus the rounded square root of the RAM.
if [[ $(bc <<< "${SWAPSIZE} < (2048 * 1014)") -eq 1 ]]; then
  SWAPSIZE=$(bc <<< "${SWAPSIZE} * 2")
elif [[ $(bc <<< "${SWAPSIZE} >= (2048 * 1014)") -eq 1 ]]; then
  SWAPSIZE=$(bc <<< "${SWAPSIZE} / 1024^2") # To GiB
  SWAPSIZE=$(bc <<< "scale = 1; ${SWAPSIZE} + sqrt(${SWAPSIZE})")
  SWAPSIZE=$(bc <<< "((${SWAPSIZE} + 0.5) / 1) * 1024^2") # Round & convert to KiB.
fi

DESCRIPTION="SWAP partition size: (KiB) (Free space: ${FREESPACE} KiB)"
FLAGS=(--clear --title "${TITLE}" --inputbox "${DESCRIPTION}" 8 60)

SWAPSIZE=$(whiptail "${FLAGS[@]}" ${SWAPSIZE} 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

# Check if a size has been chosen.
[ -z "${SWAPSIZE}" ] && { msg error "Empty value!"; exit 1; }

# Check if a size is zero.
[[ "${SWAPSIZE}" -eq 0 ]] && { msg error "Zero value!"; exit 1; }

if [[ ! "${SWAPSIZE}" =~ ^[0-9]+$ ]]; then
  msg error "SWAP size contains invalid characters."; exit 1
elif [[ ${SWAPSIZE} -gt ${FREESPACE} ]]; then
  msg error "Choosen SWAP size is more than the available free space!"; exit 1
fi

# Update free space size.
FREESPACE=$(bc <<< "${FREESPACE} - ${SWAPSIZE}")
CONFIGURATION+="  SWAP partition size = ${SWAPSIZE} (KiB)\n"

# -------------------------------------------------------------------------------------------------
DESCRIPTION="Enter SWAP partition password.\nLeave empty if encryption is not required."
FLAGS=(--clear --title "${TITLE}" --passwordbox "${DESCRIPTION}" 8 60)

SWAPPASSWORD=$(whiptail "${FLAGS[@]}" ${SWAPPASSWORD} 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

# Check if a root password has been entered.
if [ -z "${SWAPPASSWORD}" ]; then
  CONFIGURATION+="  Password for SWAP partition = NONE\n"
else
  DESCRIPTION="Confirm SWAP partition password:"
  FLAGS=(--clear --title "${TITLE}" --passwordbox "${DESCRIPTION}" 8 60)

  CONFIRMPASSWORD=$(whiptail "${FLAGS[@]}" 3>&1 1>&2 2>&3 3>&-)

  # Check whiptail window return value.
  [[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

  if [[ "${SWAPPASSWORD}" != "${CONFIRMPASSWORD}" ]]; then
    msg error "SWAP passwords do not match!"; exit 1
  fi

  CONFIGURATION+="  Password for SWAP partition = (password hidden)\n"
fi

# -------------------------------------------------------------------------------------------------
DESCRIPTION="SYSTEM partition size: (KiB) (Free space: ${FREESPACE} KiB) 0 == Use all free space"
FLAGS=(--clear --title "${TITLE}" --inputbox "${DESCRIPTION}" 10 60)

SYSTEMSIZE=$(whiptail "${FLAGS[@]}" ${SYSTEMSIZE} 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

# Check if a size has been chosen.
[ -z "${SYSTEMSIZE}" ] && { msg error "Empty value!"; exit 1; }

if [[ ! "${SYSTEMSIZE}" =~ ^[0-9]+$ ]]; then
  msg error "SYSTEM size contains invalid characters."; exit 1
elif [[ ${SYSTEMSIZE} -gt ${FREESPACE} ]]; then
  msg error "Choosen SYSTEM size is more than the available free space!"; exit 1
fi

[ ${SYSTEMSIZE} -eq 0 ] && CONFIGURATION+="  SYSTEM partition size = ${FREESPACE} (KiB)\n"
[ ${SYSTEMSIZE} -ne 0 ] && CONFIGURATION+="  SYSTEM partition size = ${SYSTEMSIZE} (KiB)\n"

# -------------------------------------------------------------------------------------------------
DESCRIPTION="Enter SYSTEM partition password.\nLeave empty if encryption is not required."
FLAGS=(--clear --title "${TITLE}" --passwordbox "${DESCRIPTION}" 8 60)

SYSTEMPASSWORD=$(whiptail "${FLAGS[@]}" ${SYSTEMPASSWORD} 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

# Check if a root password has been entered.
if [ -z "${SYSTEMPASSWORD}" ]; then
  CONFIGURATION+="  Password for SYSTEM partition = NONE\n"
else
  DESCRIPTION="Confirm SYSTEM partition password:"
  FLAGS=(--clear --title "${TITLE}" --passwordbox "${DESCRIPTION}" 8 60)

  CONFIRMPASSWORD=$(whiptail "${FLAGS[@]}" 3>&1 1>&2 2>&3 3>&-)

  # Check whiptail window return value.
  [[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

  if [[ "${SYSTEMPASSWORD}" != "${CONFIRMPASSWORD}" ]]; then
    msg error "SYSTEM passwords do not match!"; exit 1
  fi

  CONFIGURATION+="  Password for SYSTEM partition = (password hidden)\n"
fi

# -------------------------------------------------------------------------------------------------
whiptail --clear --title "${TITLE}" --yesno "Add new user?" 7 30 3>&1 1>&2 2>&3 3>&-

case $? in
  0)
    DESCRIPTION="Enter username: (usernames must be all lowercase)"
    FLAGS=(--clear --title "${TITLE}" --inputbox "${DESCRIPTION}" 8 60)

    USERNAME=$(whiptail "${FLAGS[@]}" ${USERNAME} 3>&1 1>&2 2>&3 3>&-)

    # Check whiptail window return value.
    [[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

    if [[ "${USERNAME}" =~ [A-Z] ]] || [[ "${USERNAME}" == *['!'@#\$%^\&*()_+]* ]]; then
      msg error "Username contains invalid characters."; exit 1
    fi

    # Check if a name has been entered.
    [ -z "${USERNAME}" ] && { msg error "Empty value!"; exit 1; }

    DESCRIPTION="Enter Full Name for ${USERNAME}:"
    FLAGS=(--clear --title "${TITLE}" --inputbox "${DESCRIPTION}" 8 50)

    FULLNAME=$(whiptail "${FLAGS[@]}" "${FULLNAME}" 3>&1 1>&2 2>&3 3>&-)

    # Check whiptail window return value.
    [[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

    # Check if a user name has been entered.
    [ -z "${FULLNAME}" ] && { msg error "Empty value!"; exit 1; }

    DESCRIPTION="Enter additional groups for ${USERNAME} in a comma seperated list:(default is wheel)"
    FLAGS=(--clear --title "${TITLE}" --inputbox "${DESCRIPTION}" 8 90)

    USERGROUPS=$(whiptail "${FLAGS[@]}" "wheel" 3>&1 1>&2 2>&3 3>&-)

    # Check whiptail window return value.
    [[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

    DESCRIPTION="Enter Password for ${USERNAME}:"
    FLAGS=(--clear --title "${TITLE}" --passwordbox "${DESCRIPTION}" 8 60)

    PASSWORD=$(whiptail "${FLAGS[@]}" ${PASSWORD} 3>&1 1>&2 2>&3 3>&-)

    # Check whiptail window return value.
    [[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

    # Check if a password has been entered.
    [ -z "${PASSWORD}" ] && { msg error "Empty value!"; exit 1; }

    DESCRIPTION="Confirm Password for ${USERNAME}:"
    FLAGS=(--clear --title "${TITLE}" --passwordbox "${DESCRIPTION}" 8 60)

    CONFIRMPASSWORD=$(whiptail "${FLAGS[@]}" 3>&1 1>&2 2>&3 3>&-)

    # Check whiptail window return value.
    [[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

    if [[ "${PASSWORD}" != "${CONFIRMPASSWORD}" ]]; then
      msg error "User passwords do not match!"; exit 1
    fi

    CONFIGURATION+="  Username = ${USERNAME} (${FULLNAME})\n"
    CONFIGURATION+="  Additional usergroups = ${USERGROUPS}\n"
    CONFIGURATION+="  Password for ${USERNAME} = (password hidden)\n"
    ;;
  255)
    msg info "Installation aborted...." && exit 1
    ;;
esac

# -------------------------------------------------------------------------------------------------
CONFIRMPASSWORD=${ROOTPASSWORD}

DESCRIPTION="Enter Root Password:(default is 'root')"
FLAGS=(--clear --title "${TITLE}" --passwordbox "${DESCRIPTION}" 8 60)

ROOTPASSWORD=$(whiptail "${FLAGS[@]}" ${ROOTPASSWORD} 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

# Check if a root password has been entered.
[ -z "${ROOTPASSWORD}" ] && { msg error "Empty value!"; exit 1; }

DESCRIPTION="Confirm Root Password:(default is 'root')"
FLAGS=(--clear --title "${TITLE}" --passwordbox "${DESCRIPTION}" 8 60)

CONFIRMPASSWORD=$(whiptail "${FLAGS[@]}" ${CONFIRMPASSWORD} 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

if [[ "${ROOTPASSWORD}" != "${CONFIRMPASSWORD}" ]]; then
  msg error "Root passwords do not match!"; exit 1
fi

# -------------------------------------------------------------------------------------------------
DESCRIPTION="Enter desired hostname for this system:"
FLAGS=(--clear --title "${TITLE}" --inputbox "${DESCRIPTION}" 8 50)

HOSTNAME=$(whiptail "${FLAGS[@]}" ${HOSTNAME} 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

# Check if a host name has been entered.
[ -z "${HOSTNAME}" ] && { msg error "Empty value!"; exit 1; }

CONFIGURATION+="  Hostname = ${HOSTNAME}\n"

# -------------------------------------------------------------------------------------------------
# Retrieve a list with available timezones.
TMPLIST=($(timedatectl list-timezones))

for ITEM in ${TMPLIST[@]}; do
  TIMEZONES+=("${ITEM}" "")
done

DESCRIPTION="Choose your timezone:"
FLAGS=(--clear --title "${TITLE}" --menu "${DESCRIPTION}" 20 50 12)

TIMEZONE=$(whiptail "${FLAGS[@]}" "${TIMEZONES[@]}" 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

# Check if a timezone has been chosen.
[ -z "${TIMEZONE}" ] && { msg error "Empty value!"; exit 1; }

CONFIGURATION+="  Timezone = ${TIMEZONE}\n"

# -------------------------------------------------------------------------------------------------
# Retrieve a list with available locales.
LOCALES=($(awk '/^.*UTF-8/ { print $0 }' /etc/locale.gen | sed -e 's/^#*//' | sort -u))

DESCRIPTION="Choose your language:"
FLAGS=(--clear --title "${TITLE}" --menu "${DESCRIPTION}" 20 50 12)

LANG=$(whiptail "${FLAGS[@]}" "${LOCALES[@]}" 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

# Check if a timezone has been chosen.
[ -z "${LANG}" ] && { msg error "Empty value!"; exit 1; }

CONFIGURATION+="  Language = ${LANG}\n"

# -------------------------------------------------------------------------------------------------
# Retrieve a list with available locales.
LOCALES=($(awk '/^.*UTF-8/ { print $0 " off" }' /etc/locale.gen | sed -e 's/^#*//' | sort -u))

DESCRIPTION="Choose your locales:"
FLAGS=(--clear --title "${TITLE}" --checklist "${DESCRIPTION}" 20 50 12)

LOCALES=($(whiptail "${FLAGS[@]}" "${LOCALES[@]}" 3>&1 1>&2 2>&3 3>&-))

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

# Check if a locale has been chosen.
[ ${#LOCALES[@]} -eq 0 ] && { msg error "Empty value!"; exit 1; }

CONFIGURATION+="  Locales = ${LOCALES[@]}\n"

# -------------------------------------------------------------------------------------------------
# Retrieve a list with available keyboard layouts.
TMPLIST=($(localectl list-keymaps))

for ITEM in ${TMPLIST[@]}; do
  CLIKEYMAPS+=("${ITEM}" "")
done

DESCRIPTION="Choose your TTY keyboard layout:"
FLAGS=(--clear --title "${TITLE}" --menu "${DESCRIPTION}" 20 50 12)

CLIKEYMAP=$(whiptail "${FLAGS[@]}" "${CLIKEYMAPS[@]}" 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

# Check if a keymap has been chosen.
[ -z "${CLIKEYMAP}" ] && { msg error "Empty value!"; exit 1; }

CONFIGURATION+="  TTY Keyboard layout = ${CLIKEYMAP}\n"

# -------------------------------------------------------------------------------------------------
# Retrieve a list with available font layouts.
TMPLIST=($(find /usr/share/kbd/consolefonts/ -type f -name "*.psfu.gz" | \
           awk -F'/' '{ print $6 }' | cut -d'.' -f1))

for ITEM in ${TMPLIST[@]}; do
  CLIFONTS+=("${ITEM}" "")
done

DESCRIPTION="Choose your TTY font layout:"
FLAGS=(--clear --title "${TITLE}" --menu "${DESCRIPTION}" 20 50 12)

CLIFONT=$(whiptail "${FLAGS[@]}" "${CLIFONTS[@]}" 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

# Check if a keymap has been chosen.
[ -z "${CLIFONT}" ] && { msg error "Empty value!"; exit 1; }

CONFIGURATION+="  TTY font layout = ${CLIFONT}\n"

# -------------------------------------------------------------------------------------------------
# Calculate the height based on the number of entries and increase by 10 for window compensation.
HEIGHT=$((${#MICROCODES[@]} / 3 + 10))
LISTHEIGHT=$((${#MICROCODES[@]} / 3))

DESCRIPTION="Pick CPU microcodes (press space):"
FLAGS=(--clear --title "${TITLE}" --checklist "${DESCRIPTION}" ${HEIGHT} 80 ${LISTHEIGHT})

MICROCODES=($(whiptail "${FLAGS[@]}" "${MICROCODES[@]}" 3>&1 1>&2 2>&3 3>&-))

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

[ ${#MICROCODES[@]} != 0 ] && CONFIGURATION+="  Microcodes = ${MICROCODES[@]}\n"

# -------------------------------------------------------------------------------------------------
# Calculate the height based on the number of entries and increase by 10 for window compensation.
HEIGHT=$((${#KERNELPARAMS[@]} / 3 + 10))
LISTHEIGHT=$((${#KERNELPARAMS[@]} / 3))

DESCRIPTION="Optional kernel boot parameters which are not normally required (press space):"
FLAGS=(--clear --title "${TITLE}" --checklist "${DESCRIPTION}" ${HEIGHT} 100 ${LISTHEIGHT})

KERNELPARAMS=($(whiptail "${FLAGS[@]}" "${KERNELPARAMS[@]}" 3>&1 1>&2 2>&3 3>&-))

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

[ ${#KERNELPARAMS[@]} != 0 ] && CONFIGURATION+="  Additional Kernel Params = ${KERNELPARAMS[@]}\n"

# -------------------------------------------------------------------------------------------------
# Calculate the height based on the number of entries and increase by 10 for window compensation.
HEIGHT=$((${#GPUDRIVERS[@]} / 3 + 10))
LISTHEIGHT=$((${#GPUDRIVERS[@]} / 3))

DESCRIPTION="Pick video drivers (press space):"
FLAGS=(--clear --title "${TITLE}" --checklist "${DESCRIPTION}" ${HEIGHT} 90 ${LISTHEIGHT})

GPUDRIVERS=($(whiptail "${FLAGS[@]}" "${GPUDRIVERS[@]}" 3>&1 1>&2 2>&3 3>&-))

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

[ ${#GPUDRIVERS[@]} != 0 ] && CONFIGURATION+="  GPU Drivers = ${GPUDRIVERS[@]}\n"

# -------------------------------------------------------------------------------------------------
# Calculate the height based on the number of entries and increase by 10 for window compensation.
HEIGHT=$((${#ENVIRONMENTS[@]} / 3 + 10))
LISTHEIGHT=$((${#ENVIRONMENTS[@]} / 3))

DESCRIPTION="Pick desktop environment (press space):"
FLAGS=(--clear --title "${TITLE}" --radiolist "${DESCRIPTION}" ${HEIGHT} 80 ${LISTHEIGHT})

ENVIRONMENT=$(whiptail "${FLAGS[@]}" "${ENVIRONMENTS[@]}" 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

CONFIGURATION+="  Environment = ${ENVIRONMENT}"

if [[ ${ENVIRONMENT} == "GNOME" || ${ENVIRONMENT} == "KDE" || ${ENVIRONMENT} == "XFCE" ]]; then
  # Enable the default manager based on the chosen environment.
  [[ ${ENVIRONMENT} == "GNOME" ]] && { DISPLAYMANAGERS[2]="on"; }
  [[ ${ENVIRONMENT} == "KDE" ]] && { DISPLAYMANAGERS[5]="on"; }
  [[ ${ENVIRONMENT} == "XFCE" ]] && { DISPLAYMANAGERS[8]="on"; }

  # Calculate the height based on the number of entries and increase by 10 for window compensation.
  HEIGHT=$((${#DISPLAYMANAGERS[@]} / 3 + 10))
  LISTHEIGHT=$((${#DISPLAYMANAGERS[@]} / 3))

  DESCRIPTION="Pick  display manager (press space):"
  FLAGS=(--clear --title "${TITLE}" --radiolist "${DESCRIPTION}" ${HEIGHT} 90 ${LISTHEIGHT})

  DISPLAYMANAGER=$(whiptail "${FLAGS[@]}" "${DISPLAYMANAGERS[@]}" 3>&1 1>&2 2>&3 3>&-)

  # Check whiptail window return value.
  [[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

  CONFIGURATION+="\n  Display Manager = ${DISPLAYMANAGER}"

  # Calculate the height based on the number of entries and increase by 10 for window compensation.
  HEIGHT=$((${#BROWSERS[@]} / 3 + 10))
  LISTHEIGHT=$((${#BROWSERS[@]} / 3))

  DESCRIPTION="Pick one of more internet browsers (press space):"
  FLAGS=(--clear --title "${TITLE}" --checklist "${DESCRIPTION}" ${HEIGHT} 90 ${LISTHEIGHT})

  BROWSERS=($(whiptail "${FLAGS[@]}" "${BROWSERS[@]}" 3>&1 1>&2 2>&3 3>&-))

  # Check whiptail window return value.
  [[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

  [ ${#BROWSERS[@]} != 0 ] && CONFIGURATION+="\n  Browsers = ${BROWSERS[@]}"

  # Calculate the height based on the number of entries and increase by 10 for window compensation.
  HEIGHT=$((${#HWVIDEOACCELERATION[@]} / 3 + 10))
  LISTHEIGHT=$((${#HWVIDEOACCELERATION[@]} / 3))

  DESCRIPTION="Pick hardware video acceleration drivers (press space):"
  FLAGS=(--clear --title "${TITLE}" --checklist "${DESCRIPTION}" ${HEIGHT} 115 ${LISTHEIGHT})

  HWVIDEOACCELERATION=($(whiptail "${FLAGS[@]}" "${HWVIDEOACCELERATION[@]}" 3>&1 1>&2 2>&3 3>&-))

  # Check whiptail window return value.
  [[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

  if [ ${#HWVIDEOACCELERATION[@]} != 0 ]; then
    CONFIGURATION+="\n  Video Acceleration drivers = ${HWVIDEOACCELERATION[@]}"
  fi
fi

# Calculate the height based on the number of entries and increase by 10 for window compensation.
HEIGHT=$((${#EXTRAPKGS[@]} / 3 + 10))
LISTHEIGHT=$((${#EXTRAPKGS[@]} / 3))

DESCRIPTION="Pick additional packages (press space):"
FLAGS=(--clear --title "${TITLE}" --checklist "${DESCRIPTION}" ${HEIGHT} 80 ${LISTHEIGHT})

EXTRAPKGS=($(whiptail "${FLAGS[@]}" "${EXTRAPKGS[@]}" 3>&1 1>&2 2>&3 3>&-))

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { msg info "Installation aborted..."; exit 1; }

[ ${#EXTRAPKGS[@]} != 0 ] && CONFIGURATION+="\n  Extra packages = ${EXTRAPKGS[@]}"

# -------------------------------------------------------------------------------------------------
# Verify configuration
CONFIGURATION="Is the below information correct:\n${CONFIGURATION}"

# Calculate the height based on the number of lines and increase by 8 for window compensation.
HEIGHT=$(($(printf "${CONFIGURATION}" | wc -l) + 8))

whiptail --clear --title "${TITLE}" --yesno "${CONFIGURATION}" ${HEIGHT} 100 3>&1 1>&2 2>&3 3>&-

case $? in
  0) msg info "Proceeding....";;
  1|255) msg info "Installation aborted..."; exit 1;;
esac

RUNTIME=$(date +%s)
prepare && install && cleanup
RUNTIME=$(echo ${RUNTIME} $(date +%s) | awk '{ printf "%0.2f",($2-$1)/60 }')

msg info "Time: ${RUNTIME} minutes"
