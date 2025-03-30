#!/bin/bash
#
# Transfer pairing keys from from one OS to the other by guiding the user 
# through the synchronization process via dialog boxes (whiptail), keeping
# devices paired across both systems.
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
  "awk" "grep" "sed" "chntpw" "xxd" "fold" "tac" "tr" "dirname" "whiptail"
)

# Global variables.
declare -a TMPLIST=()

declare TMPDIR="/tmp"
declare WINTMPDIR="${TMPDIR}/c"

declare -a CTRLSETS=("CurrentControlSet" "ControlSet001" "ControlSet002" "ControlSet003")
declare CTRLSET=""

declare WIN_KEYS_REG="${TMPDIR}/bluetooth-keys.reg"
declare WIN_DEVS_REG="${TMPDIR}/bluetooth-devices.reg"

declare WIN_KEYS_REG_BACKUP=""
declare WIN_DEVS_REG_BACKUP=""

declare INFO=""
declare DESCRIPTION=""
declare CMD=""

declare -i HEIGHT=0
declare -i LISTHEIGHT=0
declare -a FLAGS=()

declare -a MOUNTDIRS=()
declare MOUNTDIR=""
declare -a WINSYSPATHS=()
declare WINSYSTEM=""
declare DEVICE=""
declare -a DEVICES=()

declare -a BTCTRLS=()
declare BTCTRL=""

declare -a BTDEVS=()

declare MACADDR=""
declare OTHER_MACADDR=""
declare DEVNAME=""
declare OTHER_DEVNAME=""

declare -a LINUX_DEVS=()
declare -a WINDOWS_DEVS=()
declare -a UNPAIRED_DEVS_ON_LINUX=()
declare -a UNPAIRED_DEVS_ON_WINDOWS=()
declare -A COMPATIBLE_DEVS=()
declare -a SYNCED_DEVS=()
declare -a UNSYNCED_DEVS=()

declare -a WINDOWS_TO_LINUX_DEVS=()
declare -a LINUX_TO_WINDOWS_DEVS=()

declare -a MENUOPTS=()
declare -a SUBMENUOPTS=()
declare CHOICE=""


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

  umount -R ${WINTMPDIR} 1> /dev/null 2>&1
  rm -rf ${WINTMPDIR} 1> /dev/null 2>&1

  rm ${WIN_KEYS_REG} 1> /dev/null 2>&1
  rm ${WIN_DEVS_REG} 1> /dev/null 2>&1

  msg log "Done"
}

function compatible_windows_devices() {
  # First argument is the MAC address of the device on Linux.
  local macaddr=$1

  # Local variables.
  local infopath
  local winaddr

  local win_vid
  local win_pid

  local lin_vid
  local lin_pid

  local -a devices

  infopath="$(find /var/lib/bluetooth/ -name ${macaddr} -type d)/info"

  # Extract the device VendorID and ProductID for later comparison.
  lin_vid=$(cat ${infopath} | awk -F'=' '/^Vendor=/ {print "obase=16; "$2}' | bc)
  lin_pid=$(cat ${infopath} | awk -F'=' '/^Product=/ {print "obase=16; "$2}' | bc)

  # If device does not have VID and PID then nothing further can be done at this point.
  [[ -z "${lin_vid}" || -z "${lin_pid}" ]] && return

  # Try to find a potential matches among the other Windows devices.
  for winaddr in ${UNPAIRED_DEVS_ON_LINUX[@]}; do
    # Compare the VendorID and ProductID of the devices.
    win_vid="$(cat -e ${WIN_DEVS_REG} \
      | sed 's/\^M\$//g' \
      | sed -n '/^\[.*'${winaddr//:/}'\]$/I,/^$/p' \
      | awk -F':' '/^"VID"=dword:/ {print toupper($2)}' \
      | sed 's/^0*//')"

    win_pid="$(cat -e ${WIN_DEVS_REG} \
      | sed 's/\^M\$//g' \
      | sed -n '/^\[.*'${winaddr//:/}'\]$/I,/^$/p' \
      | awk -F':' '/^"PID"=dword:/ {print toupper($2)}' \
      | sed 's/^0*//')"

    # Device doesn't have VID and PID, skip it.
    [[ -z "${win_vid}" || -z "${win_pid}" ]] && continue
    # Different VID and/or PID, skip device.
    [[ "${lin_vid}" != "${win_vid}" || "${lin_pid}" != "${win_pid}" ]] && continue

    devices+=(${winaddr})
  done

  echo "${devices[@]}"
}

function compatible_linux_devices() {
  # First argument is the MAC address of the device on Windows.
  local macaddr=$1

  # Local variables.
  local linaddr
  local infopath

  local win_vid
  local win_pid

  local lin_vid
  local lin_pid

  local -a devices

  # Extract the device VendorID and ProductID for later comparison.
  win_vid="$(cat -e ${WIN_DEVS_REG} \
    | sed 's/\^M\$//g' \
    | sed -n '/^\[.*'${macaddr//:/}'\]$/I,/^$/p' \
    | awk -F':' '/^"VID"=dword:/ {print toupper($2)}' \
    | sed 's/^0*//')"
  win_pid="$(cat -e ${WIN_DEVS_REG} \
    | sed 's/\^M\$//g' \
    | sed -n '/^\[.*'${macaddr//:/}'\]$/I,/^$/p' \
    | awk -F':' '/^"PID"=dword:/ {print toupper($2)}' \
    | sed 's/^0*//')"

  # If device does not have VID and PID then nothing further can be done at this point.
  [[ -z "${win_vid}" || -z "${win_pid}" ]] && return

  for linaddr in ${UNPAIRED_DEVS_ON_WINDOWS[@]}; do
    infopath="$(find /var/lib/bluetooth/ -name ${linaddr} -type d)/info"

    # Compare the VendorID and ProductID of the devices.
    lin_vid=$(cat ${infopath} | awk -F'=' '/^Vendor=/ {print "obase=16; "$2}' | bc)
    lin_pid=$(cat ${infopath} | awk -F'=' '/^Product=/ {print "obase=16; "$2}' | bc)

    # Device doesn't have VID and PID, skip it.
    [[ -z "${lin_vid}" || -z "${lin_pid}" ]] && continue
    # Different VID and/or PID, skip device.
    [[ "${win_vid}" != "${lin_vid}" || "${win_pid}" != "${lin_pid}" ]] && continue

    devices+=(${linaddr})
  done

  echo "${devices[@]}"
}

