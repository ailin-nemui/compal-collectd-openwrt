#!/bin/sh

HOSTNAME="${COLLECTD_HOSTNAME:-$(cat /proc/sys/kernel/hostname)}"
INTERVAL="60"
ID="$$"

. /usr/share/libubox/jshn.sh


xml_to_json() {
    sed \
	-e 's/\r/\\r/g' \
	"$@" \
	| tr $'\n' $'\r' \
	| sed \
	      -e 's/\r*$//g' \
	      -e 's/\r/\\n/g' \
	      -e 's/<?.*?>//' \
	      -e 's/^<\([^>]*\)>\(.*\)<\/\1>$/"\1":{\2}/' \
	      -e 's/<\([^>]*\)>\(.*<\/\1><\1>.*\)<\/\1>/"\1":[{\2}],/g' \
	      -e 's/<\/\([^>]*\)><\1>/},{/g' \
	      -e 's/<\([^>]*\)>\([^<]*\)<\/\1>/"\1":"\2",/g' \
	      -e 's/<\([^>]*\) \/>/"\1":null,/g' \
	      -e 's/<\([^>]*\)>\([^<]*\)<\/\1>/"\1":{\2},/g' \
	      -e 's/{\(\|\([^"}][^}]*\)\)}/"\2"/g' \
	      -e 's/<\([^>]*\)>\([^<]*\)<\/\1>/"\1":{\2},/g' \
	      -e 's/$/}/' \
	      -e 's/^/{/' \
	      -e 's/,*}/}/g'
}

dump_codewords() {
    local unc
    local cor
    local une
    local dsid
    local num

    num="$2"
    if [ "$num" = "signal" ]; then
	num=1
    fi

    json_select "$2"
    json_get_var unc uncorrectable
    json_get_var cor correctable
    json_get_var une unerrored
    json_get_var dsid dsid
    json_select ..

    echo "PUTVAL \"$HOSTNAME/exec-cmstat/cm_codewords-ds$num\" interval=$INTERVAL N:$une:$cor:$unc"
}

dump_upstream() {
    local pow
    local t3to
    local mod
    local freq
    local usid
    local num

    num="$2"
    if [ "$num" = "upstream" ]; then
	num=1
    fi

    json_select "$2"
    json_get_var pow power
    json_get_var t3to t3Timeouts
    json_get_var mod mod
    json_get_var freq freq
    json_get_var usid usid
    json_select ..

    echo "PUTVAL \"$HOSTNAME/exec-cmstat/cm_line_info-us$num\" interval=$INTERVAL N:$usid:$freq:${mod%%qam}:$pow"
    echo "PUTVAL \"$HOSTNAME/exec-cmstat/cm_us_error-us$num\" interval=$INTERVAL N:$t3to"
}

dump_downstream() {
    local pow
    local rxmer
    local mod
    local freq
    local chid
    local num

    num="$2"
    if [ "$num" = "downstream" ]; then
	num=1
    fi

    json_select "$2"
    json_get_var pow pow
    json_get_var rxmer RxMER
    json_get_var mod mod
    json_get_var freq freq
    json_get_var chid chid
    json_select ..

    echo "PUTVAL \"$HOSTNAME/exec-cmstat/cm_line_info-ds$num\" interval=$INTERVAL N:$chid:$freq:${mod%%qam}:$pow"
    echo "PUTVAL \"$HOSTNAME/exec-cmstat/cm_ds_quality-ds$num\" interval=$INTERVAL N:$rxmer"
}

device_token() {
    curl -s -c "/tmp/cm.cookie.$ID" -I http://192.168.100.1/common_page/login.html -o /dev/null
}

read_report() {
    local num

    device_token

    json_load "$( query_device 12 | xml_to_json )"
    json_select signal_table
    json_get_var num sig_num
    if [ "$num" -gt 1 ]; then
	json_for_each_item dump_codewords signal
    else
	dump_codewords '' signal
    fi
    json_select ..
    json_cleanup

    json_load "$( query_device 11 | xml_to_json )"
    json_select upstream_table
    json_get_var num us_num
    echo "PUTVAL \"$HOSTNAME/exec-cmstat/count-us_num\" interval=$INTERVAL N:$num"
    if [ "$num" -gt 1 ]; then
	json_for_each_item dump_upstream upstream
    else
	dump_upstream '' upstream
    fi
    json_select ..
    json_cleanup

    json_load "$( query_device 10 | xml_to_json )"
    json_select downstream_table
    json_get_var num ds_num
    echo "PUTVAL \"$HOSTNAME/exec-cmstat/count-ds_num\" interval=$INTERVAL N:$num"
    if [ "$num" -gt 1 ]; then
	json_for_each_item dump_downstream downstream
    else
	dump_downstream '' downstream
    fi
    json_select ..
    json_cleanup
}

query_device() {
    curl -s -c "/tmp/cm.cookie.$ID" http://192.168.100.1/xml/getter.xml \
	 -d 'token='"$(awk '$6 == "sessionToken" {print $7;exit}' "/tmp/cm.cookie.$ID")"'&fun='"$1"
}

# while not orphaned
while [ $(awk '$1 ~ "^PPid:" {print $2;exit}' /proc/$$/status) -ne 1 ] ; do
    read_report
    sleep "${INTERVAL%%.*}"
done

rm -f "/tmp/cm.cookie.$ID" 2>/dev/null
