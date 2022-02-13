#!/bin/sh

NAME="$(basename "$0")[$$]"
SCRIPT_LOC="$(readlink -f "$0")"
UPPER_SCRIPT="/opt/etc/init.d/S99AdGuardHome"
LOWER_SCRIPT="/opt/etc/init.d/rc.func.AdGuardHome"

[ ! -f "$UPPER_SCRIPT" ] && exit 1 || UPPER_SCRIPT_LOC=". $UPPER_SCRIPT"
[ ! -f "$LOWER_SCRIPT" ] && exit 1 || LOWER_SCRIPT_LOC=". $LOWER_SCRIPT"
[ -z "$PROCS" ] && $UPPER_SCRIPT_LOC

lower_script () {
  case $1 in
    start|stop|restart|kill|check)
      $LOWER_SCRIPT_LOC $1 $NAME
      ;;
  esac
}

dnsmasq_params () {
  local CONFIG
  local COUNT
  local iCOUNT
  local dCOUNT
  local iVARS
  local IVARS
  local dVARS
  local DVARS
  local NIVARS
  local NDCARS
  local i 
  CONFIG="/etc/dnsmasq.conf"
  if [ "$(pidof "$PROCS")" ] && [ -z "$(nvram get ipv6_rtr_addr)" ]; then printf "%s\n" "port=553" "local=/$(nvram get lan_ipaddr | awk 'BEGIN{FS="."}{print $2"."$1".in-addr.arpa"}')/" "local=/10.in-addr.arpa/" "dhcp-option=lan,6,0.0.0.0" >> $CONFIG; fi
  if [ "$(pidof "$PROCS")" ] && [ -n "$(nvram get ipv6_rtr_addr)" ]; then printf "%s\n" "port=553" "local=/$(nvram get lan_ipaddr | awk 'BEGIN{FS="."}{print $2"."$1".in-addr.arpa"}')/" "local=/10.in-addr.arpa/" "local=/$(nvram get ipv6_prefix | sed "s/://g;s/^.*$/\n&\n/;tx;:x;s/\(\n.\)\(.*\)\(.\n\)/\3\2\1/;tx;s/\n//g;s/\(.\)/\1./g;s/$/ip6.arpa/")/" "dhcp-option=lan,6,0.0.0.0" >> $CONFIG; fi
  if [ -n "$(route | grep "br" | grep -v "br0" | grep -E "^(192\.168|10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.)" | awk '{print $1}' | sed -e 's/[0-9]$/1/' | sed -e ':a; N; $!ba;s/\n/ /g')" ]; then
    iCOUNT="1"
    for iVARS in $(route | grep "br" | grep -v "br0" | grep -E "(192\.168|10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.)" | awk '{print $8}' | sed -e ':a; N; $!ba;s/\n/ /g'); do
      [ "$iCOUNT" = "1" ] && COUNT="$iCOUNT" && IVARS="$iVARS"
      [ "$iCOUNT" != "1" ] && COUNT="$COUNT $iCOUNT" && IVARS="$IVARS $iVARS"
      iCOUNT="$((iCOUNT+1))"
    done
    dCOUNT="1"
    for dVARS in $(route | grep "br" | grep -v "br0" | grep -E "192\.168|10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.)" | awk '{print $1}' | sed -e 's/[0-9]$/1/' | sed -e ':a; N; $!ba;s/\n/ /g'); do
      [ "$dCOUNT" = "1" ] && DVARS="$dVARS"
      [ "$dCOUNT" != "1" ] && DVARS="$DVARS $dVARS"
      dCOUNT="$((dCOUNT+1))"
    done
    for i in $COUNT; do
      NIVARS="$(printf "%s\n" "$IVARS" | cut -d' ' -f"$i")"
      NDVARS="$(printf "%s\n" "$DVARS" | cut -d' ' -f"$i")"
      if [ "$(pidof "$PROCS")" ]; then printf "%s\n" "dhcp-option=${NIVARS},6,${NDVARS}" >> $CONFIG; fi
    done
  fi
}

start_AdGuardHome () {
  if [ -z "$(pidof "$PROCS")" ]; then lower_script start; else lower_script restart; fi
  if [ ! -f "/tmp/stats.db" ]; then ln -sf "${WORK_DIR}/data/stats.db" "/tmp/stats.db" >/dev/null 2>&1; fi
  if [ ! -f "/tmp/sessions.db" ]; then ln -sf "${WORK_DIR}/data/sessions.db" "/tmp/sessions.db" >/dev/null 2>&1; fi
  lower_script check
}

stop_AdGuardHome () {
  if [ -n "$(pidof "$PROCS")" ]; then lower_script stop; lower_script kill; else lower_script check; fi
  if [ -f "/tmp/stats.db" ]; then rm -rf "/tmp/stats.db" >/dev/null 2>&1; fi
  if [ -f "/tmp/sessions.db" ]; then rm -rf "/tmp/sessions.db" >/dev/null 2>&1; fi
  service restart_dnsmasq >/dev/null 2>&1
  lower_script check
}

start_monitor () {
  trap "" 1 2 3 15
  while [ "$(nvram get ntp_ready)" -eq 0 ]; do sleep 1; done
  local NW_STATE
  local RES_STATE
  local COUNT
  COUNT=0
  while true; do
    if [ "$COUNT" -eq 90 ]; then
      COUNT=0
      timezone
    fi
    COUNT="$((COUNT + 1))"
    NW_STATE="$(ping 1.1.1.1 -c1 -W2 >/dev/null 2>&1; echo $?)"
    RES_STATE="$(nslookup google.com 127.0.0.1 >/dev/null 2>&1; echo $?)"
    if [ -f "/opt/sbin/AdGuardHome" ]; then
      if [ -z "$(pidof "$PROCS")" ]; then
        logger -st "$NAME" "Warning: $PROCS is dead; $NAME will force-start it!"
        start_AdGuardHome
      elif { [ "$NW_STATE" = "0" ] && [ "$RES_STATE" != "0" ]; }; then
        logger -st "$NAME" "Warning: $PROCS is not responding; $NAME will re-start it!"
        start_AdGuardHome
      fi
    fi
    sleep 10
  done
}

timezone () {
  local SANITY
  local NOW
  local TIMEZONE
  local TARGET
  #local LINK
  SANITY="$(date -u -r "$0" '+%s')"
  NOW="$(date -u '+%s')"
  TIMEZONE="${WORK_DIR}/localtime"
  TARGET="/etc/localtime"
  #LINK="$(readlink "$TARGET")"
  if [ -f "$TARGET" ]; then
      if [ "$NOW" -ge "$SANITY" ]; then
        touch "$0"
      elif [ "$NOW" -le "$SANITY" ]; then
        date -u -s "$(date -u -r \"$0\" '+%Y-%m-%d %H:%M:%S')"
      fi 
  elif [ -f "$TIMEZONE" ] || [ ! -f "$TARGET" ]; then
    ln -sf $TIMEZONE $TARGET
    timezone
  fi
}

unset TZ

case $1 in
  "monitor-start")
    start_monitor &
    ;;
  "dnsmasq")
    dnsmasq_params
    ;;
  "services-stop")
    timezone
    ;;
  "start"|"restart")
    if [ -z "$(pidof "$PROCS")" ]; then start_AdGuardHome; $SCRIPT_LOC monitor-start >/dev/null 2>&1; else start_AdGuardHome; fi
    timezone
    ;;
  "stop"|"kill")
    stop_AdGuardHome
    killall -q -9 $PROCS S99${PROCS} ${PROCS}.sh 2>/dev/null
    ;;
esac