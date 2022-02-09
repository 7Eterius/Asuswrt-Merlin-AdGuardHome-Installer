#!/bin/sh

[ -f "/opt/etc/init.d/S99AdGuardHome" ] && . /opt/etc/init.d/S99AdGuardHome

NAME="$(basename $0)[$$]"

dnsmasq_params () {
  if [ "$(pidof AdGuardHome)" ] && [ "$(nvram get ipv6_fw_enable)" != "1" ]; then printf "%s\n" "port=553" "local=/$(nvram get lan_ipaddr | awk 'BEGIN{FS="."}{print $2"."$1".in-addr.arpa"}')/" "local=/10.in-addr.arpa/" "dhcp-option=lan,6,0.0.0.0" >> $1; fi
  if [ "$(pidof AdGuardHome)" ] && [ "$(nvram get ipv6_fw_enable)" = "1" ]; then printf "%s\n" "port=553" "local=/$(nvram get lan_ipaddr | awk 'BEGIN{FS="."}{print $2"."$1".in-addr.arpa"}')/" "local=/10.in-addr.arpa/" "local=/$(nvram get ipv6_prefix | sed "s/://g;s/^.*$/\n&\n/;tx;:x;s/\(\n.\)\(.*\)\(.\n\)/\3\2\1/;tx;s/\n//g;s/\(.\)/\1./g;s/$/ip6.arpa/")/" "dhcp-option=lan,6,0.0.0.0" >> $1; fi
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
      NIVARS="$(printf "%s\n" "$IVARS" | cut -d' ' -f$i)"
      NDVARS="$(printf "%s\n" "$DVARS" | cut -d' ' -f$i)"
      if [ "$(pidof AdGuardHome)" ]; then printf "%s\n" "dhcp-option=$NIVARS,6,$NDVARS" >> $1; fi
    done
  fi
}

start_AdGuardHome () {
  killall -q AdGuardHome
  logger -st "$NAME" "Starting AdGuardHome"
  $PREARGS AdGuardHome $ARGS >/dev/null 2>&1 </dev/null &
}

start_monitor () {
  trap "" 1 2
  while [ "$(nvram get ntp_ready)" -eq 0 ]; do sleep 1; done
  local NW_STATE
  local RES_STATE
  local COUNT=0
  while true; do  
    if [ "$COUNT" -eq 90 ]; then
      COUNT=0
      timezone
    fi
    COUNT="$((COUNT + 1))"
    NW_STATE="$(ping 1.1.1.1 -c1 -W2 >/dev/null 2>&1; echo $?)"
    RES_STATE="$(nslookup google.com 127.0.0.1 >/dev/null 2>&1; echo $?)"
    if [ -f "/opt/sbin/AdGuardHome" ]; then
      if [ -z "$(pidof AdGuardHome)" ]; then
        logger -st "$NAME" "Warning: AdGuardHome is dead"
        start_AdGuardHome
      elif [ "$NW_STATE" = "0" -a "$RES_STATE" != "0" ]; then
        logger -st "$NAME" "Warning: AdGuardHome is not responding"
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
  local LINK
  SANITY="$(date -u -r $0 '+%s')"
  NOW="$(date -u '+%s')"
  TIMEZONE="/opt/etc/AdGuardHome/localtime"
  TARGET="/etc/localtime"
  LINK="$(readlink $TARGET)"
  if [ -f "$TIMEZONE" ] && [ "$LINK" = "$TIMEZONE" ]; then
      if [ "$NOW" -ge "$SANITY" ]; then
        touch "$0"
      fi
  elif [ -f "$TIMEZONE" ]; then
    ln -sf $TIMEZONE $TARGET
    if [ "$NOW" -le "$SANITY" ]; then
      date -u -s "$(date -u -r \"$0\" '+%Y-%m-%d %H:%M:%S')"
    fi
  fi
}

unset TZ
case $1 in
  "start"|"restart")    
    $0 monitor-start
    start_AdGuardHome 
    ;;
  "dnsmasq")
    dnsmasq_params
    ;;
  "monitor-start")
    start_monitor &
    ;;
  "services-stop")
    timezone
    ;;
esac
