# AmanaGate
AmanaGate is a lightweight, high-performance deployment framework for Unbound DNS, specifically optimized for resource-constrained environments like the Raspberry Pi Zero.

The name derives from the Arabic/Swahili word "Amana", representing trust or something held in safekeeping. True to its name, AmanaGate serves as a "Trust Gateway" for your home network, providing parents with granular control over digital boundaries without compromising privacy or performance.

## 🚀 Overview
AmanaGate transforms a standard Raspberry Pi into a dedicated recursive DNS resolver. By intercepting requests at the network level, it allows for the seamless management of access to gaming platforms (Roblox, Bloxio), social media, and streaming services like YouTube—all through a privacy-first, self-hosted architecture.

# Key Features
* Minimalist Footprint: Architected for low-memory devices; fully tested on Raspberry Pi Zero (512MB RAM).
* DietPi Optimized: Tailored for the DietPi ecosystem for maximum efficiency and stability.
* Privacy-Centric: Eliminates reliance on third-party commercial parental control suites and data-logging DNS providers.
* Recursive Resolution: Improves security by communicating directly with Root Nameservers.
* Custom DNS A record management: Allows you to refine own DNS records in a friendly `hosts` file format

🛠 Target Environment
_Hardware_: Raspberry Pi Series (Optimized for Zero/Zero W)
_OS_: DietPi (recommended) or any Debian-based distributions (Ubuntu, Kubuntu, etc.)
_Service_: Unbound DNS / cron

## 🚩 Basic Installation

### 1. Clone the Repository

```sh
cd /tmp
git clone https://github.com/lhotakj/unbound-parental-control.git
cd unbound-parental-control
```

### 2. Install Unbound and Configure Local Network

This script installs Unbound and configures upstream DNS servers to use [AdGuard DNS](https://adguard.com/en/adguard-dns/overview.html) for ad-blocking purposes. You can also define custom A records via a hosts-like file.

To install and set up Unbound:

```sh
sudo ./install-unbound.sh <host_file_path>
```

**Example:**
```sh
sudo ./install-unbound.sh ./conf/local-lan.txt
```
- `<host_file_path>` should point to a plaintext file formatted similarly to `/etc/hosts`, listing custom domain mappings.

### 3. Verify Local A Record Resolution

Test DNS resolution for a configured hostname to ensure the setup is functioning:

```sh
dig @localhost amd
```

Replace `amd` with any hostname you defined in your hosts file.

---

## ⛔ Parental Control

### Add Parental Control Rules

Add parental control rules using an INI configuration file. This file enables granular control over which domains are accessible from specific devices, based on cron-style schedules.

```sh
sudo ./add-parental-control.sh <config_file_path>
```

#### INI File Format

The INI file should follow this structure:

```ini
[metadata]
kid_name=<rule_name>
block_cron=<cron_expression_for_blocking>
allow_cron=<cron_expression_for_allowing>

[domains]
domain1.com
domain2.net
...

[devices]
10.0.0.2
10.0.0.3
...
```
- You may specify multiple `block_cron` and `allow_cron` rules to customize schedules, such as for weekdays and weekends.
- Domains should be listed one per line under `[domains]`.
- Device IPs should be listed one per line under `[devices]`.

**Example:**
```sh
sudo ./add-parental-control.sh ./conf/jonas.ini
```

### Remove Parental Control Rules

To remove previously configured parental control rules, run:

```sh
sudo ./add-parental-control.sh ./conf/jonas.ini
```

---

## 🪲 Debugging and Testing

### Testing Parental Blocking
Test blocking for a domain (e.g., `youtube.com`) from a restricted host IP (e.g., `10.0.2.2`), outside allowed hours:

```sh
sudo dig +short youtube.com @127.0.0.1 -b 10.0.2.2
```
Result:
```
;; UDP setup with 127.0.0.1#53(127.0.0.1) for youtube.com failed: address not available.
;; no servers could be reached
```

### Positive DNS Test

To verify that allowed domains resolve correctly (e.g., from localhost):

```sh
sudo dig +short youtube.com @127.0.0.1
```
Expected output:
```
142.251.141.174
```

### Viewing Cached DNS Entries

To list current cached DNS A records in Unbound:

```sh
unbound-control dump_cache | grep -E "IN[[:space:]]+A[[:space:]]"
```

---

## Additional Notes

- **Security:** Always ensure your Raspberry Pi’s OS and Unbound are up-to-date to mitigate vulnerabilities.
- **Customization:** You can extend domain and schedule lists as required. Multiple configuration files can be managed for different users and devices.
- **Support & Contributions:** Please open issues or pull requests on [GitHub](https://github.com/lhotakj/unbound-parental-control) for bug reports, enhancements, or feature requests.

---

**References**
- [Unbound DNS documentation](https://nlnetlabs.nl/documentation/unbound/)
- [AdGuard DNS](https://adguard.com/en/adguard-dns/overview.html)
- [DietPi](https://dietpi.com/)
