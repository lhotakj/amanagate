# unbound-parental-control
Simple script to install unbound on raspberry with parental control

## Install Unbound and setup the local-lan 
Install the unbound and sets the upstream servers to AdGuard DNS servers blocking ads and sets custom A records defined in the hosts like file
```sh
sudo ./install-unbound.sh <path to own hosts like file>
```

Example:
```sh
sudo ./install-unbound.sh ./conf/local-lan.txt
```

## Add parental control
```sh
sudo ./add-parental-control.sh <path to the ini file>
```

The ini file has to be in the following format:
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



