# Dnsmasq Troubleshooting Scripts

Comprehensive troubleshooting scripts for diagnosing and resolving Dnsmasq DNS server and client issues. These scripts provide automated diagnostics with detailed reporting to quickly identify DNS configuration problems, network issues, and performance bottlenecks.

## Quick Start

Run directly from GitHub without installation:

```bash
# Troubleshoot Dnsmasq server
curl -sSL https://raw.githubusercontent.com/riverwolf67/dnsmasq-troubleshooting/main/troubleshoot_dnsmasq_server.sh | sudo bash

# Troubleshoot DNS client
curl -sSL https://raw.githubusercontent.com/riverwolf67/dnsmasq-troubleshooting/main/troubleshoot_dnsmasq_client.sh | bash
```

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
  - [Server Troubleshooting](#server-troubleshooting)
  - [Client Troubleshooting](#client-troubleshooting)
- [Output Examples](#output-examples)
- [Script Details](#script-details)
- [Troubleshooting Guide](#troubleshooting-guide)
- [Contributing](#contributing)
- [License](#license)

## Features

### Key Capabilities
- **Automated Diagnostics**: Comprehensive system, network, and DNS checks
- **Color-Coded Output**: Easy visual identification of issues (✓ OK, ✗ ERROR, ! WARNING)
- **Detailed Logging**: Timestamped log files saved to `/tmp/` for further analysis
- **Smart Recommendations**: Automatic suggestions based on detected issues
- **Non-Destructive**: Read-only operations ensure system safety
- **Multi-Platform Support**: Works with systemd-resolved, NetworkManager, and traditional DNS configurations

### What Gets Checked

#### Server-Side Diagnostics
- Dnsmasq service status and configuration validation
- Network interface bindings and port listening status
- Firewall rules and DNS port accessibility
- Cache statistics and performance metrics
- DHCP configuration (if enabled)
- Recent logs and error analysis

#### Client-Side Diagnostics
- DNS resolver configuration (`/etc/resolv.conf`)
- Network connectivity to DNS servers
- DNS query response times and reliability
- DNSSEC validation capabilities
- DNS hijacking detection
- Local hosts file integrity

## Prerequisites

### Required Tools
- **Bash**: Version 4.0 or higher
- **Basic networking tools**: `ip`, `ping`, `nc` (netcat)
- **DNS tools** (at least one):
  - `dig` (recommended) - Install: `apt-get install dnsutils` or `yum install bind-utils`
  - `nslookup` - Usually pre-installed
  - `host` - Part of dnsutils package

### Permissions
- **Server script**: Requires root/sudo access for complete diagnostics
- **Client script**: Can run as regular user, but sudo provides more detailed information

## Installation

### Quick Install

```bash
# Clone the repository
git clone https://github.com/riverwolf67/dnsmasq-troubleshooting.git
cd dnsmasq-troubleshooting

# Make scripts executable
chmod +x troubleshoot_dnsmasq_server.sh
chmod +x troubleshoot_dnsmasq_client.sh
```

### Manual Download

```bash
# Download server script
wget https://raw.githubusercontent.com/riverwolf67/dnsmasq-troubleshooting/main/troubleshoot_dnsmasq_server.sh

# Download client script
wget https://raw.githubusercontent.com/riverwolf67/dnsmasq-troubleshooting/main/troubleshoot_dnsmasq_client.sh

# Make executable
chmod +x troubleshoot_dnsmasq_*.sh
```

### Run Directly from GitHub (No Installation)

Run the scripts directly without downloading:

#### Server Script (requires sudo)
```bash
# Test all interfaces (using curl)
curl -sSL https://raw.githubusercontent.com/riverwolf67/dnsmasq-troubleshooting/main/troubleshoot_dnsmasq_server.sh | sudo bash

# Test specific interfaces
curl -sSL https://raw.githubusercontent.com/riverwolf67/dnsmasq-troubleshooting/main/troubleshoot_dnsmasq_server.sh | sudo bash -s -- eth0 eth1

# List available interfaces
curl -sSL https://raw.githubusercontent.com/riverwolf67/dnsmasq-troubleshooting/main/troubleshoot_dnsmasq_server.sh | bash -s -- --list

# Or using wget
wget -qO- https://raw.githubusercontent.com/riverwolf67/dnsmasq-troubleshooting/main/troubleshoot_dnsmasq_server.sh | sudo bash
wget -qO- https://raw.githubusercontent.com/riverwolf67/dnsmasq-troubleshooting/main/troubleshoot_dnsmasq_server.sh | sudo bash -s -- eth0
```

#### Client Script
```bash
# Test system DNS (no sudo required)
curl -sSL https://raw.githubusercontent.com/riverwolf67/dnsmasq-troubleshooting/main/troubleshoot_dnsmasq_client.sh | bash

# Test specific DNS server
curl -sSL https://raw.githubusercontent.com/riverwolf67/dnsmasq-troubleshooting/main/troubleshoot_dnsmasq_client.sh | bash -s -- 192.168.1.1

# With sudo for complete diagnostics
curl -sSL https://raw.githubusercontent.com/riverwolf67/dnsmasq-troubleshooting/main/troubleshoot_dnsmasq_client.sh | sudo bash

# Using wget instead of curl
wget -qO- https://raw.githubusercontent.com/riverwolf67/dnsmasq-troubleshooting/main/troubleshoot_dnsmasq_client.sh | bash
```

**Note**: When running directly from GitHub, logs are still saved to `/tmp/` for later review.

## Usage

### Server Troubleshooting

Run on the Dnsmasq server machine:

```bash
# Run with sudo for complete diagnostics (tests all interfaces)
sudo ./troubleshoot_dnsmasq_server.sh

# Test specific network interfaces
sudo ./troubleshoot_dnsmasq_server.sh eth0              # Test only eth0
sudo ./troubleshoot_dnsmasq_server.sh eth0 eth1         # Test eth0 and eth1
sudo ./troubleshoot_dnsmasq_server.sh bond0 vlan100     # Test bond0 and vlan100

# List available network interfaces
sudo ./troubleshoot_dnsmasq_server.sh --list

# Show help and usage information
./troubleshoot_dnsmasq_server.sh --help

# Output will be displayed on screen and saved to log file
# Log location: /tmp/dnsmasq_server_troubleshoot_YYYYMMDD_HHMMSS.log
```

#### Interface Selection Features
- **Automatic Detection**: By default, tests all non-loopback interfaces
- **Specific Interface Testing**: Specify one or more interfaces to test only those
- **Interface Validation**: Checks if specified interfaces exist before testing
- **Performance Metrics**: Shows DNS response times per interface
- **IPv4 Detection**: Automatically skips interfaces without IPv4 addresses

### Client Troubleshooting

Run on client machines experiencing DNS issues:

```bash
# Test system-configured DNS servers
./troubleshoot_dnsmasq_client.sh

# Test specific DNS server
./troubleshoot_dnsmasq_client.sh 192.168.1.1

# Run with sudo for additional network diagnostics
sudo ./troubleshoot_dnsmasq_client.sh
```

## Output Examples

### Successful Check
```
[✓] dnsmasq service is active
[✓] Configuration syntax is valid
[✓] DNS port 53 is listening
[✓] Local DNS resolution working
```

### Issue Detection
```
[✗] dnsmasq service is not active
[!] No upstream servers configured (using system resolv.conf)
[✗] Cannot reach upstream server 8.8.8.8
[!] Query response time: 523ms (Very slow)
```

## Script Details

### troubleshoot_dnsmasq_server.sh

Performs comprehensive server-side diagnostics:

1. **System Information**
   - Hostname, OS version, kernel, uptime
   - Dnsmasq installation and version

2. **Service Status**
   - systemd service state and enablement
   - Recent service activity from journals

3. **Configuration Analysis**
   - Syntax validation
   - Listen addresses and interfaces
   - Upstream DNS servers
   - Cache size settings
   - DHCP ranges (if configured)

4. **Network Checks**
   - Interface configuration
   - Port 53 TCP/UDP listening status
   - Firewall rules (ufw, iptables, firewalld)

5. **Performance Metrics**
   - CPU and memory usage
   - Query response times
   - Cache hit statistics
   - Current connection count

6. **Log Analysis**
   - Recent errors and warnings
   - Service restart patterns

### troubleshoot_dnsmasq_client.sh

Performs client-side DNS diagnostics:

1. **DNS Configuration**
   - `/etc/resolv.conf` analysis
   - systemd-resolved status
   - NetworkManager DNS settings

2. **Network Connectivity**
   - Interface configuration
   - Gateway reachability
   - DNS server connectivity (TCP/UDP port 53)

3. **Resolution Testing**
   - Multiple domain lookups
   - Reverse DNS capability
   - Response time analysis (5-query average)

4. **Security Checks**
   - DNS hijacking detection
   - DNSSEC validation testing
   - Local hosts file integrity

5. **Troubleshooting Tools**
   - Available DNS tools inventory
   - Recommendations for missing tools

## Troubleshooting Guide

### Common Issues and Solutions

#### Server Issues

| Problem | Possible Cause | Solution |
|---------|---------------|----------|
| Service not active | Crash or not started | `sudo systemctl start dnsmasq` |
| Port 53 in use | Another DNS service running | Check with `ss -tuln | grep :53` |
| Configuration syntax error | Typo in config file | Run `dnsmasq --test` to find error |
| Firewall blocking | Restrictive firewall rules | Open port 53: `ufw allow 53` |

#### Client Issues

| Problem | Possible Cause | Solution |
|---------|---------------|----------|
| No DNS servers configured | Empty `/etc/resolv.conf` | Add `nameserver 8.8.8.8` |
| Slow resolution | Distant DNS server | Use local DNS or cache |
| DNS hijacking | ISP interference | Use DNS-over-HTTPS |
| DNSSEC failures | Validation issues | Check system time accuracy |

### Performance Tuning

#### Cache Optimization
```bash
# Increase cache size in /etc/dnsmasq.conf
cache-size=10000

# Enable DNSSEC validation
dnssec
trust-anchor=...
```

#### Network Optimization
```bash
# Reduce DNS timeout
echo "options timeout:1" >> /etc/resolv.conf

# Add multiple nameservers
echo "nameserver 1.1.1.1" >> /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf
```

## Advanced Usage

### Automation and Monitoring

#### Cron Job for Regular Checks
```bash
# Add to crontab for hourly checks
0 * * * * /path/to/troubleshoot_dnsmasq_server.sh > /var/log/dnsmasq_check.log 2>&1
```

#### Integration with Monitoring Systems
```bash
# Parse output for monitoring
./troubleshoot_dnsmasq_server.sh | grep -c "ERROR"
```

### Custom Modifications

The scripts can be customized by modifying these variables at the top of each file:

```bash
# Change log location
LOG_FILE="/var/log/dnsmasq_troubleshoot.log"

# Modify test domains
test_domains=("example.com" "yourcompany.com")

# Adjust timeout values
timeout_seconds=5
```

## Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for:

- Bug fixes
- New diagnostic checks
- Platform-specific improvements
- Documentation updates

### Development

```bash
# Test syntax without execution
bash -n troubleshoot_dnsmasq_server.sh

# Run in debug mode
bash -x troubleshoot_dnsmasq_server.sh
```

## Security Considerations

- Scripts perform read-only operations
- No system modifications are made
- Sensitive information is not transmitted
- Log files may contain IP addresses and hostnames

## Compatibility

- **Operating Systems**: Linux (Debian, Ubuntu, RHEL, CentOS, Fedora, Arch)
- **Dnsmasq Versions**: 2.x and higher
- **Shell**: Bash 4.0+
- **Init Systems**: systemd, SysV init

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Dnsmasq project for excellent DNS/DHCP server software
- Community contributors and testers
- Open source DNS diagnostic tools

## Support

For issues, questions, or suggestions:
1. Check the [Troubleshooting Guide](#troubleshooting-guide)
2. Open an [Issue](https://github.com/riverwolf67/dnsmasq-troubleshooting/issues)
3. Consult Dnsmasq [documentation](https://thekelleys.org.uk/dnsmasq/doc.html)

---

