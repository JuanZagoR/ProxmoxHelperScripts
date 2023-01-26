#!/usr/bin/env bash
function header_info {
cat <<"EOF"

 ______ _                                    _            
(_____ (_)                                  | |           
 _____) )  ___  ____ ____   ____ ____   ____| | ____  ___ 
|  ____/ |/___)/ _  |  _ \ / _  |  _ \ / _  ) |/ _  )/___)
| |    | |___ ( ( | | | | ( ( | | | | ( (/ /| ( (/ /|___ |
|_|    |_(___/ \_||_| ||_/ \_||_| ||_/ \____)_|\____|___/ 
                    |_|         |_|                       
Instalador de Home Assistant OS en Proxmox

EOF
}
clear
header_info
echo -e "\n Cargando..."
GEN_MAC=$(echo 'AE 1A 60'$(od -An -N3 -t xC /dev/urandom) | sed -e 's/ /:/g' | tr '[:lower:]' '[:upper:]')
USEDID=$(pvesh get /cluster/resources --type vm --output-format yaml | egrep -i 'vmid' | awk '{print substr($2, 1, length($2)-0) }')
NEXTID=$(pvesh get /cluster/nextid)
STABLE=$(curl -s https://raw.githubusercontent.com/home-assistant/version/master/stable.json | grep "ova" | awk '{print substr($2, 2, length($2)-3) }')
BETA=$(curl -s https://raw.githubusercontent.com/home-assistant/version/master/beta.json | grep "ova" | awk '{print substr($2, 2, length($2)-3) }')
DEV=$(curl -s https://raw.githubusercontent.com/home-assistant/version/master/dev.json | grep "ova" | awk '{print substr($2, 2, length($2)-3) }')
LATEST=$(curl -s https://api.github.com/repos/home-assistant/operating-system/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
YW=`echo "\033[33m"`
BL=`echo "\033[36m"`
HA=`echo "\033[1;34m"`
RD=`echo "\033[01;31m"`
BGN=`echo "\033[4;92m"`
GN=`echo "\033[1;92m"`
DGN=`echo "\033[32m"`
CL=`echo "\033[m"`
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
THIN="discard=on,ssd=1,"
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR
trap cleanup EXIT
function error_exit() {
  trap - ERR
  local reason="Fallo desconocido."
  local msg="${1:-$reason}"
  local flag="${RD}‼ ERROR ${CL}$EXIT@$LINE"
  echo -e "$flag $msg" 1>&2
  [ ! -z ${VMID-} ] && cleanup_vmid
  exit $EXIT
}
function cleanup_vmid() {
  if $(qm status $VMID &>/dev/null); then
    if [ "$(qm status $VMID | awk '{print $2}')" == "Funcionando" ]; then
      qm stop $VMID
    fi
    qm destroy $VMID
  fi
}
function cleanup() {
  popd >/dev/null
  rm -rf $TEMP_DIR
}
TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if (whiptail --title "HOME ASSISTANT OS VM" --yesno "Este script creará una nueva instancia de Home Assistant OS VM. ¿Continuar?" 10 58); then
    echo "User selected Yes"
else
    clear
    echo -e "⚠ El usuario ha detenido el script \n"
    exit
fi
function msg_info() {
    local msg="$1"
    echo -ne " ${HOLD} ${YW}${msg}..."
}
function msg_ok() {
    local msg="$1"
    echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}
function msg_error() {
    local msg="$1"
    echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}
function PVE_CHECK() {
if [ `pveversion | grep "pve-manager/7.2\|7.3" | wc -l` -ne 1 ]; then
        echo "⚠ Esta versión de Proxmox no está soportada"
        echo "Se requiere al menos Proxmox VE Version: =>7.2"
        echo "Saliendo..."
        sleep 2
        exit
fi
}
function ARCH_CHECK() {
  ARCH=$(dpkg --print-architecture)
  if [[ "$ARCH" != "amd64" ]]; then
    echo -e "\n ❌  Este script no funcionará con PiMox \n"
    echo -e "Saliendo..."
    sleep 2
    exit
  fi
}
function default_settings() {
        echo -e "${DGN}Versión de HAOS a usar: ${BGN}${STABLE}${CL}"
        BRANCH=${STABLE}
        echo -e "${DGN}ID de VM a usar: ${BGN}$NEXTID${CL}"
        VMID=$NEXTID
        echo -e "${DGN}Tipo de máquina a usar: ${BGN}i440fx${CL}"
        FORMAT=",efitype=4m"
        MACHINE=""
        echo -e "${DGN}Hostname a usar: ${BGN}haos${STABLE}${CL}"
        HN=haos${STABLE}
        echo -e "${DGN}Núcleos reservados: ${BGN}2${CL}"
        CORE_COUNT="2"
        echo -e "${DGN}Memoria RAM reservada: ${BGN}4096${CL}"
        RAM_SIZE="4096"
        echo -e "${DGN}Usar Bridge: ${BGN}vmbr0${CL}"
        BRG="vmbr0"
        echo -e "${DGN}Dirección MAC a usar: ${BGN}$GEN_MAC${CL}"
        MAC=$GEN_MAC
        echo -e "${DGN}Usar VLAN: ${BGN}Default${CL}"
        VLAN=""
        echo -e "${DGN}Tamaño de MTU a usar: ${BGN}Default${CL}"
        MTU=""
        echo -e "${DGN}¿Iniciar al terminar?: ${BGN}yes${CL}"
        START_VM="yes"
        echo -e "${BL}Creando VM de HAOS con los datos por defecto${CL}"
}
function advanced_settings() {
BRANCH=$(whiptail --title "Versión de HAOS" --radiolist "Escoger Versión" --cancel-button Exit-Script 10 58 4 \
"$STABLE" "Estable" ON \
"$BETA" "Beta" OFF \
"$DEV" "Dev" OFF \
"$LATEST" "Última" OFF \
3>&1 1>&2 2>&3)
exitstatus=$?
if [ $exitstatus = 0 ]; then echo -e "${DGN}Versión de HAOS a usar: ${BGN}$BRANCH${CL}"; fi
VMID=$(whiptail --inputbox "Ajustar ID de VM" 8 58 $NEXTID --title "ID de Máquina Virtual" --cancel-button Exit-Script 3>&1 1>&2 2>&3)
exitstatus=$?
if [ -z $VMID ]; then VMID="$NEXTID"; echo -e "${DGN}Máquina Virtual: ${BGN}$VMID${CL}";
  else
    if echo "$USEDID" | egrep -q "$VMID"
    then
      echo -e "\n🚨  ${RD}El ID $VMID ya está en uso${CL} \n"
      echo -e "Operación abortada \n"
      sleep 2;
      exit
  else
    if [ $exitstatus = 0 ]; then echo -e "${DGN}ID de VM: ${BGN}$VMID${CL}"; fi;
    fi
fi
MACH=$(whiptail --title "Tipo de máquina" --radiolist --cancel-button Exit-Script "Escoger tipo de máquina" 10 58 2 \
"i440fx" "i440fx" ON \
"q35" "q35" OFF \
3>&1 1>&2 2>&3)
exitstatus=$?
if [ $MACH = q35 ]; then
  echo -e "${DGN}Usando tipo de máquina: ${BGN}$MACH${CL}"
  FORMAT=""
  MACHINE=" -machine q35"
  else
  echo -e "${DGN}Usando tipo de máquina: ${BGN}$MACH${CL}"
  FORMAT=",efitype=4m"
  MACHINE=""
fi
VM_NAME=$(whiptail --inputbox "Ajustar Hostname" 8 58 haos${BRANCH} --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3)
exitstatus=$?
if [ -z $VM_NAME ]; then HN="haos${BRANCH}"; echo -e "${DGN}Usando Hostname: ${BGN}$HN${CL}";
else
  if [ $exitstatus = 0 ]; then HN=$(echo ${VM_NAME,,} | tr -d ' '); echo -e "${DGN}Usando Hostname: ${BGN}$HN${CL}"; fi;
fi
CORE_COUNT=$(whiptail --inputbox "Reservar núcleos" 8 58 2 --title "Número de núcleos" --cancel-button Exit-Script 3>&1 1>&2 2>&3)
exitstatus=$?
if [ -z $CORE_COUNT ]; then CORE_COUNT="2"; echo -e "${DGN}Núcleos reservados: ${BGN}$CORE_COUNT${CL}";
else
  if [ $exitstatus = 0 ]; then echo -e "${DGN}Núcleos reservados: ${BGN}$CORE_COUNT${CL}"; fi;
fi
RAM_SIZE=$(whiptail --inputbox "Memoria RAM reservada (en MiB)" 8 58 4096 --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3)
exitstatus=$?
if [ -z $RAM_SIZE ]; then RAM_SIZE="4096"; echo -e "${DGN}Memoria RAM reservada: ${BGN}$RAM_SIZE${CL}";
else
  if [ $exitstatus = 0 ]; then echo -e "${DGN}Memoria RAM reservada: ${BGN}$RAM_SIZE${CL}"; fi;
fi
BRG=$(whiptail --inputbox "Usar Bridge:" 8 58 vmbr0 --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3)
exitstatus=$?
if [ -z $BRG ]; then BRG="vmbr0"; echo -e "${DGN}Usando Bridge: ${BGN}$BRG${CL}";
else
  if [ $exitstatus = 0 ]; then echo -e "${DGN}Usando Bridge: ${BGN}$BRG${CL}"; fi;
fi
MAC1=$(whiptail --inputbox "Ajustar dirección MAC" 8 58 $GEN_MAC --title "MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3)
exitstatus=$?
if [ -z $MAC1 ]; then MAC="$GEN_MAC"; echo -e "${DGN}Dirección MAC en uso: ${BGN}$MAC${CL}";
else
 if [ $exitstatus = 0 ]; then MAC="$MAC1"; echo -e "${DGN}Dirección MAC en uso: ${BGN}$MAC1${CL}"; fi
fi
VLAN1=$(whiptail --inputbox "Configurar VLAN (dejar en blanco si no se usa)" 8 58 --title "VLAN" --cancel-button Exit-Script 3>&1 1>&2 2>&3)
exitstatus=$?
if [ $exitstatus = 0 ]; then
  if [ -z $VLAN1 ]; then VLAN1="Default" VLAN="";
    echo -e "${DGN}Usando VLAN: ${BGN}$VLAN1${CL}"
else
    VLAN=",tag=$VLAN1"
    echo -e "${DGN}Usando VLAN: ${BGN}$VLAN1${CL}"
  fi  
fi
MTU1=$(whiptail --inputbox "Tamaño de MTU a usar (dejar en blanco para usar por defecto" 8 58 --title "MTU SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3)
exitstatus=$?
if [ $exitstatus = 0 ]; then
  if [ -z $MTU1 ]; then
    MTU1="Default" MTU=""
    echo -e "${DGN}Tamaño de MTU en uso: ${BGN}$MTU1${CL}"
  else
    MTU=",mtu=$MTU1"
    echo -e "${DGN}Tamaño de MTU en uso: ${BGN}$MTU1${CL}"
  fi
fi
if (whiptail --title "Iniciar máquina virtual" --yesno "¿Iniciar VM al completar?" 10 58); then
    echo -e "${DGN}Iniciar VM al completar: ${BGN}yes${CL}"
    START_VM="yes"
else
    echo -e "${DGN}Iniciar VM al completar: ${BGN}no${CL}"
    START_VM="no"
fi
if (whiptail --title "Configuración avanzada completada" --yesno "¿Listo para crear una VM con HAOS ${BRANCH} ?" --no-button Do-Over 10 58); then
    echo -e "${RD}Creando una VM con la configuración anterior${CL}"
else
  clear
  header_info
  echo -e "${RD}Usando configuración avanzada${CL}"
  advanced_settings
fi
}
function START_SCRIPT() {
if (whiptail --title "Configuración" --yesno "¿Usar configuración por defecto?" --no-button Advanced 10 58); then
  clear
  header_info
  echo -e "${BL}Usando configuración por defecto${CL}"
  default_settings
else
  clear
  header_info
  echo -e "${RD}Usando configuración avanzada${CL}"
  advanced_settings
fi
}
ARCH_CHECK
PVE_CHECK
START_SCRIPT
msg_info "Validando almacenamiento"
while read -r line; do
  TAG=$(echo $line | awk '{print $1}')
  TYPE=$(echo $line | awk '{printf "%-10s", $2}')
  FREE=$(echo $line | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
  ITEM="  Type: $TYPE Free: $FREE "
  OFFSET=2
  if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
    MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
  fi
STORAGE_MENU+=( "$TAG" "$ITEM" "OFF" )
done < <(pvesm status -content images | awk 'NR>1')
VALID=$(pvesm status -content images | awk 'NR>1')
if [ -z "$VALID" ]; then
msg_error "No se puede detectar un storage pool adecuado."
  exit
elif [ $((${#STORAGE_MENU[@]}/3)) -eq 1 ]; then
  STORAGE=${STORAGE_MENU[0]}
else
  while [ -z "${STORAGE:+x}" ]; do
    STORAGE=$(whiptail --title "Storage Pools" --radiolist \
    "¿Qué storage pool usar para almacenamiento?\n\n" \
    16 $(($MSG_MAX_LENGTH + 23)) 6 \
    "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3) || exit
  done
fi
msg_ok "Usando ${CL}${BL}$STORAGE${CL} ${GN} como almacenamiento"
msg_ok "El ID de VM es ${CL}${BL}$VMID${CL}."
msg_info "Obteniendo dirección para imagen de disco HAOS ${BRANCH}"
if [ "$BRANCH" == "$DEV" ]; then 
URL=https://os-builds.home-assistant.io/${BRANCH}/haos_ova-${BRANCH}.qcow2.xz
else
URL=https://github.com/home-assistant/operating-system/releases/download/${BRANCH}/haos_ova-${BRANCH}.qcow2.xz
fi
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
wget -q --show-progress $URL
echo -en "\e[1A\e[0K"
FILE=$(basename $URL)
msg_ok "Descargado ${CL}${BL}haos_ova-${BRANCH}.qcow2.xz${CL}"
msg_info "Extrayendo imagen de disco KVM"
unxz $FILE
STORAGE_TYPE=$(pvesm status -storage $STORAGE | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
  nfs|dir)
    DISK_EXT=".raw"
    DISK_REF="$VMID/"
    DISK_IMPORT="-format raw"
    THIN=""
    ;;
  btrfs)
    DISK_EXT=".raw"
    DISK_REF="$VMID/"
    DISK_IMPORT="-format raw"
    FORMAT=",efitype=4m"
    THIN=""
    ;;
esac
for i in {0,1}; do
  disk="DISK$i"
  eval DISK${i}=vm-${VMID}-disk-${i}${DISK_EXT:-}
  eval DISK${i}_REF=${STORAGE}:${DISK_REF:-}${!disk}
done
msg_ok "Imagen KVM extraída"
msg_info "Creando VM Home Assistant OS"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
qm importdisk $VMID ${FILE%.*} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${THIN}size=32G \
  -boot order=scsi0 \
  -description "# Home Assistant OS
### https://github.com/JuanZagoR
[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/juanzago)" >/dev/null
msg_ok "La VM ha sido creada ${CL}${BL}(${HN})"
if [ "$START_VM" == "yes" ]; then
msg_info "Iniciando Home Assistant OS VM"
qm start $VMID
msg_ok "Home Assistant OS VM Iniciada"
fi
msg_ok "Completado con éxito\n"