function windows_device_name() {
  # First argument is the device MAC address on Windows or combined adresses on Windows and Linux.
  local macaddr=$1

  # Local variables.
  local devname

  # Check if there are 2 MAC addresses. First for Windows and second for Linux.
  # This is due to the device having random static address type that is generated at each pairing.
  macaddr=$(echo ${macaddr} \
    | awk -F'|' '/^[[:xdigit:]:]{17}$/ {print $0} /^[[:xdigit:]:]{17}\|[[:xdigit:]:]{17}$/ {print $1}')

  # Extract the name in hex from the windows devices registry and convert them to characters.
  devname="$(cat -e ${WIN_DEVS_REG} \
    | sed 's/\^M\$//g' \
    | sed -n '/^\[.*'${macaddr//:/}'\]$/I,/^$/p' \
    | awk -F':' '/^"Name"=hex/ {if (sub(/\\/,"")) {printf $2; getline; print $0; exit} else {print $2; exit}}' \
    | sed 's/[, ]//g' \
    | xxd -r -p \
    | tr '\0' '\n')"

  echo "${devname}"
}

function linux_device_name() {
  # First argument is the device MAC address on Linux or combined adresses on Windows and Linux.
  local macaddr=$1

  # Local variables.
  local infopath
  local devname

  # Check if there are 2 MAC addresses. First for Windows and second for Linux.
  # This is due to the device having random static address type that is generated at each pairing.
  macaddr=$(echo ${macaddr} \
    | awk -F'|' '/^[[:xdigit:]:]{17}$/ {print $0} /^[[:xdigit:]:]{17}\|[[:xdigit:]:]{17}$/ {print $2}')

  infopath="$(find /var/lib/bluetooth/ -name ${macaddr} -type d)/info"
  devname=$(cat ${infopath} | awk -F'=' '/Name=/ {print $2}')

  echo "${devname}"
}

function windows_keys() {
  # First argument is the device MAC address on Windows or combined adresses on Windows and Linux.
  local macaddr=$1

  # Local variables.
  local info

  # Check if there are 2 MAC addresses. First for Windows and second for Linux.
  # This is due to the device having random static address type that is generated at each pairing.
  macaddr=$(echo ${macaddr} \
    | awk -F'|' '/^[[:xdigit:]:]{17}$/ {print $0} /^[[:xdigit:]:]{17}\|[[:xdigit:]:]{17}$/ {print $1}')

  # Pattern for the keys on regular Bluetooth devices.
  info="$(cat -e ${WIN_KEYS_REG} \
    | sed 's/\^M\$//g' \
    | grep -i "\"${macaddr//:/}\"=hex:" \
    | awk -F':' '{print "Key=hex:"toupper($2)}' \
    | sed 's/,//g')"

  # Pattern for the keys on Bluetooth LE devices.
  info+="$(cat -e ${WIN_KEYS_REG} \
    | sed 's/\^M\$//g' \
    | sed -n '/^\[.*'${macaddr//:/}'\]$/I,/^$/p' \
    | grep -E "\"EDIV\"=|\"ERand\"=|\"IRK\"=|\"KeyLength\"=|\"LTK\"=" \
    | sed 's/\(\"\|,\)//g' \
    | awk -F':' '{print $1":"toupper($2)}')"

  echo "${info}"
}

function linux_keys() {
  # First argument is the device MAC address on Windows or combined adresses on Windows and Linux.
  local macaddr=$1

  # Local variables.
  local info

  # Check if there are 2 MAC addresses. First for Windows and second for Linux.
  # This is due to the device having random static address type that is generated at each pairing.
  macaddr=$(echo ${macaddr} \
    | awk -F'|' '/^[[:xdigit:]:]{17}$/ {print $0} /^[[:xdigit:]:]{17}\|[[:xdigit:]:]{17}$/ {print $2}')

  info="$(cat $(find /var/lib/bluetooth/ -name ${macaddr} -type d)/info \
    | sed -n '/^\[\(LinkKey\|IdentityResolvingKey\|LongTermKey\|PeripheralLongTermKey\|SlaveLongTermKey\)\]$/,/^$/p')"

  echo "${info}"
}

function is_synced() {
  # First argument is the device MAC address(es) and Windows and Linux.
  local macaddr=$1

  # Local variables.
  local windows_mac_address
  local linux_mac_address

  local wininfo
  local lininfo

  local winkey
  local linkey

  local winirk
  local winrand
  local winediv
  local winkeylen
  local winltk

  local linirk
  local linediv
  local linrand
  local linltk
  local linkeylen

  wininfo="$(windows_keys "${macaddr}")"
  lininfo="$(linux_keys "${macaddr}")"

  # Check and compare keys if device is regular Bluettoh device (only keys are available).
  winkey="$(echo "${wininfo}" | awk -F':' '/Key=/ {print $2}')"
  linkey="$(echo "${lininfo}" | sed -n '/^\[LinkKey\]$/,/^$/p' | awk -F'=' '/Key=/ {print $2}')"

  if [[ ! -z "${winkey}" && ! -z  ${linkey} ]]; then
    [[ ${winkey} == ${linkey} ]] && return 0 || return 1
  fi

  # IRK is hex value. Needs to be reversed.
  winirk="$(echo "${wininfo}" | awk -F':' '/IRK=/ {print $2}' | fold -w2 | tac | tr -d '\n')"
  # ERand is hex value. Needs to be reversed.
  winrand="$(echo "${wininfo}" | awk -F':' '/ERand=/ {print $2}' | fold -w2 | tac | tr -d '\n')"
  # EDIV is hex value. Leading zeroes must be trimmed.
  winediv="$(echo "${wininfo}" | awk -F':' '/EDIV=/ {print $2}' | sed 's/^0*//')"
  # KeyLength is hex value. Leading zeroes must be trimmed.
  winkeylen="$(echo "${wininfo}" | awk -F':' '/KeyLength=/ {print $2}' | sed 's/^0*//')"
  # KeyLength is hex value. No additional steps are required.
  winltk="$(echo "${wininfo}" | grep -E "LTK=" | awk -F':' '{print $2}')"

  # IRK is hex value. No additional steps are required.
  linirk="$(echo "${lininfo}" \
    | sed -n '/^\[IdentityResolvingKey\]$/,/^$/p' \
    | awk -F'=' '/Key=/ {print $2}')"
  # EDiv is decimal value. Needs to be converted to hex.
  linediv="$(echo "${lininfo}" \
    | sed -n '/^\[LongTermKey\]$/,/^$/p' \
    | awk -F'=' '/EDiv=/ {print "obase=16; "$2}' \
    | bc)"
  # Rand is decimal value. Needs to be converted to hex.
  linrand="$(echo "${lininfo}" \
    | sed -n '/^\[LongTermKey\]$/,/^$/p' \
    | awk -F'=' '/Rand=/ {print "obase=16; "$2}' \
    | bc)"
  # EncSize is decimal value. Needs to be converted to hex.
  linkeylen="$(echo "${lininfo}" \
    | sed -n '/^\[LongTermKey\]$/,/^$/p'\
    | awk -F'=' '/EncSize=/ {print "obase=16; "$2}' \
    | bc)"
  # LTK is hex value. No additional steps are required.
  linltk="$(echo "${lininfo}" | sed -n '/^\[LongTermKey\]$/,/^$/p' | awk -F'=' '/Key=/ {print $2}')"

  if [[ ${winirk} == ${linirk} && ${winediv} == ${linediv} && ${winrand} == ${linrand} && \
        ${winltk} == ${linltk} && ${winkeylen} == ${linkeylen} ]]; then
    return 0
  fi

  return 1
}

