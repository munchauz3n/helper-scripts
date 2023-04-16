#!/bin/bash

# Dependencies.
declare -a DEPENDNECIES=(
  "awk" "grep" "sed" "sfdisk" "sgdisk" "lscpu" "lspci" "lsblk" "bc" "openssl" "wipefs"
  "arch-chroot" "pacstrap" "genfstab" "whiptail" "mkfs.vfat" "mkfs.btrfs"
)

# Temp work directory.
declare TMPDIR="/mnt"

# Global variables.
declare -a TMPLIST=()
declare CONFIGURATION=""

# List of additional bootloader kernel parameters.
declare -a KERNELPARAMS=(
  "acpi_osi=Linux" "Tell BIOS that it's running Linux" "off"
  "acpi_backlight=vendor" "First probe vendor specific backlight drives" "off"
)

# List of available user environments.
declare -a ENVIRONMENTS=(
  "Console" "Bare console environment" "on"
  "GNOME" "Modern and simple desktop - minimal installation" "off"
#  "KDE" "Flashy desktop with many features - minimal installation" "off"
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

# List of possible processor microcodes.
declare -a MICROCODES=(
  "AMD" "Install and enable AMD CPUs microcode updates in bootloader" "off"
  "Intel" "Install and enable Intel CPUs microcode updates in bootloader" "off"
)

# List of possible video drivers.
declare -a VIDEODRIVERS=(
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
  "Touchpad" "Install for touchpad support via the libinput driver" "off"
  "Touchscreen" "Install for touchscreen support via the libinput driver" "off"
  "Wacom" "Install for Wacom stylus support" "off"
)

declare DRIVE=""

declare FREESPACE=""
declare EFISIZE="512"
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

declare CRYPTSWAP=""
declare CRYPTSYSTEM=""

# ============================================================================
# Functions
# ============================================================================
msg() {
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

prepare() {
  msg info "Getting ${DRIVE} ready..."
  local partitions=($(lsblk ${DRIVE} -no KNAME | grep -E ${DEVICE}.*[0-9]+))

  for partition in ${partitions[@]}; do
    msg log "umount partition /dev/${partition} ..."
    umount /dev/${partition} 1> /dev/null 2>&1

    # Check umount return value.
    [[ $? == +(1|255) ]] && { clear; msg error "Failed to umount previous partition!"; exit 1; }
  done

  msg log "Removing any lingering information from previous partitions..."
  sgdisk --zap-all ${DRIVE} 1> /dev/null 2>&1

  # Check sgdisk return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to clear GPT/MBR data!"; exit 1; }

  # Wipe filesystem information.
  wipefs -a ${DRIVE} 1> /dev/null 2>&1

  msg log "Creating partition table..."
  sgdisk --clear \
       --new=1:0:+${EFISIZE}MiB    --typecode=1:ef00 --change-name=1:EFI \
       --new=2:0:+${SWAPSIZE}MiB   --typecode=2:8200 --change-name=2:cryptswap \
       --new=3:0:+${SYSTEMSIZE}MiB --typecode=3:8300 --change-name=3:cryptsystem \
       ${DRIVE} 1> /dev/null 2>&1

  # Check sgdisk return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to create partition table!"; exit 1; }

  partitions=($(lsblk ${DRIVE} -no KNAME | grep -E ${DEVICE}.*[0-9]+))

  msg log "Encrypting Swap partition..."
  echo -n "${SWAPPASSWORD}" | cryptsetup luksFormat --align-payload=8192 \
                                         /dev/${partitions[1]} - 1> /dev/null 2>&1
  echo -n "${SWAPPASSWORD}" | cryptsetup open /dev/${partitions[1]} swap - \
                                         1> /dev/null 2>&1

  msg log "Initializing Swap partition..."
  mkswap -L swap /dev/mapper/swap 1> /dev/null 2>&1
  swapon -L swap 1> /dev/null 2>&1

  msg log "Encrypting System partition..."
  echo -n "${SYSTEMPASSWORD}" | cryptsetup luksFormat --type luks1 --iter-time 5000 \
                                           --align-payload=8192 /dev/${partitions[2]} - \
                                           1> /dev/null 2>&1
  echo -n "${SYSTEMPASSWORD}" | cryptsetup open /dev/${partitions[2]} system - 1> /dev/null 2>&1

  msg log "Creating and mounting System BTRFS Subvolumes..."
  mkfs.btrfs --force --label system /dev/mapper/system  1> /dev/null 2>&1

  # Check mkfs return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to create system volume!"; exit 1; }

  msg log "Mount system volume..."
  mount -t btrfs LABEL=system ${TMPDIR}  1> /dev/null 2>&1

  # Check mount return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to mount system volume!"; exit 1; }

  msg log "Create root subvolume..."
  btrfs subvolume create ${TMPDIR}/root  1> /dev/null 2>&1

  # Check btrfs return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to create root subvolume!"; exit 1; }

  msg log "Create home subvolume..."
  btrfs subvolume create ${TMPDIR}/home  1> /dev/null 2>&1

  # Check btrfs return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to create home subvolume!"; exit 1; }

  msg log "Create snapshots subvolume..."
  btrfs subvolume create ${TMPDIR}/snapshots  1> /dev/null 2>&1

  # Check btrfs return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to create snapshosts subvolume!"; exit 1; }

  msg log "Umount system volume..."
  umount -R ${TMPDIR}  1> /dev/null 2>&1

  # Check umount return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to umount system volume!"; exit 1; }

  local options="defaults,x-mount.mkdir,compress=lzo,ssd,noatime"

  msg log "Mount root subvolume..."
  mount -t btrfs -o subvol=root,${options} LABEL=system ${TMPDIR}  1> /dev/null 2>&1

  # Check mount return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to mount root subvolume!"; exit 1; }

  msg log "Mount home subvolume..."
  mount -t btrfs -o subvol=home,${options} LABEL=system ${TMPDIR}/home  1> /dev/null 2>&1

  # Check mount return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to mount home subvolume!"; exit 1; }

  msg log "Mount snapshots subvolume..."
  mount -t btrfs -o subvol=snapshots,${options} LABEL=system ${TMPDIR}/.snapshots  1> /dev/null 2>&1

  # Check mount return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to mount snapshots subvolume!"; exit 1; }

  msg log "Formating EFI partition..."
  mkfs.vfat  /dev/${partitions[0]} -F 32 -n EFI 1> /dev/null 2>&1

  # Check mkfs return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to format EFI partition!"; exit 1; }

  msg log "Mounting EFI partition..."
  mkdir ${TMPDIR}/efi  1> /dev/null 2>&1
  mount /dev/${partitions[0]} ${TMPDIR}/efi 1> /dev/null 2>&1

  # Check mount return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to mount EFI partition!"; exit 1; }

  # Save the encrypted partitions for later use.
  CRYPTSWAP="/dev/${partitions[1]}"
  CRYPTSYSTEM="/dev/${partitions[2]}"

  msg log "Done"
}

setup_console_environment() {
  msg log "Installing ACPI daemon..."
  pacstrap ${TMPDIR} acpid 1> /dev/null 2>&1

  # Check pacstrap return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to install ACPI daemon!"; exit 1; }

  msg log "Enabling ACPI daemon service..."
  arch-chroot ${TMPDIR} systemctl enable acpid.service 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to enable ACPI service!"; exit 1; }

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
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to enable network daemon service!"; exit 1; }

  msg log "Enabling resolved service..."
  arch-chroot ${TMPDIR} systemctl enable systemd-resolved.service 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to enable resolve daemon service!"; exit 1; }
}

setup_common_environment() {
  msg log "Installing Xorg display server and xinitrc..."
  pacstrap ${TMPDIR} xorg-server xorg-xinit 1> /dev/null 2>&1

  # Check pacstrap return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to install xorg and xinitrc!"; exit 1; }

  msg log "Installing Xorg relates packages..."
  pacstrap ${TMPDIR} xorg-xset xorg-xprop xorg-xrandr xorg-xclock xdg-utils 1> /dev/null 2>&1

  # Check pacstrap return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to install xorg relatd packages!"; exit 1; }

  msg log "Installing video drivers..."
  pacstrap ${TMPDIR} xf86-video-vesa 1> /dev/null 2>&1

  # Check pacstrap return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to install vesa drivers!"; exit 1; }

  [[ ${VIDEODRIVERS[@]} == *"AMD"* ]] && pacstrap ${TMPDIR} xf86-video-amdgpu 1> /dev/null 2>&1
  [[ ${VIDEODRIVERS[@]} == *"ATI"* ]] && pacstrap ${TMPDIR} xf86-video-ati 1> /dev/null 2>&1
  [[ ${VIDEODRIVERS[@]} == *"NVidia"* ]] && pacstrap ${TMPDIR} xf86-video-nouveau 1> /dev/null 2>&1
  [[ ${VIDEODRIVERS[@]} == *"Intel"* ]] && pacstrap ${TMPDIR} xf86-video-intel 1> /dev/null 2>&1

  # Check pacstrap return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to install video drivers!"; exit 1; }

  if [[ ${VIDEODRIVERS[@]} == *"AMD"* ]]; then
    msg log "Installing Vulkan drivers for AMD..."
    pacstrap ${TMPDIR} vulkan-icd-loader vulkan-radeon 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { clear; msg error "Failed to install Vulkan drivers for AMD!"; exit 1; }
  fi

  if [[ ${VIDEODRIVERS[@]} == *"Intel"* ]]; then
    msg log "Installing Vulkan drivers for Intel..."
    pacstrap ${TMPDIR} vulkan-icd-loader vulkan-intel 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { clear; msg error "Failed to install Vulkan drivers for Intel!"; exit 1; }
  fi

  if [[ ${HWVIDEOACCELERATION[@]} == *"Mesa VA-API"* ]]; then
    msg log "Installing Mesa VA-API drivers..."
    pacstrap ${TMPDIR} libva-mesa-driver 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { clear; msg error "Failed to install VA-API drivers!"; exit 1; }
  fi

  if [[ ${HWVIDEOACCELERATION[@]} == *"Mesa VDPAU"* ]]; then
    msg log "Installing Mesa VDPAU drivers..."
    pacstrap ${TMPDIR} mesa-vdpau 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { clear; msg error "Failed to install VDPAU drivers!"; exit 1; }
  fi

  if [[ ${HWVIDEOACCELERATION[@]} == *"Intel VA-API(>= Broadwell)"* ]]; then
    msg log "Installing Intel VA-API drivers for Broadwell and newer graphics..."
    pacstrap ${TMPDIR} intel-media-driver 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { clear; msg error "Failed to install VA-API drivers for Broadwell!"; exit 1; }
  fi

  if [[ ${HWVIDEOACCELERATION[@]} == *"Intel VA-API(<= Haswell)"* ]]; then
    msg log "Installing Intel VA-API drivers for Haswell and older graphics..."
    pacstrap ${TMPDIR} libva-intel-driver 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { clear; msg error "Failed to install VA-API drivers for Haswell!"; exit 1; }
  fi

  if [[ ${EXTRAPKGS[@]} == *"Touchscreen"* || ${EXTRAPKGS[@]} == *"Touchpad"* ]]; then
    msg log "Installing touchscreen/touchpad packages..."
    pacstrap ${TMPDIR} xf86-input-libinput 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { clear; msg error "Failed to install touchscreen/touchpad packages!"; exit 1; }
  fi

  if [[ ${EXTRAPKGS[@]} == *"Wacom"* ]]; then
    msg log "Installing Wacom packages..."
    pacstrap ${TMPDIR} xf86-input-wacom 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { clear; msg error "Failed to install Wacom packages!"; exit 1; }
  fi

  if [[ ${DISPLAYMANAGER} == "GDM" ]]; then
    msg log "Installing GDM package..."
    pacstrap ${TMPDIR} gdm 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { clear; msg error "Failed to install GDM package!"; exit 1; }

    msg log "Enabling the GDM service..."
    arch-chroot ${TMPDIR} systemctl enable gdm.service 1> /dev/null 2>&1

    # Check arch-chroot return value.
    [[ $? == +(1|255) ]] && { clear; msg error "Failed to enable GDM service!"; exit 1; }
  elif [[ ${DISPLAYMANAGER} == "SDDM" ]]; then
    msg log "Installing SDDM package..."
    pacstrap ${TMPDIR} gdm 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { clear; msg error "Failed to install SDDM package!"; exit 1; }

    msg log "Enabling the SDDM service..."
    arch-chroot ${TMPDIR} systemctl enable sddm.service 1> /dev/null 2>&1

    # Check arch-chroot return value.
    [[ $? == +(1|255) ]] && { clear; msg error "Failed to enable SDDM service!"; exit 1; }
  elif [[ ${DISPLAYMANAGER} == "LightDM(GTK)" || ${DISPLAYMANAGER} == "LightDM(slick)" ]]; then
    msg log "Installing LightDM and greeter packages..."

    if [[ ${DISPLAYMANAGER} == "LightDM(GTK)" ]]; then
      pacstrap ${TMPDIR} lightdm lightdm-gtk-greeter lightdm-gtk-greeter-settings 1> /dev/null 2>&1

      # Check pacstrap return value.
      [[ $? == +(1|255) ]] && { clear; msg error "Failed to install LightDM packages!"; exit 1; }

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
      [[ $? == +(1|255) ]] && { clear; msg error "Failed to install LightDM packages!"; exit 1; }

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
    [[ $? == +(1|255) ]] && { clear; msg error "Failed to enable LightDM service!"; exit 1; }
  elif [[ ${DISPLAYMANAGER} == "LXDM" ]]; then
    msg log "Installing LXDM package..."
    pacstrap ${TMPDIR} lxdm-gtk3 librsvg 1> /dev/null 2>&1

    # Check pacstrap return value.
    [[ $? == +(1|255) ]] && { clear; msg error "Failed to install LXDM package!"; exit 1; }

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
    [[ $? == +(1|255) ]] && { clear; msg error "Failed to enable LXDM service!"; exit 1; }
  fi
}

setup_gnome_environment() {
  msg log "Installing GNOME packages..."
  pacstrap ${TMPDIR} baobab eog evince file-roller gedit gnome-backgrounds \
           gnome-calculator gnome-calendar gnome-clocks gnome-control-center gnome-logs gnome-menus \
           gnome-remote-desktop gnome-screenshot gnome-session gnome-settings-daemon gnome-shell \
           gnome-shell-extensions gnome-system-monitor gnome-terminal gnome-tweaks gnome-themes-extra \
           gnome-user-docs gnome-user-share gnome-video-effects gnome-weather gnome-bluetooth \
           gnome-icon-theme-extras gnome-software gnome-keyring mutter nautilus sushi gvfs yelp guake \
           pulseaudio pavucontrol networkmanager 1> /dev/null 2>&1

  msg log "Configuring NetworkManager to use iwd as the Wi-Fi backend..."
  echo "[device]" > ${TMPDIR}/etc/NetworkManager/conf.d/wifi-backend.conf
  echo "wifi.backend=iwd" >> ${TMPDIR}/etc/NetworkManager/conf.d/wifi-backend.conf

  msg log "Disabling the wpa_supplicant service..."
  arch-chroot ${TMPDIR} systemctl disable wpa_supplicant.service 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to disable wpa_suplicant service!"; exit 1; }

  msg log "Enabling the NetworkManager service..."
  arch-chroot ${TMPDIR} systemctl enable NetworkManager.service 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to enable NetworkManager service!"; exit 1; }
}

setup_xfce_environment() {
  msg log "Installing XFCE packages..."
  pacstrap ${TMPDIR} exo garcon mousepad thunar thunar-volman tumbler xfwm4 xfwm4-themes ristretto \
           xfce4-appfinder xfce4-panel xfce4-power-manager xfce4-session xfce4-pulseaudio-plugin \
           xfce4-taskmanager xfce4-screenshooter xfce4-notifyd xfce4-xkb-plugin xfce4-mount-plugin \
           xfce4-whiskermenu-plugin xfce4-battery-plugin xfce4-sensors-plugin xfce4-settings \
           xfce4-terminal xfce4-screensaver pulseaudio pavucontrol xfdesktop xfconf networkmanager \
           network-manager-applet 1> /dev/null 2>&1

  # Check pacstrap return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to install XFCE packages!"; exit 1; }

  msg log "Configuring NetworkManager to use iwd as the Wi-Fi backend..."
  echo "[device]" > ${TMPDIR}/etc/NetworkManager/conf.d/wifi-backend.conf
  echo "wifi.backend=iwd" >> ${TMPDIR}/etc/NetworkManager/conf.d/wifi-backend.conf

  msg log "Disabling the wpa_supplicant service..."
  arch-chroot ${TMPDIR} systemctl disable wpa_supplicant.service 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to disable wpa_suplicant service!"; exit 1; }

  msg log "Enabling the NetworkManager service..."
  arch-chroot ${TMPDIR} systemctl enable NetworkManager.service 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to enable NetworkManager service!"; exit 1; }
}

installation() {
  msg info "Creating installation..."

  msg log "Installing base packages..."
  pacstrap ${TMPDIR} base base-devel linux linux-firmware util-linux usbutils man-db man-pages texinfo \
           bash-completion openssh sudo gptfdisk tree wget vim iwd cryptsetup grub efibootmgr acpi \
           btrfs-progs lm_sensors ntp dbus alsa-utils cronie terminus-font ttf-dejavu ttf-liberation \
           ntfs-3g libxkbcommon xdg-user-dirs 1> /dev/null 2>&1

  # Check pacstrap return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to install base packages!"; exit 1; }

  # Enabling microcode updates, grub-mkconfig will automatically detect
  # microcode updates and configure appropriately.
  [[ ${MICROCODES[@]} == *"AMD"* ]] && pacstrap ${TMPDIR} amd-ucode 1> /dev/null 2>&1
  [[ ${MICROCODES[@]} == *"Intel"* ]] && pacstrap ${TMPDIR} intel-ucode 1> /dev/null 2>&1

  # Check pacstrap return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to install microcodes!"; exit 1; }

  msg log "Generate fstab..."
  genfstab -L -p ${TMPDIR} >> ${TMPDIR}/etc/fstab

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to generate fstab!"; exit 1; }

  msg log "Setting password for root..."
  awk -i inplace -F: "BEGIN {OFS=FS;} \
      \$1 == \"root\" {\$2=\"$(openssl passwd -6 ${ROOTPASSWORD})\"} 1" \
      ${TMPDIR}/etc/shadow 1> /dev/null 2>&1

  # Check awk return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to configure the root password!"; exit 1; }

  msg log "Set timezone, locales, keyboard, fonts and hostname..."
  arch-chroot ${TMPDIR} ln -sf /usr/share/zoneinfo/"${TIMEZONE}" \
                               /etc/localtime 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to set time zone!"; exit 1; }

  msg log "Set hardware clock..."
  arch-chroot ${TMPDIR} hwclock --systohc 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to set HW clock!"; exit 1; }

  msg log "Setting locales..."
  for locale in "${LOCALES[@]//\"}"; do
    sed -i s/"#${locale}"/"${locale}"/g ${TMPDIR}/etc/locale.gen 1> /dev/null 2>&1

    # Check sed return value.
    [[ $? == +(1|255) ]] && { clear; msg error "Failed to set '${locale}'!"; exit 1; }
  done

  echo "LANG=${LANG}" > ${TMPDIR}/etc/locale.conf
  arch-chroot ${TMPDIR} locale-gen 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to generate locales!"; exit 1; }

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
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to add group 'wheel' to sudoers!"; exit 1; }

  if [ ! -z ${USERNAME} ]; then
    msg log "Setting user ${USERNAME}..."
    arch-chroot ${TMPDIR} useradd -m -G wheel,storage,optical,scanner \
                                  -s /bin/bash ${USERNAME} 1> /dev/null 2>&1

    # Check arch-chroot return value.
    [[ $? == +(1|255) ]] && { clear; msg error "Failed to add user!"; exit 1; }

    msg log "Setting password for user ${USERNAME} ..."
    awk -i inplace -F: "BEGIN {OFS=FS;} \
        \$1 == \"${USERNAME}\" {\$2=\"$(openssl passwd -6 ${PASSWORD})\"} 1" \
        ${TMPDIR}/etc/shadow 1> /dev/null 2>&1

    # Check awk return value.
    [[ $? == +(1|255) ]] && { clear; msg error "Failed to configure the user password!"; exit 1; }

    msg log "Adding groups '${USERGROUPS}' to user '${USERNAME}'..."
    arch-chroot ${TMPDIR} usermod -aG ${USERGROUPS} ${USERNAME} 1> /dev/null 2>&1

    # Check arch-chroot return value.
    [[ $? == +(1|255) ]] && { clear; msg error "Failed to modify user groups!"; exit 1; }

    msg log "Set fullname for '${USERNAME}'..."
    arch-chroot ${TMPDIR} chfn -f "${FULLNAME}" ${USERNAME} 1> /dev/null 2>&1

    # Check arch-chroot return value.
    [[ $? == +(1|255) ]] && { clear; msg error "Failed to set full name!"; exit 1; }
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
  if [[ ${VIDEODRIVERS[@]} == *"AMD"* ]]; then
    [[ -z ${module} ]] && module+="amdgpu" || module+=" amdgpu"
  fi

  if [[ ${VIDEODRIVERS[@]} == *"ATI"* ]]; then
    [[ -z ${module} ]] && module+="radeon" || module+=" radeon"
  fi

  if [[ ${VIDEODRIVERS[@]} == *"NVidia"* ]]; then
    [[ -z ${module} ]] && module+="nouveau" || module+=" nouveau"
  fi

  if [[ ${VIDEODRIVERS[@]} == *"Intel"* ]]; then
    [[ -z ${module} ]] && module+="i915" || module+=" i915"
  fi

  sed -i "s/^MODULES=\(.*\)/MODULES=\(${module}\)/g" \
      ${TMPDIR}/etc/mkinitcpio.conf 1> /dev/null 2>&1

  msg log "Configuring GRUB..."

  local cmdline="${KERNELPARAMS[@]//\"}"
  sed -i "/^GRUB_CMDLINE_LINUX=/ s/\(.*\)\"/\1${cmdline}\"/" \
      ${TMPDIR}/etc/default/grub 1> /dev/null 2>&1

  # Set the kernel parameters, so initramfs can unlock the encrypted partitions.
  [[ ! -z ${cmdline} ]] && cmdline=" rd.luks.name=$(lsblk -dno UUID ${CRYPTSYSTEM})=system"
  [[ -z ${cmdline} ]] && cmdline="rd.luks.name=$(lsblk -dno UUID ${CRYPTSYSTEM})=system"
  cmdline+=" root=/dev/mapper/system"

  sed -i "/^GRUB_CMDLINE_LINUX=/ s/\(.*\)\"/\1${cmdline//\//\\/}\"/" \
      ${TMPDIR}/etc/default/grub 1> /dev/null 2>&1

  cmdline=" rd.luks.name=$(lsblk -dno UUID ${CRYPTSWAP})=swap"
  cmdline+=" resume=/dev/mapper/swap"

  sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/\(.*\)\"/\1${cmdline//\//\\/}\"/" \
      ${TMPDIR}/etc/default/grub 1> /dev/null 2>&1

  # Configure GRUB to allow booting from /boot on a LUKS1 encrypted partition.
  sed -i s/"^#GRUB_ENABLE_CRYPTODISK=y"/"GRUB_ENABLE_CRYPTODISK=y"/g \
      ${TMPDIR}/etc/default/grub 1> /dev/null 2>&1

  # Restruct /boot permissions.
  chmod 700 ${TMPDIR}/boot

  msg log "Creating crypt keys..."

  local cryptdir="/etc/cryptsetup-keys.d"
  mkdir ${TMPDIR}${cryptdir} && chmod 700 ${TMPDIR}${cryptdir} 1> /dev/null 2>&1

  dd bs=512 count=4 if=/dev/urandom of=${TMPDIR}${cryptdir}/cryptswap.key 1> /dev/null 2>&1
  chmod 600 ${TMPDIR}${cryptdir}/cryptswap.key 1> /dev/null 2>&1

  echo -n "${SWAPPASSWORD}" | cryptsetup -v luksAddKey -i 1 ${CRYPTSWAP} \
      ${TMPDIR}${cryptdir}/cryptswap.key - 1> /dev/null 2>&1

  dd bs=512 count=4 if=/dev/urandom of=${TMPDIR}${cryptdir}/cryptsystem.key 1> /dev/null 2>&1
  chmod 600 ${TMPDIR}${cryptdir}/cryptsystem.key 1> /dev/null 2>&1

  echo -n "${SYSTEMPASSWORD}" | cryptsetup -v luksAddKey -i 1 ${CRYPTSYSTEM} \
      ${TMPDIR}${cryptdir}/cryptsystem.key - 1> /dev/null 2>&1

  # Add the keys to the initramfs.
  local files="${cryptdir}/cryptswap.key ${cryptdir}/cryptsystem.key"
  sed -i "s/^FILES=\(.*\)/FILES=\(${files//\//\\/}\)/g" \
      ${TMPDIR}/etc/mkinitcpio.conf 1> /dev/null 2>&1

  # Add the keys to the grub configuration
  cmdline="rd.luks.key=$(lsblk -dno UUID ${CRYPTSWAP})=${cryptdir}/cryptswap.key"
  sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/\(.*\)\"/\1 ${cmdline//\//\\/}\"/" \
      ${TMPDIR}/etc/default/grub 1> /dev/null 2>&1

  cmdline="rd.luks.key=$(lsblk -dno UUID ${CRYPTSYSTEM})=${cryptdir}/cryptsystem.key"
  sed -i "/^GRUB_CMDLINE_LINUX=/ s/\(.*\)\"/\1 ${cmdline//\//\\/}\"/" \
      ${TMPDIR}/etc/default/grub 1> /dev/null 2>&1

  msg log "Recreate initramfs..."
  arch-chroot ${TMPDIR} mkinitcpio -P 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to recreate initramfs!"; exit 1; }

  msg log "Installing GRUB in /efi..."
  arch-chroot ${TMPDIR} grub-install --target=x86_64-efi --efi-directory=/efi \
                                     --bootloader-id=GRUB --recheck 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to install GRUB!"; exit 1; }

  msg log "Creating GRUB configuration file..."
  arch-chroot ${TMPDIR} grub-mkconfig -o /boot/grub/grub.cfg 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to create GRUB configuration!"; exit 1; }

  msg log "Enabling NTP(Network Time Protocol) daemon service..."
  arch-chroot ${TMPDIR} systemctl enable ntpd 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to enable NTP daemon service!"; exit 1; }

  msg log "Enabling the iwd service..."
  arch-chroot ${TMPDIR} systemctl enable iwd.service 1> /dev/null 2>&1

  # Check arch-chroot return value.
  [[ $? == +(1|255) ]] && { clear; msg error "Failed to enable iw daemon service!"; exit 1; }

  msg log "Setup ${ENVIRONMENT} environment..."
  [[ ${ENVIRONMENT} == "Console" ]] && { setup_console_environment; }
  [[ ${ENVIRONMENT} == "GNOME" ]] && { setup_common_environment; setup_gnome_environment; }
  [[ ${ENVIRONMENT} == "XFCE" ]] && { setup_common_environment; setup_xfce_environment; }

  msg log "Install complete"
}

cleanup() {
  msg info "Cleanup..."

  umount -R ${TMPDIR}

  msg log "Done"
}


# ============================================================================
# MAIN
# ============================================================================
if [ "${EUID}" -ne 0 ]; then
  msg error "Script requires root privalages!"
  exit 1
fi

# Checks for dependencies
for cmd in "${DEPENDNECIES[@]}"; do
  if ! [[ -f "/bin/${cmd}" || -f "/sbin/${cmd}" || \
          -f "/usr/bin/${cmd}" || -f "/usr/sbin/${cmd}" ]] ; then
    msg error "${cmd} command is missing! Please install the relevant package."
    exit 1
  fi
done

# -----------------------------------------------------------------------------
# Retrieve a list with curently available devices
TMPLIST=($(lsblk -dn -o NAME))

for i in ${TMPLIST[@]}; do
  DEVICES+=("${i}" " $(lsblk -dn -o SIZE /dev/${i})")
done

DEVICE=$(whiptail --title "Arch Linux Installer" \
 --menu "Choose drive - Be sure the correct device is selected!" 20 50 10 \
 "${DEVICES[@]}" 3>&2 2>&1 1>&3)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

# Check if a device has been chosen.
[ -z "${DEVICE}" ] && { clear; msg error "Empty value!"; exit 1; }

DRIVE="/dev/${DEVICE}"
CONFIGURATION+="  Drive = ${DRIVE}\n"

# -----------------------------------------------------------------------------
# Find out the total disk size (GiB).
FREESPACE=$(sfdisk -l ${DRIVE} | awk '/Sector size/ { print $4 }' | awk -F'/' '{ print $1 }')
FREESPACE=$(bc <<< "($(sfdisk -l ${DRIVE} | awk '/sectors$/ { print $7 }') - 2048) * ${FREESPACE}")
FREESPACE=$(bc <<< "${FREESPACE} / 1024^2")

EFISIZE=$(whiptail --clear --title "Arch Linux Installer" \
  --inputbox "EFI partition size: (MiB) (Free space: ${FREESPACE} MiB)" 8 60 \
  ${EFISIZE} 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

# Check if a size has been chosen.
[ -z "${EFISIZE}" ] && { clear; msg error "Empty value!"; exit 1; }

# Check if a size is zero.
[[ "${EFISIZE}" -eq 0 ]] && { clear; msg error "Zero value!"; exit 1; }

if [[ ! "${EFISIZE}" =~ ^[0-9]+$ ]]; then
  clear; msg error "EFI size contains invalid characters."; exit 1
elif [[ ${EFISIZE} -gt ${FREESPACE} ]]; then
  clear; msg error "Choosen EFI size is more than the available free space!"; exit 1
fi

# Update free space size.
FREESPACE=$(bc <<< "${FREESPACE} - ${EFISIZE}")
CONFIGURATION+="  EFI partition size = ${EFISIZE} (MiB)\n"

# -----------------------------------------------------------------------------
# Calculate physical RAM size.
for mem in /sys/devices/system/memory/memory*; do
  [[ "$(cat ${mem}/online)" != "1" ]] && continue
  SWAPSIZE=$((SWAPSIZE + $((0x$(cat /sys/devices/system/memory/block_size_bytes)))));
done

# Convert the bytes to MiB.
SWAPSIZE=$(bc <<< "${SWAPSIZE} / 1024^2")

# Recommended swap sizes:
#
# RAM < 2 GB: [No Hibernation] - equal to RAM.
#             [With Hibernation] - double the size of RAM.
# RAM > 2 GB: [No Hibernation] - equal to the rounded square root of the RAM.
#             [With Hibernation] - RAM plus the rounded square root of the RAM.
if [[ $(bc <<< "${SWAPSIZE} < 2048") -eq 1 ]]; then
  SWAPSIZE=$(bc <<< "${SWAPSIZE} * 2")
elif [[ $(bc <<< "${SWAPSIZE} >= 2048") -eq 1 ]]; then
  SWAPSIZE=$(bc <<< "${SWAPSIZE} / 1024") # To GiB
  SWAPSIZE=$(bc <<< "scale = 1; ${SWAPSIZE} + sqrt(${SWAPSIZE})")
  SWAPSIZE=$(bc <<< "((${SWAPSIZE} + 0.5) / 1) * 1024") # Round & convert to MiB.
fi

SWAPSIZE=$(whiptail --clear --title "Arch Linux Installer" \
  --inputbox "SWAP partition size: (MiB) (Free space: ${FREESPACE} MiB)" 8 60 \
  ${SWAPSIZE} 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

# Check if a size has been chosen.
[ -z "${SWAPSIZE}" ] && { clear; msg error "Empty value!"; exit 1; }

# Check if a size is zero.
[[ "${SWAPSIZE}" -eq 0 ]] && { clear; msg error "Zero value!"; exit 1; }

if [[ ! "${SWAPSIZE}" =~ ^[0-9]+$ ]]; then
  clear; msg error "SWAP size contains invalid characters."; exit 1
elif [[ ${SWAPSIZE} -gt ${FREESPACE} ]]; then
  clear; msg error "Choosen SWAP size is more than the available free space!"; exit 1
fi

# Update free space size.
FREESPACE=$(bc <<< "${FREESPACE} - ${SWAPSIZE}")
CONFIGURATION+="  SWAP partition size = ${SWAPSIZE} (MiB)\n"

# -----------------------------------------------------------------------------
SWAPPASSWORD=$(whiptail --clear --title "Arch Linux Installer" \
  --passwordbox "Enter SWAP partition password:" 8 60 \
  ${SWAPPASSWORD} 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

# Check if a root password has been entered.
[ -z "${SWAPPASSWORD}" ] && { clear; msg error "Empty value!"; exit 1; }

CONFIRMPASSWORD=$(whiptail --clear --title "Arch Linux Installer" \
  --passwordbox "Confirm SWAP partition password:" 8 60 \
  3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

if [[ "${SWAPPASSWORD}" != "${CONFIRMPASSWORD}" ]]; then
  clear; msg error "SWAP passwords do not match!"; exit 1
fi

CONFIGURATION+="  Password for SWAP partition = (password hidden)\n"

# -----------------------------------------------------------------------------
SYSTEMSIZE=$(whiptail --clear --title "Arch Linux Installer" --inputbox \
  "SYSTEM partition size: (MiB) (Free space: ${FREESPACE} MiB)
  0 == Use all available free space" 10 60 ${SYSTEMSIZE} 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

# Check if a size has been chosen.
[ -z "${SYSTEMSIZE}" ] && { clear; msg error "Empty value!"; exit 1; }

if [[ ! "${SYSTEMSIZE}" =~ ^[0-9]+$ ]]; then
  clear; msg error "SYSTEM size contains invalid characters."; exit 1
elif [[ ${SYSTEMSIZE} -gt ${FREESPACE} ]]; then
  clear; msg error "Choosen SYSTEM size is more than the available free space!"; exit 1
fi

[ ${SYSTEMSIZE} -eq 0 ] && CONFIGURATION+="  SYSTEM partition size = ${FREESPACE} (MiB)\n"
[ ${SYSTEMSIZE} -ne 0 ] && CONFIGURATION+="  SYSTEM partition size = ${SYSTEMSIZE} (MiB)\n"

# -----------------------------------------------------------------------------
SYSTEMPASSWORD=$(whiptail --clear --title "Arch Linux Installer" \
  --passwordbox "Enter SYSTEM partition password:" 8 60 \
  ${SYSTEMPASSWORD} 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

# Check if a root password has been entered.
[ -z "${SYSTEMPASSWORD}" ] && { clear; msg error "Empty value!"; exit 1; }

CONFIRMPASSWORD=$(whiptail --clear --title "Arch Linux Installer" \
  --passwordbox "Confirm SYSTEM partition password:" 8 60 \
  3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

if [[ "${SYSTEMPASSWORD}" != "${CONFIRMPASSWORD}" ]]; then
  clear; msg error "SYSTEM passwords do not match!"; exit 1
fi

CONFIGURATION+="  Password for SYSTEM partition = (password hidden)\n"

# -----------------------------------------------------------------------------
whiptail --clear --title "Arch Linux Installer" \
  --yesno "Add new user?" 7 30 3>&1 1>&2 2>&3 3>&-

case $? in
  0) USERNAME=$(whiptail --clear --title "Arch Linux Installer" \
       --inputbox "Enter username: (usernames must be all lowercase)" \
       8 60 ${USERNAME} 3>&1 1>&2 2>&3 3>&-)

     # Check whiptail window return value.
     [[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

     if [[ "${USERNAME}" =~ [A-Z] ]] || [[ "${USERNAME}" == *['!'@#\$%^\&*()_+]* ]]; then
       clear; msg error "Username contains invalid characters."; exit 1
     fi

     # Check if a name has been entered.
     [ -z "${USERNAME}" ] && { clear; msg error "Empty value!"; exit 1; }

     FULLNAME=$(whiptail --clear --title "Arch Linux Installer" \
       --inputbox "Enter Full Name for ${USERNAME}:" 8 50 "${FULLNAME}" \
       3>&1 1>&2 2>&3 3>&-)

     # Check whiptail window return value.
     [[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

     # Check if a user name has been entered.
     [ -z "${FULLNAME}" ] && { clear; msg error "Empty value!"; exit 1; }

     USERGROUPS=$(whiptail --clear --title "Arch Linux Installer" --inputbox \
       "Enter additional groups for ${USERNAME} in a comma seperated list:(default is wheel)" \
       8 90 "wheel" 3>&1 1>&2 2>&3 3>&-)

     # Check whiptail window return value.
     [[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

     PASSWORD=$(whiptail --clear --title "Arch Linux Installer" \
       --passwordbox "Enter Password for ${USERNAME}:" 8 60 \
       ${PASSWORD} 3>&1 1>&2 2>&3 3>&-)

     # Check whiptail window return value.
     [[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

     # Check if a password has been entered.
     [ -z "${PASSWORD}" ] && { clear; msg error "Empty value!"; exit 1; }

     CONFIRMPASSWORD=$(whiptail --clear --title "Arch Linux Installer" \
       --passwordbox "Confirm Password for ${USERNAME}:" 8 60 \
       3>&1 1>&2 2>&3 3>&-)

     # Check whiptail window return value.
     [[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

     if [[ "${PASSWORD}" != "${CONFIRMPASSWORD}" ]]; then
       clear; msg error "User passwords do not match!"; exit 1
     fi

     CONFIGURATION+="  Username = ${USERNAME} (${FULLNAME})\n"
     CONFIGURATION+="  Additional usergroups = ${USERGROUPS}\n"
     CONFIGURATION+="  Password for ${USERNAME} = (password hidden)\n"
     ;;
  255) clear; msg info "Installation aborted...."; exit 1;;
esac

# -----------------------------------------------------------------------------
CONFIRMPASSWORD=${ROOTPASSWORD}

ROOTPASSWORD=$(whiptail --clear --title "Arch Linux Installer" \
  --passwordbox "Enter Root Password:(default is 'root')" 8 60 \
  ${ROOTPASSWORD} 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

# Check if a root password has been entered.
[ -z "${ROOTPASSWORD}" ] && { clear; msg error "Empty value!"; exit 1; }

CONFIRMPASSWORD=$(whiptail --clear --title "Arch Linux Installer" \
  --passwordbox "Confirm Root Password:(default is 'root')" 8 60 ${CONFIRMPASSWORD} \
  3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

if [[ "${ROOTPASSWORD}" != "${CONFIRMPASSWORD}" ]]; then
  clear; msg error "Root passwords do not match!"; exit 1
fi

# -----------------------------------------------------------------------------
HOSTNAME=$(whiptail --clear --title "Arch Linux Installer" \
  --inputbox "Enter desired hostname for this system:" 8 50 ${HOSTNAME} \
  3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

# Check if a host name has been entered.
[ -z "${HOSTNAME}" ] && { clear; msg error "Empty value!"; exit 1; }

CONFIGURATION+="  Hostname = ${HOSTNAME}\n"

# -----------------------------------------------------------------------------
# Retrieve a list with available timezones.
TMPLIST=($(timedatectl list-timezones))

for i in ${TMPLIST[@]}; do
  TIMEZONES+=("${i}" "")
done

TIMEZONE=$(whiptail --clear --title "Arch Linux Installer" \
  --menu "Choose your timezone:" 20 50 12 \
  "${TIMEZONES[@]}" 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

# Check if a timezone has been chosen.
[ -z "${TIMEZONE}" ] && { clear; msg error "Empty value!"; exit 1; }

CONFIGURATION+="  Timezone = ${TIMEZONE}\n"

# -----------------------------------------------------------------------------
# Retrieve a list with available locales.
LOCALES=($(awk '/^#.*UTF-8/ { print $0 }' /etc/locale.gen | \
           tail -n +2 | sed -e 's/^#*//' | sort -u))

LANG=$(whiptail --clear --title "Arch Linux Installer" \
  --menu "Choose your language:" 20 50 12 \
  "${LOCALES[@]}" 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

# Check if a timezone has been chosen.
[ -z "${LANG}" ] && { clear; msg error "Empty value!"; exit 1; }

CONFIGURATION+="  Language = ${LANG}\n"

# -----------------------------------------------------------------------------
# Retrieve a list with available locales.
LOCALES=($(awk '/^#.*UTF-8/ { print $0 " off" }' /etc/locale.gen | \
           tail -n +2 | sed -e 's/^#*//' | sort -u))

LOCALES=($(whiptail --clear --title "Arch Linux Installer" \
  --checklist "Choose your locales:" 20 50 12 \
  "${LOCALES[@]}" 3>&1 1>&2 2>&3 3>&-))

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

# Check if a locale has been chosen.
[ ${#LOCALES[@]} -eq 0 ] && { clear; msg error "Empty value!"; exit 1; }

CONFIGURATION+="  Locales = ${LOCALES[@]}\n"

# -----------------------------------------------------------------------------
# Retrieve a list with available keyboard layouts.
TMPLIST=($(localectl list-keymaps))

for i in ${TMPLIST[@]}; do
  CLIKEYMAPS+=("${i}" "")
done

CLIKEYMAP=$(whiptail --clear --title "Arch Linux Installer" \
  --menu "Choose your TTY keyboard layout:" 20 50 12 \
  "${CLIKEYMAPS[@]}" 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

# Check if a keymap has been chosen.
[ -z "${CLIKEYMAP}" ] && { clear; msg error "Empty value!"; exit 1; }

CONFIGURATION+="  TTY Keyboard layout = ${CLIKEYMAP}"

# -----------------------------------------------------------------------------
# Retrieve a list with available font layouts.
TMPLIST=($(find /usr/share/kbd/consolefonts/ -type f -name "*.psfu.gz" | \
           awk -F'/' '{ print $6 }' | cut -d'.' -f1))

for i in ${TMPLIST[@]}; do
  CLIFONTS+=("${i}" "")
done

CLIFONT=$(whiptail --clear --title "Arch Linux Installer" \
  --menu "Choose your TTY font layout:" 20 50 12 \
  "${CLIFONTS[@]}" 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

# Check if a keymap has been chosen.
[ -z "${CLIFONT}" ] && { clear; msg error "Empty value!"; exit 1; }

CONFIGURATION+="  TTY font layout = ${CLIFONT}"

# -----------------------------------------------------------------------------
MICROCODES=($(whiptail --clear --title "Arch Linux Installer" \
  --checklist "Pick CPU microcodes (press space):" 15 80 \
  $(bc <<< "${#MICROCODES[@]} / 3") "${MICROCODES[@]}" 3>&1 1>&2 2>&3 3>&-))

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

# -----------------------------------------------------------------------------
KERNELPARAMS=($(whiptail --clear --title "Arch Linux Installer" \
  --checklist "Pick kernel boot parameters (press space):" 15 80 \
  $(bc <<< "${#KERNELPARAMS[@]} / 3") "${KERNELPARAMS[@]}" 3>&1 1>&2 2>&3 3>&-))

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

# -----------------------------------------------------------------------------
ENVIRONMENT=$(whiptail --clear --title "Arch Linux Installer" \
  --radiolist "Pick desktop environment (press space):" 15 80 \
  $(bc <<< "${#ENVIRONMENTS[@]} / 3") "${ENVIRONMENTS[@]}" 3>&1 1>&2 2>&3 3>&-)

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

if [[ ${ENVIRONMENT} == "GNOME" || ${ENVIRONMENT} == "KDE" || ${ENVIRONMENT} == "XFCE" ]]; then
  # Enable the default manager based on the chosen environment.
  [[ ${ENVIRONMENT} == "GNOME" ]] && { DISPLAYMANAGERS[2]="on"; }
  [[ ${ENVIRONMENT} == "KDE" ]] && { DISPLAYMANAGERS[5]="on"; }
  [[ ${ENVIRONMENT} == "XFCE" ]] && { DISPLAYMANAGERS[8]="on"; }

  DISPLAYMANAGER=$(whiptail --clear --title "Arch Linux Installer" \
    --radiolist "Pick  display manager (press space):" 15 90 \
    $(bc <<< "${#DISPLAYMANAGERS[@]} / 3") "${DISPLAYMANAGERS[@]}" 3>&1 1>&2 2>&3 3>&-)

  # Check whiptail window return value.
  [[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

  VIDEODRIVERS=($(whiptail --clear --title "Arch Linux Installer" \
    --checklist "Pick video drivers (press space):" 15 90 \
    $(bc <<< "${#VIDEODRIVERS[@]} / 3") "${VIDEODRIVERS[@]}" 3>&1 1>&2 2>&3 3>&-))

  # Check whiptail window return value.
  [[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

  HWVIDEOACCELERATION=($(whiptail --clear --title "Arch Linux Installer" \
    --checklist "Pick hardware video acceleration drivers (press space):" 15 115 \
    $(bc <<< "${#HWVIDEOACCELERATION[@]} / 3") "${HWVIDEOACCELERATION[@]}" 3>&1 1>&2 2>&3 3>&-))

  # Check whiptail window return value.
  [[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }

  EXTRAPKGS=($(whiptail --clear --title "Arch Linux Installer" \
    --checklist "Pick additional packages (press space):" 15 80 \
    $(bc <<< "${#EXTRAPKGS[@]} / 3") "${EXTRAPKGS[@]}" 3>&1 1>&2 2>&3 3>&-))

  # Check whiptail window return value.
  [[ $? == +(1|255) ]] && { clear; msg info "Installation aborted..."; exit 1; }
fi

# -----------------------------------------------------------------------------
# Verify configuration
whiptail --clear --title "Arch Linux Installer" \
  --yesno "Is the below information correct:\n${CONFIGURATION}" 20 70 \
  3>&1 1>&2 2>&3 3>&-

case $? in
  0) clear; msg info "Proceeding....";;
  1|255) clear; msg info "Installation aborted...."; exit 1;;
esac

RUNTIME=$(date +%s)
prepare && installation && cleanup
RUNTIME=$(echo ${RUNTIME} $(date +%s) | awk '{ printf "%0.2f",($2-$1)/60 }')

msg info "Time: ${RUNTIME} minutes"
