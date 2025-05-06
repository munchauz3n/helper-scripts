#!/bin/bash
#
# Enable or Disable bluetooth controler autosuspend and peripherials
# wakeup from suspend udev rules.
#
# Copyright (C) 2025  Petar G. Georgiev <petr.blake@gmail.com>
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
  "awk" "grep" "sed" "lsusb" "whiptail"
)

# Global variables.
declare -a TMPLIST=()

declare CONFIGURATION=""
declare DESCRIPTION=""

declare CMD=""
declare ID=""
declare ENTRY=""

declare VID=""
declare PID=""

declare -i HEIGHT=0
declare -i LISTHEIGHT=0
declare -a FLAGS=()

declare -a CTRLS=()

declare -A ENABLED_POWERSAVE_RULES=()
declare -A DISABLED_POWERSAVE_RULES=()

declare WAKEUP_RULE=""
declare WAKEUP_RULE_STATE="NO CHANGE"

declare POWERSAVE_RULES_FILE="/etc/udev/rules.d/50-usb-power-save.rules"
declare WAKEUP_RULES_FILE="/etc/udev/rules.d/91-bluetooth-wakeup.rules"


# ============================================================================
# Functions
# ============================================================================
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


# =====================================================================================================================
# MAIN
# =====================================================================================================================
if [ "${EUID}" -ne 0 ]; then
  msg error "Script requires root privalages!"
  exit 1
fi

# Checks for dependencies
for CMD in "${DEPENDNECIES[@]}"; do
  if ! [[ -f "/bin/${CMD}" || -f "/sbin/${CMD}" || \
          -f "/usr/bin/${CMD}" || -f "/usr/sbin/${CMD}" ]] ; then
    msg error "'${CMD}' command is missing! Please install the relevant package."
    exit 1
  fi
done

# ---------------------------------------------------------------------------------------------------------------------
# Get vensor and product IDs of the Bluetooth controllers
TMPLIST=($(lsusb -tv | awk 'x{$1=""; print $2 ; x = 0} /Driver=btusb/ {x = 1}' | uniq))

