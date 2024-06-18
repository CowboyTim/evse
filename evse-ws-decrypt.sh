#!/bin/bash
fn=$1
shift
[[ ! -f "$fn" ]] && exit 1
websocket_lua_script_file=$(dirname $(readlink -f $BASH_SOURCE))/ws.lua
tshark -r "$fn" -2 -R \
    'tcp and (not tcp.len==0) and (websocket || http)' \
    -Xlua_script:$websocket_lua_script_file \
    -T fields \
    -E occurrence=l \
    -E separator=/t \
    -e tcp.stream \
    -e ip.src \
    -e ip.dst \
    -e text \
    -e _ws.col.Info \
    -e bcencrypt.command \
    |awk -F'\t' '{print $6}'|jq -cr
