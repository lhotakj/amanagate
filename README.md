# unbound-parental-control
Simple script to install unbound on raspberry with parental control. Tested on Raspberry Pi Zero running DietPi.


# 🚩 Basic installation
## Clone the repository

```sh
cd /tmp
git clone https://github.com/lhotakj/unbound-parental-control.git
cd unbound-parental-control
```

## Install Unbound and setup the local-lan 
Install the unbound and sets the upstream servers to AdGuard DNS servers blocking ads and sets custom A records defined in the hosts like file
```sh
sudo ./install-unbound.sh <path to own hosts like file>
```

Example:
```sh
sudo ./install-unbound.sh ./conf/local-lan.txt
```

## Test if local A type addreses are properly set
Simply test one of the host defines in the host like file, eg.
```sh
 dig @localhost amd
```

# ⛔ Parental Control
## Add parental control
```sh
sudo ./add-parental-control.sh <path to the ini file>
```
The ini file has to be in the following format. Note that there can be added more `block_cron` and `allow_cron` configurations, e.g. you want to set specific rule for weekday and weekend
```ini
[metadata]
kid_name=<rulename>
block_cron=<valid cron expression when to block defined domains>
allow_cron=<valid cron expression when to unblock defined domains>

[domains]
<domain 1>
<domain 2>
...

[devices]
<ip 1>
<ip 2>
...
```
Example:
```sh
sudo ./add-parental-control.sh ./conf/jonas.ini
```

## Remove parental control
```sh
sudo ./add-parental-control.sh ./conf/jonas.ini
```

# 🪲 Debugging / testing hints

## Test if parental block works (domain `youtube.com` on host `10.0.2.2` is blacklisted and it's outside allowed time)
```
# sudo dig +short youtube.com @127.0.0.1 -b 10.0.2.2
;; UDP setup with 127.0.0.1#53(127.0.0.1) for youtube.com failed: address not available.
;; no servers could be reached
;; UDP setup with 127.0.0.1#53(127.0.0.1) for youtube.com failed: address not available.
;; no servers could be reached
;; UDP setup with 127.0.0.1#53(127.0.0.1) for youtube.com failed: address not available.
;; no servers could be reached
```

## Positive test (domain `youtube.com` from localhost)
```
# sudo dig +short youtube.com @127.0.0.1
142.251.141.174
```

## How to list cached DNS entries
```
unbound-control dump_cache | grep -E "IN[[:space:]]+A[[:space:]]"
```