if [[ ${#TMPLIST[@]} -eq 0 ]]; then
  whiptail --title "Bluetooth" --msgbox "No Bluetooth controllers were detected." 8 60 3>&1 1>&2 2>&3 3>&-
  exit 1
fi

# Transform into format suitable for whiptail checklist.
for ID in ${TMPLIST[@]}; do
  DESCRIPTION=$(lsusb | sed -n 's/^.*'${ID}' *//p')

  VID=$(echo ${ID} | sed 's/\"//g' | awk -F: '{print $1}')
  PID=$(echo ${ID} | sed 's/\"//g' | awk -F: '{print $2}')

  ENTRY="ACTION==\"add\", SUBSYSTEM==\"usb\", ATTR{idVendor}==\"${VID}\""
  ENTRY="${ENTRY}, ATTR{idProduct}==\"${PID}\", ATTR{power/autosuspend_delay_ms}=\"-1\""

  if [[ -f ${POWERSAVE_RULES_FILE} ]] && cat ${POWERSAVE_RULES_FILE} | grep -q "${ENTRY}"; then
    CTRLS+=("${ID}" "${DESCRIPTION}" "on")
  else
    CTRLS+=("${ID}" "${DESCRIPTION}" "off")
  fi
done

# Calculate the height based on the number of entries and increase by 8 for window compensation.
HEIGHT=$((${#CTRLS[@]} / 3 + 8))
LISTHEIGHT=$((${#CTRLS[@]} / 3))

FLAGS=(--clear --title "Bluetooth")
FLAGS+=(--checklist "Bluetooth controllers for which to disable autosuspend in udev rules. (press space)")
FLAGS+=(${HEIGHT} 60 ${LISTHEIGHT})

CTRLS=($(whiptail "${FLAGS[@]}" "${CTRLS[@]}" 3>&1 1>&2 2>&3 3>&-))

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { msg info "Script aborted..."; exit 1; }

# Check return IDs and fill the enabled powersave rules.
for ID in ${CTRLS[@]}; do
  VID=$(echo ${ID} | sed 's/\"//g' | awk -F: '{print $1}')
  PID=$(echo ${ID} | sed 's/\"//g' | awk -F: '{print $2}')

  ENTRY="ACTION==\"add\", SUBSYSTEM==\"usb\", ATTR{idVendor}==\"${VID}\""
  ENTRY="${ENTRY}, ATTR{idProduct}==\"${PID}\", ATTR{power/autosuspend_delay_ms}=\"-1\""

  # Skip ifrules file exists and rule is already present in it.
  [[ -f ${POWERSAVE_RULES_FILE} ]] && { cat ${POWERSAVE_RULES_FILE} | grep -q "${ENTRY}" && continue; }

  ENABLED_POWERSAVE_RULES[${ID}]="${ENTRY}"
done

if [[ ${#ENABLED_POWERSAVE_RULES[@]} -ne 0 ]]; then
  CONFIGURATION+="\n  Add rules to ${POWERSAVE_RULES_FILE} :\n"
  CONFIGURATION+="      ${ENABLED_POWERSAVE_RULES[@]}\n"
fi

# Check and fill any leftover entries into the disabled powersave rules.
for ID in ${TMPLIST[@]}; do
  [[ ${CTRLS[@]} =~ ${ID}  ]] && continue

  VID=$(echo ${ID} | sed 's/\"//g' | awk -F: '{print $1}')
  PID=$(echo ${ID} | sed 's/\"//g' | awk -F: '{print $2}')

  ENTRY="ACTION==\"add\", SUBSYSTEM==\"usb\", ATTR{idVendor}==\"${VID}\""
  ENTRY="${ENTRY}, ATTR{idProduct}==\"${PID}\", ATTR{power/autosuspend_delay_ms}=\"-1\""

  DISABLED_POWERSAVE_RULES[${ID}]="${ENTRY}"
done

if [[ ${#DISABLED_POWERSAVE_RULES[@]} -ne 0 ]]; then
  CONFIGURATION+="\n  Remove rules from ${POWERSAVE_RULES_FILE} :\n"
  CONFIGURATION+="      ${DISABLED_POWERSAVE_RULES[@]}\n"
fi

# ---------------------------------------------------------------------------------------------------------------------
# E0 01 01: Bluetooth Programming Interface. Get specific information from www.bluetooth.com.
WAKEUP_RULE="ACTION==\"add\", SUBSYSTEM==\"usb\", DRIVERS==\"usb\", ATTR{bDeviceClass}==\"e0\""
WAKEUP_RULE="${WAKEUP_RULE}, ATTR{bDeviceProtocol}==\"01\", ATTR{bDeviceSubClass}==\"01\""
WAKEUP_RULE="${WAKEUP_RULE}, ATTR{power/wakeup}=\"enabled\""

# Check if the rule exists and display the appropriate action.
if cat ${WAKEUP_RULES_FILE} | grep -q "${WAKEUP_RULE}"; then
  DESCRIPTION="Waking the system from suspend for Bluetooth peripherials is enabled. Disable?"

  whiptail --clear --title "Bluetooth" --yesno "${DESCRIPTION}" 8 60 3>&1 1>&2 2>&3 3>&-

  [[ $? -eq 0 ]] && WAKEUP_RULE_STATE="DISABLE"
else
  DESCRIPTION="Allow Bluetooth keyboards, mice, etc. to wake the system from suspend?"

  whiptail --clear --title "Bluetooth" --yesno "${DESCRIPTION}" 8 60 3>&1 1>&2 2>&3 3>&-

  [[ $? -eq 0 ]] && WAKEUP_RULE_STATE="ENABLE"
fi

if [[ ${WAKEUP_RULE_STATE} == "DISABLE" ]]; then
  CONFIGURATION+="\n  Remove rules from ${WAKEUP_RULES_FILE} :\n"
  CONFIGURATION+="      ${WAKEUP_RULE}\n"
elif [[ ${WAKEUP_RULE_STATE} == "ENABLE" ]]; then
  CONFIGURATION+="\n  Add rules to ${WAKEUP_RULES_FILE} (Make sure that wake from USB is not disabled in BIOS):\n"
  CONFIGURATION+="      ${WAKEUP_RULE}\n"
fi

# ---------------------------------------------------------------------------------------------------------------------
# Exit if there is no configuration.
[[ ${CONFIGURATION} == "" ]] && { msg info "Nothing to configure..."; exit 1; }

CONFIGURATION="Is the information below correct?\n${CONFIGURATION}"

# Verify configuration
whiptail --clear --title "Bluetooth" --yesno "${CONFIGURATION}" 15 180 3>&1 1>&2 2>&3 3>&-

[[ $? == +(1|255) ]] && { msg info "Script aborted..."; exit 1; }

if [[ ${#ENABLED_POWERSAVE_RULES[@]} -ne 0 ]]; then
  # Create the rules file in case it doesn't exist.
  [[ ! -f ${POWERSAVE_RULES_FILE} ]] && touch ${POWERSAVE_RULES_FILE}

  for ID in ${!ENABLED_POWERSAVE_RULES[@]}; do
    echo "${ENABLED_POWERSAVE_RULES[${ID}]}" >> ${POWERSAVE_RULES_FILE};
  done
fi

if [[ ${#DISABLED_POWERSAVE_RULES[@]} -ne 0 ]]; then
  for ID in ${!DISABLED_POWERSAVE_RULES[@]}; do
    ENTRY="${DISABLED_POWERSAVE_RULES[${ID}]////\\/}"
    sed -i "/${ENTRY// /\\ }/d" ${POWERSAVE_RULES_FILE}
  done
fi

if [[ ${WAKEUP_RULE_STATE} == "ENABLE" ]]; then
  # Create the rules file in case it doesn't exist.
  [[ ! -f ${WAKEUP_RULES_FILE} ]] && touch ${WAKEUP_RULES_FILE}

  echo "${WAKEUP_RULE}" >> ${WAKEUP_RULES_FILE};
elif [[ ${WAKEUP_RULE_STATE} == "DISABLE" ]]; then
  WAKEUP_RULE=${WAKEUP_RULE////\\/}
  sed -i "/${WAKEUP_RULE// /\\ }/d" ${WAKEUP_RULES_FILE}
fi
