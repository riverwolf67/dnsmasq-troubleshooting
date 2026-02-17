#!/bin/bash

#############################################
# Dnsmasq Server Troubleshooting Script
# This script performs comprehensive checks on a dnsmasq server
# Usage: sudo ./troubleshoot_dnsmasq_server.sh [interface1] [interface2] ...
# Example: sudo ./troubleshoot_dnsmasq_server.sh eth0 eth1
# If no interfaces specified, all non-loopback interfaces will be tested
#############################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file for detailed output
LOG_FILE="/tmp/dnsmasq_server_troubleshoot_$(date +%Y%m%d_%H%M%S).log"

# Function to display usage
show_usage() {
    echo "Usage: sudo $0 [OPTIONS] [interface1] [interface2] ..."
    echo ""
    echo "OPTIONS:"
    echo "  -h, --help     Show this help message"
    echo "  -a, --all      Test all interfaces (default if no interfaces specified)"
    echo "  -l, --list     List available network interfaces and exit"
    echo ""
    echo "EXAMPLES:"
    echo "  sudo $0                    # Test all interfaces"
    echo "  sudo $0 eth0               # Test only eth0"
    echo "  sudo $0 eth0 eth1          # Test eth0 and eth1"
    echo "  sudo $0 --list             # Show available interfaces"
    echo ""
    echo "This script performs comprehensive Dnsmasq server diagnostics including:"
    echo "  - Service status and configuration validation"
    echo "  - Network interface and port checks"
    echo "  - DNS resolution tests on specified interfaces"
    echo "  - Performance metrics and log analysis"
    exit 0
}

# Function to list interfaces
list_interfaces() {
    echo "Available network interfaces:"
    echo "=============================="
    ip -o link show | awk -F': ' '{print $2}' | while IFS= read -r interface; do
        local ip
        ip=$(ip -4 addr show "$interface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        if [[ -n "$ip" ]]; then
            echo "  $interface: $ip"
        else
            echo "  $interface: (no IPv4 address)"
        fi
    done
    exit 0
}

# Parse command line options
INTERFACES_TO_TEST=()
for arg in "$@"; do
    case $arg in
        -h|--help)
            show_usage
            ;;
        -l|--list)
            list_interfaces
            ;;
        -a|--all)
            # Will test all interfaces (default behavior)
            INTERFACES_TO_TEST=()
            ;;
        -*)
            echo "Unknown option: $arg"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
        *)
            # Add interface to test list
            INTERFACES_TO_TEST+=("$arg")
            ;;
    esac
done

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "OK")
            echo -e "${GREEN}[✓]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[✗]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARNING")
            echo -e "${YELLOW}[!]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "INFO")
            echo -e "${BLUE}[i]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "HEADER")
            echo -e "\n${BLUE}═══════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
            echo -e "${BLUE}$message${NC}" | tee -a "$LOG_FILE"
            echo -e "${BLUE}═══════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
            ;;
    esac
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_status "ERROR" "This script must be run as root (use sudo)"
        exit 1
    fi
}

