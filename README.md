## prerequisites

- [perl](https://www.perl.org/get.html)
- [libjson-perl](https://metacpan.org/pod/JSON)
- [tcpdump](https://www.tcpdump.org/)
- [wireshark](https://www.wireshark.org/)
- [awk](https://www.gnu.org/software/gawk/)
- [bash](https://www.gnu.org/software/bash/)
- [jq](https://stedolan.github.io/jq/)
- [lua](https://www.lua.org/)

Install on linux mint:

```
sudo apt install perl libjson-perl tcpdump wireshark tshark gawk bash jq lua5.3
```

## create tcpdump file

```
tcpdump -i eth0 -s 65535 -w tcpdump.pcap
```

## get xor key

```
perl getkey.pl tcpdump.pcap 2>/dev/null > bc.key
```

## show OCPP1.6j request/responses

```
bash evse-ws-decrypt.sh tcpdump.pcap ~/bc.key 2>/dev/null
```
