# unbound-parental-control
Simple script to install unbound on raspberry with parental control

## Install Unbound and setup the local-lan 

```sh
sudo ./install-unbound.sh ./conf/local-lan.txt
```

## Add parental control

```sh
sudo ./add-parental-control.sh ./conf/jonas.ini
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


## Remove parental control

```sh
sudo ./add-parental-control.sh ./conf/jonas.ini
```