# System information
gather_system_info() {
    print_status "HEADER" "SYSTEM INFORMATION"
    print_status "INFO" "Hostname: $(hostname -f)"
    print_status "INFO" "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    print_status "INFO" "Kernel: $(uname -r)"
    print_status "INFO" "Date: $(date)"
    print_status "INFO" "Uptime: $(uptime -p)"

    # Show interface configuration summary
    if [[ ${#INTERFACES_TO_TEST[@]} -gt 0 ]]; then
        print_status "INFO" "Testing specific interfaces: ${INTERFACES_TO_TEST[*]}"
    else
        print_status "INFO" "Testing all available network interfaces"
    fi
}

# Check if dnsmasq is installed
check_dnsmasq_installed() {
    print_status "HEADER" "DNSMASQ INSTALLATION CHECK"

    if command -v dnsmasq &> /dev/null; then
        print_status "OK" "dnsmasq is installed"
        local version=$(dnsmasq --version 2>&1 | head -n1)
        print_status "INFO" "Version: $version"
    else
        print_status "ERROR" "dnsmasq is not installed"
        print_status "INFO" "Install with: apt-get install dnsmasq (Debian/Ubuntu) or yum install dnsmasq (RHEL/CentOS)"
        return 1
    fi
}

# Check dnsmasq service status
check_service_status() {
    print_status "HEADER" "SERVICE STATUS CHECK"

    if systemctl is-active dnsmasq &> /dev/null; then
        print_status "OK" "dnsmasq service is active"
    else
        print_status "ERROR" "dnsmasq service is not active"
        print_status "INFO" "Attempting to get service status..."
        systemctl status dnsmasq --no-pager | tee -a "$LOG_FILE"
    fi

    if systemctl is-enabled dnsmasq &> /dev/null; then
        print_status "OK" "dnsmasq service is enabled at boot"
    else
        print_status "WARNING" "dnsmasq service is not enabled at boot"
    fi

    # Check for recent restarts
    print_status "INFO" "Recent service activity:"
    journalctl -u dnsmasq --since "1 hour ago" --no-pager | tail -10 | tee -a "$LOG_FILE"
}

# Check configuration files
check_configuration() {
    print_status "HEADER" "CONFIGURATION CHECK"

    local config_file="/etc/dnsmasq.conf"
    local config_dir="/etc/dnsmasq.d"

    if [[ -f "$config_file" ]]; then
        print_status "OK" "Main configuration file exists: $config_file"

        # Test configuration syntax
        if dnsmasq --test 2>&1 | grep -q "syntax check OK"; then
            print_status "OK" "Configuration syntax is valid"
        else
            print_status "ERROR" "Configuration syntax error detected"
            dnsmasq --test 2>&1 | tee -a "$LOG_FILE"
        fi

        # Check key configuration parameters
        print_status "INFO" "Key configuration parameters:"
        echo "----------------------------------------" >> "$LOG_FILE"

        # Check listen addresses
        local listen_addr=$(grep -E "^listen-address=" "$config_file" 2>/dev/null)
        if [[ -n "$listen_addr" ]]; then
            print_status "INFO" "Listen addresses: $listen_addr"
        else
            print_status "WARNING" "No specific listen-address configured (listening on all interfaces)"
        fi

        # Check interface binding
        local interface=$(grep -E "^interface=" "$config_file" 2>/dev/null)
        if [[ -n "$interface" ]]; then
            print_status "INFO" "Bound interfaces: $interface"
        fi

        # Check upstream servers
        local servers=$(grep -E "^server=" "$config_file" 2>/dev/null)
        if [[ -n "$servers" ]]; then
            print_status "INFO" "Upstream DNS servers configured:"
            echo "$servers" | while read line; do
                echo "  - $line" | tee -a "$LOG_FILE"
            done
        else
            print_status "WARNING" "No upstream servers configured (using system resolv.conf)"
        fi

        # Check cache size
        local cache_size=$(grep -E "^cache-size=" "$config_file" 2>/dev/null | cut -d'=' -f2)
        if [[ -n "$cache_size" ]]; then
            print_status "INFO" "Cache size: $cache_size entries"
        else
            print_status "INFO" "Cache size: default (150 entries)"
        fi

        # Check DHCP configuration
        if grep -q "^dhcp-range=" "$config_file" 2>/dev/null; then
            print_status "INFO" "DHCP is configured"
            grep "^dhcp-range=" "$config_file" | while read line; do
                echo "  - $line" | tee -a "$LOG_FILE"
            done
        else
            print_status "INFO" "DHCP is not configured"
        fi

    else
        print_status "ERROR" "Configuration file not found: $config_file"
    fi

    if [[ -d "$config_dir" ]]; then
        local conf_count=$(ls -1 "$config_dir"/*.conf 2>/dev/null | wc -l)
        if [[ $conf_count -gt 0 ]]; then
            print_status "INFO" "Additional configuration files in $config_dir: $conf_count"
            ls -la "$config_dir"/*.conf | tee -a "$LOG_FILE"
        fi
    fi
}

# Check network connectivity
check_network() {
    print_status "HEADER" "NETWORK CONNECTIVITY CHECK"

    # Check network interfaces
    print_status "INFO" "Network interfaces:"
    ip -br addr show | tee -a "$LOG_FILE"

    # Check listening ports
    print_status "INFO" "DNSMasq listening ports:"
    ss -tuln | grep -E ':53\s|:67\s' | tee -a "$LOG_FILE"

    # Check if port 53 is accessible
    if ss -tuln | grep -q ':53\s'; then
        print_status "OK" "DNS port 53 is listening"
    else
        print_status "ERROR" "DNS port 53 is not listening"
    fi

    # Check firewall rules
    print_status "INFO" "Checking firewall rules..."
    if command -v ufw &> /dev/null; then
        if ufw status | grep -q "Status: active"; then
            print_status "WARNING" "UFW firewall is active"
            ufw status numbered | grep -E "53|67" | tee -a "$LOG_FILE"
        else
            print_status "INFO" "UFW firewall is inactive"
        fi
    fi

    if command -v iptables &> /dev/null; then
        local dns_rules=$(iptables -L -n | grep -E "dpt:53|dpt:67" | wc -l)
        if [[ $dns_rules -gt 0 ]]; then
            print_status "INFO" "Found $dns_rules iptables rules for DNS/DHCP"
            iptables -L -n | grep -E "dpt:53|dpt:67" | tee -a "$LOG_FILE"
        fi
    fi

    if command -v firewall-cmd &> /dev/null; then
        if firewall-cmd --state 2>/dev/null | grep -q "running"; then
            print_status "WARNING" "firewalld is active"
            firewall-cmd --list-services | tee -a "$LOG_FILE"
        fi
    fi
}

# Test DNS resolution
test_dns_resolution() {
    print_status "HEADER" "DNS RESOLUTION TESTS"

    # Test local resolution
    print_status "INFO" "Testing local DNS resolution (127.0.0.1)..."
    if dig @127.0.0.1 google.com +short &> /dev/null; then
        print_status "OK" "Local DNS resolution working"
        local result
        result=$(dig @127.0.0.1 google.com +short | head -1)
        print_status "INFO" "google.com resolves to: $result"
    else
        print_status "ERROR" "Local DNS resolution failed"
    fi

    # Determine which interfaces to test
    local interfaces_to_check=()

    if [[ ${#INTERFACES_TO_TEST[@]} -gt 0 ]]; then
        # Use user-specified interfaces
        interfaces_to_check=("${INTERFACES_TO_TEST[@]}")
        print_status "INFO" "Testing specified interfaces: ${interfaces_to_check[*]}"
    else
        # Use all non-loopback interfaces
        while IFS= read -r interface; do
            if [[ "$interface" != "lo" ]]; then
                interfaces_to_check+=("$interface")
            fi
        done < <(ip -o link show | awk -F': ' '{print $2}')
        print_status "INFO" "Testing all available interfaces (use -l to list or specify interfaces)"
    fi

    # Test resolution on each interface
    for interface in "${interfaces_to_check[@]}"; do
        # Check if interface exists
        if ! ip link show "$interface" &> /dev/null; then
            print_status "ERROR" "Interface $interface does not exist"
            continue
        fi

        local ip
        ip=$(ip -4 addr show "$interface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)

        if [[ -n "$ip" ]]; then
            print_status "INFO" "Testing DNS on interface $interface ($ip)..."
            if timeout 2 dig @"$ip" google.com +short &> /dev/null; then
                print_status "OK" "DNS working on $interface"

                # Show example resolution
                local resolved
                resolved=$(timeout 2 dig @"$ip" google.com +short | head -1)
                if [[ -n "$resolved" ]]; then
                    print_status "INFO" "  Resolution test: google.com → $resolved"
                fi

                # Test response time
                local start_time end_time response_time
                start_time=$(date +%s%N)
                timeout 2 dig @"$ip" google.com +short &> /dev/null
                end_time=$(date +%s%N)
                response_time=$(( (end_time - start_time) / 1000000 ))

                if [[ $response_time -lt 50 ]]; then
                    print_status "OK" "  Response time: ${response_time}ms (Excellent)"
                elif [[ $response_time -lt 200 ]]; then
                    print_status "OK" "  Response time: ${response_time}ms (Good)"
                else
                    print_status "WARNING" "  Response time: ${response_time}ms (Slow)"
                fi
            else
                print_status "WARNING" "DNS not responding on $interface ($ip)"
            fi
        else
            print_status "INFO" "Interface $interface has no IPv4 address - skipping"
        fi
    done

    # Test upstream DNS servers
    print_status "INFO" "Testing upstream DNS servers..."
    for server in 8.8.8.8 1.1.1.1; do
        if timeout 2 dig @$server google.com +short &> /dev/null; then
            print_status "OK" "Upstream server $server is reachable"
        else
            print_status "ERROR" "Cannot reach upstream server $server"
        fi
    done
}

# Check logs for errors
check_logs() {
    print_status "HEADER" "LOG ANALYSIS"

    print_status "INFO" "Recent dnsmasq log entries:"
    journalctl -u dnsmasq --since "10 minutes ago" --no-pager | tail -20 | tee -a "$LOG_FILE"

    print_status "INFO" "Checking for recent errors..."
    local error_count=$(journalctl -u dnsmasq --since "1 hour ago" --no-pager | grep -iE "error|fail|warn" | wc -l)
    if [[ $error_count -gt 0 ]]; then
        print_status "WARNING" "Found $error_count error/warning messages in the last hour"
        journalctl -u dnsmasq --since "1 hour ago" --no-pager | grep -iE "error|fail|warn" | tail -10 | tee -a "$LOG_FILE"
    else
        print_status "OK" "No recent errors found in logs"
    fi
}

# Check DNS cache statistics
check_cache_stats() {
    print_status "HEADER" "DNS CACHE STATISTICS"

    # Send SIGUSR1 to dnsmasq to dump stats
    local pid=$(pidof dnsmasq)
    if [[ -n "$pid" ]]; then
        print_status "INFO" "Requesting cache statistics (PID: $pid)..."
        kill -USR1 $pid 2>/dev/null
        sleep 1

        # Check system log for stats
        if command -v journalctl &> /dev/null; then
            journalctl -u dnsmasq --since "1 minute ago" | grep -A10 "cache size" | tee -a "$LOG_FILE"
        else
            tail -20 /var/log/syslog | grep -A10 "cache size" | tee -a "$LOG_FILE"
        fi
    else
        print_status "ERROR" "Cannot get cache stats - dnsmasq not running"
    fi
}

# Performance check
check_performance() {
    print_status "HEADER" "PERFORMANCE CHECK"

    # Check CPU and memory usage
    local pid=$(pidof dnsmasq)
    if [[ -n "$pid" ]]; then
        print_status "INFO" "DNSMasq process statistics (PID: $pid):"
        ps -p $pid -o pid,ppid,%cpu,%mem,rss,vsz,comm | tee -a "$LOG_FILE"

        # Check number of connections
        local connections=$(ss -tan | grep :53 | wc -l)
        print_status "INFO" "Current DNS connections: $connections"
    fi

    # Test query response time
    print_status "INFO" "Testing query response time..."
    local start_time=$(date +%s%N)
    dig @127.0.0.1 google.com +short &> /dev/null
    local end_time=$(date +%s%N)
    local response_time=$(( ($end_time - $start_time) / 1000000 ))

    if [[ $response_time -lt 50 ]]; then
        print_status "OK" "Query response time: ${response_time}ms (Good)"
    elif [[ $response_time -lt 200 ]]; then
        print_status "WARNING" "Query response time: ${response_time}ms (Slow)"
    else
        print_status "ERROR" "Query response time: ${response_time}ms (Very slow)"
    fi
}

# Generate recommendations
generate_recommendations() {
    print_status "HEADER" "RECOMMENDATIONS"

    echo -e "\nBased on the checks performed, here are some recommendations:" | tee -a "$LOG_FILE"
    echo "────────────────────────────────────────────────────────────" | tee -a "$LOG_FILE"

    # Check if service is running
    if ! systemctl is-active dnsmasq &> /dev/null; then
        echo "• Start the dnsmasq service: sudo systemctl start dnsmasq" | tee -a "$LOG_FILE"
    fi

    if ! systemctl is-enabled dnsmasq &> /dev/null; then
        echo "• Enable dnsmasq at boot: sudo systemctl enable dnsmasq" | tee -a "$LOG_FILE"
    fi

    # Check for configuration issues
    if ! dnsmasq --test 2>&1 | grep -q "syntax check OK"; then
        echo "• Fix configuration syntax errors: sudo dnsmasq --test" | tee -a "$LOG_FILE"
    fi

    # Check firewall
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        if ! ufw status | grep -q "53/"; then
            echo "• Open DNS port in firewall: sudo ufw allow 53" | tee -a "$LOG_FILE"
        fi
    fi

    echo "" | tee -a "$LOG_FILE"
    echo "For more detailed analysis, check the log file: $LOG_FILE" | tee -a "$LOG_FILE"
}

# Main execution
main() {
    echo "Dnsmasq Server Troubleshooting Script"
    echo "======================================"
    echo "Log file: $LOG_FILE"

    # Show which interfaces will be tested
    if [[ ${#INTERFACES_TO_TEST[@]} -gt 0 ]]; then
        echo "Interfaces to test: ${INTERFACES_TO_TEST[*]}"
    else
        echo "Testing all available interfaces (use -l to list or specify interfaces)"
    fi
    echo ""

    check_root
    gather_system_info
    check_dnsmasq_installed || exit 1
    check_service_status
    check_configuration
    check_network
    test_dns_resolution
    check_logs
    check_cache_stats
    check_performance
    generate_recommendations

    print_status "HEADER" "TROUBLESHOOTING COMPLETE"
    print_status "INFO" "Full log saved to: $LOG_FILE"
}

# Run main function
main