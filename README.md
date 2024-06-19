## get xor key

```
perl ./getkey.pl ~/tcpdump.pcap 2>/dev/null > ~/bc.key
```

## show OCPP1.6j request/responses

```
bash evse-ws-decrypt.sh ~/tcpdump.pcap ~/bcencrypt.xor.key 2>/dev/null
```