function sync_linux_to_windows_keys() {
  # First argument is the device MAC address(es) and Windows and Linux.
  local macaddr=${1,,}

  # Local variables.
  local winaddr
  local linaddr

  local lininfo

  local key
  local irk
  local rand
  local keylen
  local ediv
  local ltk

  # Check if there are 2 MAC addresses. First for Windows and second for Linux.
  # This is due to the device having random static address type that is generated at each pairing.
  winaddr=$(echo ${macaddr} \
    | awk -F'|' '/^[[:xdigit:]:]{17}$/ {print $0} /^[[:xdigit:]:]{17}\|[[:xdigit:]:]{17}$/ {print $1}')
  linaddr=$(echo ${macaddr} \
    | awk -F'|' '/^[[:xdigit:]:]{17}$/ {print $0} /^[[:xdigit:]:]{17}\|[[:xdigit:]:]{17}$/ {print $2}')

  if [[ "${winaddr}" != "${linaddr}" ]]; then
    msg log "Different MAC address on Linux, renaming bluetooth device in Windows registries..."

    sed -i "s/${winaddr//:/}/${linaddr//:/}/g" "${WIN_DEVS_REG}" 1> /dev/null 2>&1
    [[ $? == +(1|255) ]] && { msg error "Failed to rename MAC in device registry!"; return 1; }

    local win_hexb_address
    local lin_hexb_address

    win_hexb_address=$(echo ${winaddr//:/} | awk '{printf("%16s", $0)}' | sed 's/ /0/g')
    win_hexb_address=$(echo ${win_hexb_address} | fold -w2 | tac | tr -d '\n' | sed 's/../,&/2g')

    lin_hexb_address=$(echo ${linaddr//:/} | awk '{printf("%16s", $0)}' | sed 's/ /0/g')
    lin_hexb_address=$(echo ${lin_hexb_address} | fold -w2 | tac | tr -d '\n' | sed 's/../,&/2g')

    sed -i "s/${win_hexb_address}/${lin_hexb_address}/g" "${WIN_KEYS_REG}" 1> /dev/null 2>&1
    [[ $? == +(1|255) ]] && { msg error "Failed to rename address in keys registry!"; return 1; }

    sed -i "s/${winaddr//:/}/${linaddr//:/}/g" "${WIN_KEYS_REG}" 1> /dev/null 2>&1
    [[ $? == +(1|255) ]] && { msg error "Failed to rename MAC in keys registry!"; return 1; }

    msg log "Device in Windows registries renamed from '${winaddr//:/}' to '${linaddr//:/}'"
    macaddr="${linaddr}"
  fi

  lininfo="$(linux_keys "${macaddr^^}")"

  # For non-LE Bluetooth device transfer only key as this only value available.
  key="$(echo "${lininfo}" \
    | sed -n '/^\[LinkKey\]$/,/^$/p' \
    | awk -F'=' '/Key=/ {print $2}' \
    | sed 's/../,&/2g')"

  if [[ ! -z "${key}" ]]; then
    sed -i "s/\"${macaddr//:/}\"=hex:.*/\"${macaddr//:/}\"=hex:${key,,}\r/g" \
           "${WIN_KEYS_REG}" 1> /dev/null 2>&1

    [[ $? == +(1|255) ]] && { msg error "Failed to synchronize key!"; return 1; }
    msg log "Synchronized key '${key,,}'."
  fi

  # IRK is hex value. Neess to be reversed and separated with commmas.
  irk="$(echo "${lininfo}" \
    | sed -n '/^\[IdentityResolvingKey\]$/,/^$/p' \
    | awk -F'=' '/Key=/ {print $2}' \
    | fold -w2 \
    | tac \
    | tr -d '\n' \
    | sed 's/../,&/2g')"
  # ERand is decimal value. Needs to be converted to hex, reversed and separated with commmas.
  rand="$(echo "${lininfo}" \
    | sed -n '/^\[LongTermKey\]$/,/^$/p' \
    | awk -F'=' '/Rand=/ {print "obase=16; "$2}' \
    | bc \
    | fold -w2 \
    | tac \
    | tr -d '\n' \
    | sed 's/../,&/2g')"
  # EDiv and EncSize are decimal values. Needs to be converted to hex and leading zeroes added.
  ediv="$(echo "${lininfo}" \
    | sed -n '/^\[LongTermKey\]$/,/^$/p' \
    | awk -F'=' '/EDiv=/ {print "obase=16; "$2}' \
    | bc \
    | awk '{printf("%08s", $0)}' \
    | sed 's/ /0/g')"
  keylen="$(echo "${lininfo}" \
    | sed -n '/^\[LongTermKey\]$/,/^$/p' \
    | awk -F'=' '/EncSize=/ {print "obase=16; "$2}' \
    | bc \
    | awk '{printf("%08s", $0)}' \
    | sed 's/ /0/g')"
  # Needs to be separated with commmas.
  ltk="$(echo "${lininfo}" \
    | sed -n '/^\[LongTermKey\]$/,/^$/p' \
    | awk -F'=' '/Key=/ {print $2}' \
    | sed 's/../,&/2g')"

  if [[ ! -z "${irk}" ]]; then
    sed -i "/^\[.*${macaddr//:/}\]\r$/,/^\r$/{ s/\"IRK\"=.*/\"IRK\"=hex:${irk,,}\r/g }" \
           "${WIN_KEYS_REG}" 1> /dev/null 2>&1

    [[ $? == +(1|255) ]] && { msg error "Failed to synchronize IRK!"; return 1; }
    msg log "Synchronized IRK '${irk,,}'."
  fi

  if [[ ! -z "${ediv}" ]]; then
    sed -i "/^\[.*${macaddr//:/}\]\r$/,/^\r$/{ s/\"EDIV\"=.*/\"EDIV\"=dword:${ediv,,}\r/g }" \
           "${WIN_KEYS_REG}" 1> /dev/null 2>&1

    [[ $? == +(1|255) ]] && { msg error "Failed to synchronize EDIV!"; return 1; }
    msg log "Synchronized EDIV '${ediv,,}'."
  fi

  if [[ ! -z "${rand}" ]]; then
    sed -i "/^\[.*${macaddr//:/}\]\r$/,/^\r$/{ s/\"ERand\"=.*/\"ERand\"=hex(b):${rand,,}\r/g }" \
           "${WIN_KEYS_REG}" 1> /dev/null 2>&1

    [[ $? == +(1|255) ]] && { msg error "Failed to synchronize ERand!"; return 1; }
    msg log "Synchronized ERand '${rand,,}'."
  fi

  if [[ ! -z "${ltk}" ]]; then
    sed -i "/^\[.*${macaddr//:/}\]\r$/,/^\r$/{ s/\"LTK\"=.*/\"LTK\"=hex:${ltk,,}\r/g }" \
           "${WIN_KEYS_REG}" 1> /dev/null 2>&1

    [[ $? == +(1|255) ]] && { msg error "Failed to synchronize LTK!"; return 1; }
    msg log "Synchronized LTK '${ltk,,}'."
  fi

  if [[ ! -z "${keylen}" ]]; then
    sed -i "/^\[.*${macaddr//:/}\]\r$/,/^\r$/{ s/\"KeyLength\"=.*/\"KeyLength\"=dword:${keylen,,}\r/g }" \
           "${WIN_KEYS_REG}" 1> /dev/null 2>&1

    [[ $? == +(1|255) ]] && { msg error "Failed to synchronize KeyLength!"; return 1; }
    msg log "Synchronized KeyLength '${keylen,,}'."
  fi

  return 0
}

function sync_windows_to_linux_keys() {
  # First argument is the device MAC address(es) and Windows and Linux.
  local macaddr=$1

  # Local variables.
  local winaddr
  local linaddr

  local wininfo
  local btdir
  local infopath

  local key
  local irk
  local rand
  local keylen
  local ediv
  local ltk

  # Check if there are 2 MAC addresses. First for Windows and second for Linux.
  # This is due to the device having random static address type that is generated at each pairing.
  winaddr=$(echo ${macaddr} \
    | awk -F'|' '/^[[:xdigit:]:]{17}$/ {print $0} /^[[:xdigit:]:]{17}\|[[:xdigit:]:]{17}$/ {print $1}')
  linaddr=$(echo ${macaddr} \
    | awk -F'|' '/^[[:xdigit:]:]{17}$/ {print $0} /^[[:xdigit:]:]{17}\|[[:xdigit:]:]{17}$/ {print $2}')

  btdir="$(find /var/lib/bluetooth/ -name ${linaddr} -type d -exec dirname {} \;)"

  if [[ "${winaddr}" != "${linaddr}" ]]; then
    msg log "Different MAC address on Windows, moving bluetooth device directory..."

    mv "${btdir}/${linaddr}" "${btdir}/${winaddr}" 1> /dev/null 2>&1
    [[ $? == +(1|255) ]] && { msg error "Failed to move '${linaddr}' to '${winaddr}'!"; return 1; }

    msg log "Moved bluetooth device directory from '${btdir}/${linaddr}' to '${btdir}/${winaddr}'."
    linaddr="${winaddr}"
  fi

  infopath="${btdir}/${linaddr}/info"
  wininfo="$(windows_keys "${winaddr}")"

  # For non-LE Bluetooth device transfer only key as this only value available.
  key="$(echo "${wininfo}" | awk -F':' '/Key=/ {print $2}')"

  if [[ ! -z "${key}" ]]; then
    sed -i "/\[LinkKey\]$/,/^$/{ s/Key=.*/Key=${key}/g }" "${infopath}" 1> /dev/null 2>&1

    [[ $? == +(1|255) ]] && { msg error "Failed to synchronize LinkKey!"; return 1; }
    msg log "Synchronized LinkKey '${key}'."
  fi

  # IRK is hex value. Needs to be reversed.
  irk="$(echo "${wininfo}" | awk -F':' '/IRK=/ {print $2}' | fold -w2 | tac | tr -d '\n')"
  # ERand is hex value. Needs to be reversed and converted to decimal.
  rand="$(echo "${wininfo}" \
    | awk -F':' '/ERand=/ {print $2}' \
    | fold -w2 \
    | tac \
    | tr -d '\n' \
    | awk '{print "ibase=16; "$0}'\
    | bc)"
  # KeyLength is hex value. Leading zeroes must be trimmed and value converted to decimal.
  keylen="$(echo "${wininfo}" \
    | awk -F':' '/KeyLength=/ {print "ibase=16; "$2}' \
    | sed 's/^0*//' \
    | bc)"
  # EDIV is hex value. Leading zeroes must be trimmed and value converted to decimal.
  ediv="$(echo "${wininfo}" | awk -F':' '/EDIV=/ {print "ibase=16; "$2}' | sed 's/^0*//' | bc)"
  # LTK is hex value. No additional steps are required.
  ltk="$(echo "${wininfo}" | awk -F':' '/LTK=/ {print $2}')"

  if [[ ! -z "${irk}" ]]; then
    sed -i "/\[IdentityResolvingKey\]$/,/^$/{ s/Key=.*/Key=${irk}/g }" "${infopath}" 1> /dev/null 2>&1

    [[ $? == +(1|255) ]] && { msg error "Failed to synchronize IdentityResolvingKey Key!"; return 1; }
    msg log "Synchronized IdentityResolvingKey Key '${irk}'."
  fi

  if [[ ! -z "${ediv}" ]]; then
    sed -i "/\[LongTermKey\]$/,/^$/{ s/EDiv=.*/EDiv=${ediv}/g }" "${infopath}" 1> /dev/null 2>&1

    [[ $? == +(1|255) ]] && { msg error "Failed to synchronize LongTermKey EDiv!"; return 1; }
    msg log "Synchronized LongTermKey EDiv '${ediv}'."
  fi

  if [[ ! -z "${rand}" ]]; then
    sed -i "/\[LongTermKey\]$/,/^$/{ s/Rand=.*/Rand=${rand}/g }" "${infopath}" 1> /dev/null 2>&1

    [[ $? == +(1|255) ]] && { msg error "Failed to synchronize LongTermKey Rand!"; return 1; }
    msg log "Synchronized LongTermKey Rand '${rand}'."
  fi

  if [[ ! -z "${ltk}" ]]; then
    sed -i "/\[LongTermKey\]$/,/^$/{ s/Key=.*/Key=${ltk}/g }" "${infopath}" 1> /dev/null 2>&1

    [[ $? == +(1|255) ]] && { msg error "Failed to synchronize LongTermKey Key!"; return 1; }
    msg log "Synchronized LongTermKey Key '${ltk}'."
  fi

  if [[ ! -z "${keylen}" ]]; then
    sed -i "/\[LongTermKey\]$/,/^$/{ s/EncSize=.*/EncSize=${keylen}/g }" "${infopath}" 1> /dev/null 2>&1

    [[ $? == +(1|255) ]] && { msg error "Failed to synchronize LongTermKey EncSize!"; return 1; }
    msg log "Synchronized LongTermKey EncSize '${keylen}'."
  fi

  return 0
}

function synckeys() {
  local macaddr
  local devname

  for macaddr in ${LINUX_TO_WINDOWS_DEVS[@]}; do
    devname=$(linux_device_name "${macaddr}")
    
    msg info "Synchronizing keys for device '${macaddr} ${devname}' in direction: Linux To Windows"
    sync_linux_to_windows_keys "${macaddr}" || return 1
  done

  for macaddr in ${WINDOWS_TO_LINUX_DEVS[@]}; do
    devname=$(windows_device_name "${macaddr}")

    msg info "Synchronizing keys for device '${macaddr} ${devname}' in direction: Windows To Linux"
    sync_windows_to_linux_keys "${macaddr}" || return 1
  done

  if [[ ${#LINUX_TO_WINDOWS_DEVS[@]} -ne 0 ]]; then
    msg log "Importing the modified bluetooth windows registry..."

    reged -IC "${WINSYSTEM}" "HKEY_LOCAL_MACHINE\SYSTEM" "${WIN_KEYS_REG}"
    [[ $? == +(1|255) ]] && { msg error "Failed to import keys registry!"; cleanup; return 1; }

    reged -IC "${WINSYSTEM}" "HKEY_LOCAL_MACHINE\SYSTEM" "${WIN_DEVS_REG}"
    [[ $? == +(1|255) ]] && { msg error "Failed to import devices registry!"; cleanup; return 1; }
  elif [[ ${#WINDOWS_TO_LINUX_DEVS[@]} -ne 0 ]]; then
    msg log "Restart bluetooth service..."

    systemctl restart bluetooth
    [[ $? == +(1|255) ]] && { msg error "Failed to restart bluetooth service!"; cleanup; return 1; }

    msg log "Depending on Bluetooth manager, a full reboot may be required in order to reconnect to the device."
  fi

  msg log "Done!"
  return 0
}


# =================================================================================================
# MAIN
# =================================================================================================
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

# -------------------------------------------------------------------------------------------------
# Find the directory where windows is mounted.
MOUNTDIRS=($(lsblk -n -o KNAME,PARTTYPENAME,MOUNTPOINT \
  | awk '/Microsoft basic data/ && ($5 != "") {print $5}'))

for MOUNTDIR in ${MOUNTDIRS[@]}; do
  [[ ! -f "${MOUNTDIR}/Windows/System32/config/SYSTEM" ]] && continue

  WINSYSTEM="${MOUNTDIR}/Windows/System32/config/SYSTEM"
  WINSYSPATHS+=("${WINSYSTEM}" "$(lsblk -n -o KNAME,MOUNTPOINT | grep ${MOUNTDIR} | awk '{print $1}')")
done

if [[ ${#WINSYSPATHS[@]} > 2 ]]; then
  FLAGS=(--clear --title "Bluetooth" --menu "Pick windows partition. (press space)" 12 80 4)

  # Found multiple mounted windows partitions with SYSTEM. Decide on which one to use.
  WINSYSTEM=$(whiptail "${FLAGS[@]}" "${WINSYSPATHS[@]}" 3>&1 1>&2 2>&3 3>&-)

  # Check whiptail window return value.
  [[ $? == +(1|255) ]] && { msg info "Script aborted..."; exit 1; }
elif [[ ${#WINSYSPATHS[@]} -eq 0 ]]; then
  # Couldn't find windows partition. Probably not mounted.
  TMPLIST=($(lsblk -n -o KNAME,PARTTYPENAME,MOUNTPOINT \
    | awk '/Microsoft basic data/ && ($5 == "") {print $1}'))

  for DEVICE in ${TMPLIST[@]}; do
    DEVICES+=("${DEVICE}" "$(lsblk /dev/${DEVICE} -n -o FSTYPE,SIZE)" "off")
  done

  HEIGHT=$((${#WINSYSPATHS[@]} / 3 + 8))
  LISTHEIGHT=$((${#WINSYSPATHS[@]} / 3))

  FLAGS=(--clear --title "Bluetooth")
  FLAGS+=(--radiolist "Pick the windows device. (press space)" ${HEIGHT} 40 ${LISTHEIGHT})

  DEVICE=$(whiptail "${FLAGS[@]}" "${DEVICES[@]}" 3>&1 1>&2 2>&3 3>&-)

  # Check whiptail window return value.
  [[ $? == +(1|255) ]] && { msg info "Script aborted..."; exit 1; }
  # Check whether a device was picked.
  [[ -z "${DEVICE}" ]] && { msg error "No device was picked. Script aborted..."; exit 1; }

  # Mount the device.
  msg info "Mount windows partition at '${WINTMPDIR}'..."
  mkdir ${WINTMPDIR} 1> /dev/null 2>&1
  mount /dev/${DEVICE} ${WINTMPDIR} 1> /dev/null 2>&1

  # Check mount return value.
  [[ $? == +(1|255) ]] && { msg error "Failed to mount windows partition!"; exit 1; }

  # Check if there is SYSTEM in the mounted directory.
  WINSYSTEM="$(find "${WINTMPDIR}/Windows/System32/config/" -iname 'SYSTEM' -type f)"
fi

# Check whether a windows SYSTEM partition was picked/found.
[[ -z "${WINSYSTEM}" ]] && { msg error "No windows partition was picked/found!"; cleanup; exit 1; }

msg info "Using windows system path: '${WINSYSTEM}'"

# -------------------------------------------------------------------------------------------------
# Check which sontrol set is used by the windows system and export the windows bluetooth registries.
for CTRLSET in ${CTRLSETS[@]}; do
  INFO=$(reged -x "${WINSYSTEM}" "HKEY_LOCAL_MACHINE\SYSTEM" \
                  "\\${CTRLSET}\\Services\BTHPORT\Parameters\Keys" "${WIN_KEYS_REG}")

  # Check whether bluetooth keys registry with this control set was found.
  echo "${INFO}" | grep -q "not found!" && { rm ${WIN_KEYS_REG}; continue; }

  INFO=$(reged -x "${WINSYSTEM}" "HKEY_LOCAL_MACHINE\SYSTEM" \
                  "\\${CTRLSET}\\Services\BTHPORT\Parameters\Devices" ${WIN_DEVS_REG})

  # Check whether bluetooth devices registry with this control set was found.
  echo "${INFO}" | grep -q "not found!" && { rm ${WIN_DEVS_REG}; rm ${WIN_KEYS_REG}; } || { break; }
done

[[ ! -f "${WIN_KEYS_REG}" ]] && { msg error "Failed to find windows registry!"; cleanup; exit 1; }

msg log "Windows bluetooth keys registry exported: '${WIN_KEYS_REG}'"
msg log "Windows bluetooth devices registry exported: '${WIN_DEVS_REG}'"

# Create a backup copy of the keys and devices registries in case something goes wrong.
WIN_KEYS_REG_BACKUP="${TMPDIR}/bluetooth-keys-$(date +"%d-%m-%Y-%H-%M-%S").reg.backup"
WIN_DEVS_REG_BACKUP="${TMPDIR}/bluetooth-devices-$(date +"%d-%m-%Y-%H-%M-%S").reg.backup"

cp --preserve "${WIN_KEYS_REG}" "${WIN_KEYS_REG_BACKUP}" 1> /dev/null 2>&1
msg log "Windows bluetooth keys registry backup: '${WIN_KEYS_REG_BACKUP}'"

cp --preserve "${WIN_DEVS_REG}" "${WIN_DEVS_REG_BACKUP}" 1> /dev/null 2>&1
msg log "Windows bluetooth devices registry backup: '${WIN_DEVS_REG_BACKUP}'"

# -------------------------------------------------------------------------------------------------
# Find bluetooth controllers and paired devices.
BTCTRLS=($(ls "/var/lib/bluetooth/" | grep -Eo "[[:xdigit:]:]{11,17}"))

[[ ${#BTCTRLS[@]} -eq 0 ]] && { msg error "Failed to find linux bluetooth controllers!"; cleanup; exit 1; }

# Check if the found bluetooth controllers are also present in the Windows bluetooth registry.
for BTCTRL in ${BTCTRLS[@]}; do
  if ! cat -v "${WIN_KEYS_REG}" | sed 's/\^M\$//g' | grep -iq "${BTCTRL//:/}"; then
    msg warning "Linux Bluetooth controller '${BTCTRL}' is not present in windows registry."
  else
    msg info "Linux Bluetooth controller '${BTCTRL}' is also present in the Windows registry."

    # Get the paired devices from the windows registry and convert their MAC address to Linux format.
    WINDOWS_DEVS+=($(cat -e ${WIN_KEYS_REG} \
      | sed 's/\^M\$//g' \
      | sed -n "/^\[.*${BTCTRL//:/}\]$/I,/^$/p" \
      | awk -F'=' '/^"[[:xdigit:]]{12}"=hex:/ {print toupper($1)}' \
      | sed 's/"//g; s/../:&/2g'))

    WINDOWS_DEVS+=($(cat -e ${WIN_KEYS_REG} \
      | sed 's/\^M\$//g' \
      | grep -Ei "^\[.*${BTCTRL//:/}\\\[[:xdigit:]]{12}\]$" \
      | awk -F'\' '{print toupper($9)}' \
      | sed 's/\]//g; s/../:&/2g'))

    # Get the paired devices from the var directory of the linux bluetooth controller. 
    LINUX_DEVS+=($(ls "/var/lib/bluetooth/${BTCTRL}" | grep -Eo "[[:xdigit:]:]{11,17}"))
  fi
done

# Merge the linux and windows paired devices into single array and remove duplicates.
BTDEVS=($(printf '%s\n' "${LINUX_DEVS[@]}" "${WINDOWS_DEVS[@]}" | sort -u))

[[ ${#BTDEVS[@]} -eq 0 ]] && { msg error "Failed to find paired bluetooth devices!"; cleanup; exit 1; }

# Separate bluetooth devices into synced or unsynced groups and unpaired groups for Linux and Windows.
for MACADDR in ${BTDEVS[@]}; do
  # Drect MAC address match is possible only if device is paired on both platforms and the device
  # is not generating new MAC address at each pairing due to having random static address type.
  if [[ "${LINUX_DEVS[*]}" =~ ${MACADDR} && "${WINDOWS_DEVS[*]}" =~ ${MACADDR} ]]; then
    # Device is paired on Linux and Windows with same MAC address. Check if keys are also synced.
    is_synced ${MACADDR} && SYNCED_DEVS+=(${MACADDR}) || UNSYNCED_DEVS+=(${MACADDR})
  fi

  [[ ! "${LINUX_DEVS[*]}" =~ ${MACADDR} ]] && UNPAIRED_DEVS_ON_LINUX+=(${MACADDR})
  [[ ! "${WINDOWS_DEVS[*]}" =~ ${MACADDR} ]] && UNPAIRED_DEVS_ON_WINDOWS+=(${MACADDR})
done

# Search among the devices marked as unpaired for yet compatible devices but with different MACs.
for MACADDR in ${UNPAIRED_DEVS_ON_LINUX[@]}; do
  COMPATIBLE_DEVS[${MACADDR}]="$(compatible_linux_devices ${MACADDR})"
done

for MACADDR in ${UNPAIRED_DEVS_ON_WINDOWS[@]}; do
  COMPATIBLE_DEVS[${MACADDR}]="$(compatible_windows_devices ${MACADDR})"
done

# -------------------------------------------------------------------------------------------------
# Handle devices which are probaly generating different MAC address at each pairing.
# Some devices with Random Static address type generate new MAC at each pairing and some don't.
unset MENUOPTS

for MACADDR in "${!COMPATIBLE_DEVS[@]}"; do
  [[ -z "${COMPATIBLE_DEVS[${MACADDR}]}" ]] && continue

  [[ "${LINUX_DEVS[*]}" =~ ${MACADDR} ]] && DEVNAME="[Linux]   $(linux_device_name ${MACADDR})"
  [[ "${WINDOWS_DEVS[*]}" =~ ${MACADDR} ]] && DEVNAME="[Windows] $(windows_device_name ${MACADDR})"

  MENUOPTS+=("${MACADDR}" "${DEVNAME}")
done

MENUOPTS+=("<Continue>" "Continue with the setup...")

while [[ ${#MENUOPTS[@]} -gt 2 ]]; do
  DESCRIPTION="Devices which do not have exact MAC address match on the opposing platform, but do "
  DESCRIPTION+="have the same VendorID and ProductID as some of the devices on that platform.\n\n"
  DESCRIPTION+="Select device in order to setup which is going to be the corresponding device on "
  DESCRIPTION+="the opposing platform."

  FLAGS=(--clear --title "Random Static Address Devices")
  FLAGS+=(--ok-button "Select" --cancel-button "Abort" --menu "${DESCRIPTION}" 20 90 8)

  CHOICE=$(whiptail "${FLAGS[@]}" "${MENUOPTS[@]}" 3>&1 1>&2 2>&3 3>&-)

  # Check whiptail window return value.
  [[ $? == +(1|255) ]] && { msg info "Script aborted..."; cleanup; exit 1; }
  # Check and break form the loop in case 'Finish' was chosen.
  [[ ${CHOICE} == "<Continue>" ]] && break

  MACADDR=${CHOICE}
  DEVNAME=${MACADDR}

  [[ "${LINUX_DEVS[*]}" =~ ${MACADDR} ]] && DEVNAME+=" [Linux] $(linux_device_name ${MACADDR})"
  [[ "${WINDOWS_DEVS[*]}" =~ ${MACADDR} ]] && DEVNAME+=" [Windows] $(windows_device_name ${MACADDR})"

  unset SUBMENUOPTS

  for OTHER_MACADDR in $(printf '%s\n' "${COMPATIBLE_DEVS[${MACADDR}]}"); do
    CHOICE="off"

    if [[ "${LINUX_DEVS[*]}" =~ ${OTHER_MACADDR} ]]; then
      OTHER_DEVNAME="$(linux_device_name ${OTHER_MACADDR})"

      [[ "${SYNCED_DEVS[*]}" =~ "${MACADDR}|${OTHER_MACADDR}" ]] && CHOICE="on"
      [[ "${UNSYNCED_DEVS[*]}" =~ "${MACADDR}|${OTHER_MACADDR}" ]] && CHOICE="on"
    elif [[ "${WINDOWS_DEVS[*]}" =~ ${OTHER_MACADDR} ]]; then
      OTHER_DEVNAME="$(windows_device_name ${OTHER_MACADDR})"

      [[ "${SYNCED_DEVS[*]}" =~ "${OTHER_MACADDR}|${MACADDR}" ]] && CHOICE="on"
      [[ "${UNSYNCED_DEVS[*]}" =~ "${OTHER_MACADDR}|${MACADDR}" ]] && CHOICE="on"
    fi

    SUBMENUOPTS+=("${OTHER_MACADDR}" "${OTHER_DEVNAME}" "${CHOICE}")
  done

  # Calculate the height based on the number of entries and increase by 8 for window compensation.
  HEIGHT=$((${#SUBMENUOPTS[@]} / 3 + 8))
  LISTHEIGHT=$((${#SUBMENUOPTS[@]} / 3))

  FLAGS=(--clear --title "${DEVNAME}")
  FLAGS+=(--radiolist "Choose which is the corresponding paired device. (press space)")
  FLAGS+=(${HEIGHT} 80 ${LISTHEIGHT})

  CHOICE=$(whiptail "${FLAGS[@]}" "${SUBMENUOPTS[@]}" 3>&1 1>&2 2>&3 3>&-)

  # Check whiptail window return value.
  [[ $? == +(1|255) ]] && continue
  # If no choice was picked simply continue and loop again.
  [[ -z "${CHOICE}" ]] && continue

  # Order the combined MAC addresses as Windows_MAC|Linux_MAC.
  [[ "${LINUX_DEVS[*]}" =~ ${MACADDR} ]] && MACADDR="${CHOICE}|${MACADDR}" || MACADDR+="|${CHOICE}"

  # Remove any group of devices which have one or the other MAC address from synced/unsynced groups.
  UNSYNCED_DEVS=($(printf '%s\n' "${UNSYNCED_DEVS[@]}" | grep -Ev "${CHOICE}|${MACADDR}"))
  SYNCED_DEVS=($(printf '%s\n' "${SYNCED_DEVS[@]}" | grep -Ev "${CHOICE}|${MACADDR}"))

  # Check if keys are synchronized between the picked devices.
  if is_synced "${MACADDR}"; then
    [[ ! "${SYNCED_DEVS[*]}" =~ "${MACADDR}" ]] && SYNCED_DEVS+=("${MACADDR}")
  else
    [[ ! "${UNSYNCED_DEVS[*]}" =~ "${MACADDR}" ]] && UNSYNCED_DEVS+=("${MACADDR}")
  fi
done

for MACADDR in "${!COMPATIBLE_DEVS[@]}"; do
  # If device wasn't grouped with another compatible device in the previous step, nothing to do.
  [[ ! "${SYNCED_DEVS[*]}" =~ "${MACADDR}" && ! "${UNSYNCED_DEVS[*]}" =~ "${MACADDR}" ]] && continue

  # Remove the newly grouped device MAC address from the unpaired lists.
  UNPAIRED_DEVS_ON_WINDOWS=(
    $(printf '%s\n' "${UNPAIRED_DEVS_ON_WINDOWS[@]}" | grep -Ev "${MACADDR}"))
  UNPAIRED_DEVS_ON_LINUX=(
    $(printf '%s\n' "${UNPAIRED_DEVS_ON_LINUX[@]}" | grep -Ev "${MACADDR}"))
done

# -------------------------------------------------------------------------------------------------
# Display and print unpaired and already synced devices.
if [[ ${#UNPAIRED_DEVS_ON_LINUX[@]} -ne 0 ]]; then
  DESCRIPTION="The following devices aren't paired on Linux and their keys cannot be synchronized:\n"

  for MACADDR in ${UNPAIRED_DEVS_ON_LINUX[@]}; do
    DEVNAME=$(windows_device_name "${MACADDR}")

    msg warning "Device '${MACADDR}  ${DEVNAME}' not paired on Linux. Please pair that device in Linux."
    DESCRIPTION+="\n  ${MACADDR}  ${DEVNAME}"
  done

  # Calculate the height based on the number of lines and increase by 8 for window compensation.
  HEIGHT=$(($(printf "${DESCRIPTION}" | wc -l) + 8))

  FLAGS=(--clear --title "Upaired Devices on Linux")
  FLAGS+=(--yes-button "Ok" --no-button "Abort" --yesno "${DESCRIPTION}" ${HEIGHT} 90)

  whiptail "${FLAGS[@]}" 3>&1 1>&2 2>&3 3>&-

  # Check whiptail window return value.
  [[ $? == +(1|255) ]] && { msg info "Script aborted..."; cleanup; exit 1; }
fi

if [[ ${#UNPAIRED_DEVS_ON_WINDOWS[@]} -ne 0 ]]; then
  DESCRIPTION="The following devices aren't paired on Windows and their keys cannot be synchronized:\n"

  for MACADDR in ${UNPAIRED_DEVS_ON_WINDOWS[@]}; do
    DEVNAME=$(linux_device_name "${MACADDR}")

    msg warning "Device '${MACADDR}  ${DEVNAME}' not paired on Windows. Please pair it on Windows."
    DESCRIPTION+="\n  ${MACADDR}  ${DEVNAME}"
  done

  # Calculate the height based on the number of lines and increase by 8 for window compensation.
  HEIGHT=$(($(printf "${DESCRIPTION}" | wc -l) + 8))

  FLAGS=(--clear --title "Upaired Devices on Windows")
  FLAGS+=(--yes-button "Ok" --no-button "Abort" --yesno "${DESCRIPTION}" ${HEIGHT} 90)

  whiptail "${FLAGS[@]}" 3>&1 1>&2 2>&3 3>&-

  # Check whiptail window return value.
  [[ $? == +(1|255) ]] && { msg info "Script aborted..."; cleanup; exit 1; }
fi

if [[ ${#SYNCED_DEVS[@]} -ne 0 ]]; then
  DESCRIPTION="The following devices are already synchronized on both Linux and Windows:\n"

  for MACADDR in ${SYNCED_DEVS[@]}; do
    DEVNAME=$(linux_device_name "${MACADDR}")

    msg log "Device '${MACADDR} ${DEVNAME}' already synchronized on both Linux and Windows."
    DESCRIPTION+="\n  ${MACADDR}  ${DEVNAME}"
  done

  # Calculate the height based on the number of lines and increase by 8 for window compensation.
  HEIGHT=$(($(printf "${DESCRIPTION}" | wc -l) + 8))

  FLAGS=(--clear --title "Synced Devices on both Linux and Windows")
  FLAGS+=(--yes-button "Ok" --no-button "Abort" --yesno "${DESCRIPTION}" ${HEIGHT} 90)

  whiptail "${FLAGS[@]}" 3>&1 1>&2 2>&3 3>&-

  # Check whiptail window return value.
  [[ $? == +(1|255) ]] && { msg info "Script aborted..."; cleanup; exit 1; }
fi

if [[ ${#UNSYNCED_DEVS[@]} -eq 0 ]]; then
  msg info "No devices were found that are paired on both Linux and Windows and not synchronized!"
  cleanup && exit 1
fi

# -------------------------------------------------------------------------------------------------
# Create main menu options for the paired but unsynced devices.
unset MENUOPTS

for MACADDR in ${UNSYNCED_DEVS[@]}; do
  DEVNAME=$(linux_device_name "${MACADDR}")
  MENUOPTS+=("${MACADDR}" "${DEVNAME}")
done

MENUOPTS+=("<Finish>" "Apply all configured settings...")

SUBMENUOPTS=(
  "Synchronization" "The direction in which keys are going to be synchronized"
  "Linux Keys" "Show paired keys info on Linux"
  "Windows Keys" "Show paired keys info on Windows"
)

# Configure the synchronization settings for the device keys.
while true; do
  DESCRIPTION="Devices paired on both Linux and Windows but not synchronized on both platforms.\n"
  DESCRIPTION+="Select a device in order to inspect and modify its settings."

  FLAGS=(--clear --title "Paired Devices" --ok-button "Select" --cancel-button "Abort")
  FLAGS+=(--menu "${DESCRIPTION}" 20 90 10)

  CHOICE=$(whiptail "${FLAGS[@]}" "${MENUOPTS[@]}" 3>&1 1>&2 2>&3 3>&-)

  # Check whiptail window return value.
  [[ $? == +(1|255) ]] && { msg info "Script aborted..."; cleanup; exit 1; }
  # Check and break form the loop in case 'Finish' was chosen.
  [[ ${CHOICE} == "<Finish>" ]] && break

  MACADDR=${CHOICE}
  DEVNAME=$(linux_device_name "${MACADDR}")

  while true; do
    FLAGS=(--clear --title "${DEVNAME}" --ok-button "Select" --cancel-button "Back")
    FLAGS+=(--menu "Synchronization settings and information." 12 80 4)

    CHOICE=$(whiptail "${FLAGS[@]}" "${SUBMENUOPTS[@]}" 3>&1 1>&2 2>&3 3>&-)

    # Check whiptail window return value.
    [[ $? == +(1|255) ]] && break

    case ${CHOICE} in
      "Windows Keys")
        INFO="$(windows_keys "${MACADDR}")"

        # Calculate the height based on the number of lines and increase by 8 for window compensation.
        HEIGHT=$(($(printf "${INFO}" | wc -l) + 8))

        whiptail --clear --title "${DEVNAME}" --msgbox "${INFO}" ${HEIGHT} 50 3>&1 1>&2 2>&3 3>&-
        ;;

      "Linux Keys")
        INFO="$(linux_keys "${MACADDR}")"

        # Calculate the height based on the number of lines and increase by 8 for window compensation.
        HEIGHT=$(($(printf "${INFO}" | wc -l) + 8))

        whiptail --clear --title "${DEVNAME}" --msgbox "${INFO}" ${HEIGHT} 50 3>&1 1>&2 2>&3 3>&-
        ;;

      "Synchronization")
        TMPLIST=(
          "Windows To Linux" "Synchronize keys from Windows registry into Linux" "off"
          "Linux To Windows" "Synchronize keys from Linux into Windows registry" "off"
        )

        [[ "${WINDOWS_TO_LINUX_DEVS[*]}" =~ ${MACADDR} ]] && TMPLIST[2]="on"
        [[ "${LINUX_TO_WINDOWS_DEVS[*]}" =~ ${MACADDR} ]] && TMPLIST[5]="on"

        FLAGS=(--clear --title "${DEVNAME}" --cancel-button "Back")
        FLAGS+=(--radiolist "Pick the direction in which to synchronize keys. (press space)" 10 80 2)

        CHOICE=$(whiptail "${FLAGS[@]}" "${TMPLIST[@]}" 3>&1 1>&2 2>&3 3>&-)

        # Check whiptail window return value.
        [[ $? == +(1|255) ]] && continue

        if [[ "${CHOICE}" == "Windows To Linux" ]]; then
          [[ ! "${WINDOWS_TO_LINUX_DEVS[*]}" =~ ${MACADDR} ]] && WINDOWS_TO_LINUX_DEVS+=("${MACADDR}")
          LINUX_TO_WINDOWS_DEVS=($(printf '%s\n' "${LINUX_TO_WINDOWS_DEVS[@]}" | grep -v "${MACADDR}"))
        elif [[ "${CHOICE}" == "Linux To Windows" ]]; then
          [[ ! "${LINUX_TO_WINDOWS_DEVS[*]}" =~ ${MACADDR} ]] && LINUX_TO_WINDOWS_DEVS+=("${MACADDR}")
          WINDOWS_TO_LINUX_DEVS=($(printf '%s\n' "${WINDOWS_TO_LINUX_DEVS[@]}" | grep -v "${MACADDR}"))
        fi
        ;;
    esac
  done
done

if [[ ${#WINDOWS_TO_LINUX_DEVS[@]} -eq 0 && ${#LINUX_TO_WINDOWS_DEVS[@]} -eq 0 ]]; then
  msg warning "No devices were configured for synchronization!"
  cleanup && exit 1
fi

# -------------------------------------------------------------------------------------------------
# Verify configuration
DESCRIPTION="Is the below synchronization configuration correct?\n"

for MACADDR in ${WINDOWS_TO_LINUX_DEVS[@]}; do
  DEVNAME=$(linux_device_name "${MACADDR}")
  DESCRIPTION+="\n  Windows To Linux  ${MACADDR}  ${DEVNAME}";
done

for MACADDR in ${LINUX_TO_WINDOWS_DEVS[@]}; do
  DEVNAME=$(linux_device_name "${MACADDR}")
  DESCRIPTION+="\n  Linux To Windows  ${MACADDR}  ${DEVNAME}";
done

# Calculate the height based on the number of lines and increase by 8 for window compensation.
HEIGHT=$(($(printf "${DESCRIPTION}" | wc -l) + 8))

whiptail --clear --title "Bluetooth" --yesno "${DESCRIPTION}" ${HEIGHT} 100 3>&1 1>&2 2>&3 3>&-

# Check whiptail window return value.
[[ $? == +(1|255) ]] && { msg info "Installation aborted...."; cleanup; exit 1; }

# Synchronize the keys for the picked devices.
synckeys && cleanup
