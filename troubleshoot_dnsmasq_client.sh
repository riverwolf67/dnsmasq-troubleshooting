#!/bin/bash

#############################################
# DNSMasq Client Troubleshooting Script
# This script performs comprehensive DNS client checks
# Run with: sudo ./troubleshoot_dnsmasq_client.sh [DNS_SERVER_IP]
#############################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default DNS server (can be overridden by command line argument)
DNS_SERVER="${1:-}"

# Log file for detailed output
LOG_FILE="/tmp/dnsmasq_client_troubleshoot_$(date +%Y%m%d_%H%M%S).log"

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

# Check if running as root (some checks require root)
check_privileges() {
    if [[ $EUID -ne 0 ]]; then
        print_status "WARNING" "Some checks require root privileges. Run with sudo for complete diagnostics."
    fi
}

# System information
gather_system_info() {
    print_status "HEADER" "SYSTEM INFORMATION"
    print_status "INFO" "Hostname: $(hostname -f)"
    print_status "INFO" "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    print_status "INFO" "Kernel: $(uname -r)"
    print_status "INFO" "Date: $(date)"

    if [[ -n "$DNS_SERVER" ]]; then
        print_status "INFO" "Testing DNS Server: $DNS_SERVER"
    else
        print_status "INFO" "Testing system-configured DNS servers"
    fi
}

# Check DNS client tools
check_dns_tools() {
    print_status "HEADER" "DNS TOOLS CHECK"

    local tools=("dig" "nslookup" "host" "drill" "systemd-resolve")
    local installed=0

    for tool in "${tools[@]}"; do
        if command -v $tool &> /dev/null; then
            print_status "OK" "$tool is installed"
            installed=$((installed + 1))
        else
            print_status "INFO" "$tool is not installed"
        fi
    done

    if [[ $installed -eq 0 ]]; then
        print_status "ERROR" "No DNS testing tools found!"
        print_status "INFO" "Install dig with: apt-get install dnsutils (Debian/Ubuntu) or yum install bind-utils (RHEL/CentOS)"
        return 1
    fi
}

# Check network configuration
check_network_config() {
    print_status "HEADER" "NETWORK CONFIGURATION"

    # Check network interfaces
    print_status "INFO" "Network interfaces:"
    ip -br addr show | tee -a "$LOG_FILE"

    # Check default gateway
    local gateway=$(ip route | grep default | awk '{print $3}')
    if [[ -n "$gateway" ]]; then
        print_status "OK" "Default gateway: $gateway"

        # Test gateway connectivity
        if ping -c 1 -W 2 $gateway &> /dev/null; then
            print_status "OK" "Gateway is reachable"
        else
            print_status "ERROR" "Cannot reach gateway"
        fi
    else
        print_status "ERROR" "No default gateway configured"
    fi

    # Check MTU settings
    print_status "INFO" "MTU settings:"
    ip link show | grep mtu | tee -a "$LOG_FILE"
}

# Check DNS configuration
check_dns_config() {
    print_status "HEADER" "DNS CONFIGURATION"

    # Check /etc/resolv.conf
    if [[ -f /etc/resolv.conf ]]; then
        print_status "OK" "/etc/resolv.conf exists"

        # Check if it's a symlink (systemd-resolved)
        if [[ -L /etc/resolv.conf ]]; then
            local target=$(readlink -f /etc/resolv.conf)
            print_status "INFO" "/etc/resolv.conf is a symlink to: $target"

            if [[ "$target" == *"systemd"* ]]; then
                print_status "INFO" "System is using systemd-resolved"
            fi
        fi

        print_status "INFO" "Current DNS servers:"
        grep -E "^nameserver" /etc/resolv.conf | while read line; do
            echo "  - $line" | tee -a "$LOG_FILE"
        done

        # Check search domains
        local search=$(grep -E "^search|^domain" /etc/resolv.conf)
        if [[ -n "$search" ]]; then
            print_status "INFO" "Search domains configured:"
            echo "  - $search" | tee -a "$LOG_FILE"
        fi
    else
        print_status "ERROR" "/etc/resolv.conf not found"
    fi

    # Check systemd-resolved if active
    if systemctl is-active systemd-resolved &> /dev/null; then
        print_status "INFO" "systemd-resolved is active"

        if command -v resolvectl &> /dev/null; then
            print_status "INFO" "DNS configuration via systemd-resolved:"
            resolvectl status | head -20 | tee -a "$LOG_FILE"
        elif command -v systemd-resolve &> /dev/null; then
            systemd-resolve --status | head -20 | tee -a "$LOG_FILE"
        fi
    fi

    # Check NetworkManager configuration
    if [[ -d /etc/NetworkManager ]]; then
        print_status "INFO" "NetworkManager is installed"

        if [[ -f /etc/NetworkManager/NetworkManager.conf ]]; then
            local dns_backend=$(grep -E "^dns=" /etc/NetworkManager/NetworkManager.conf)
            if [[ -n "$dns_backend" ]]; then
                print_status "INFO" "NetworkManager DNS backend: $dns_backend"
            fi
        fi
    fi
}

# Test DNS connectivity
test_dns_connectivity() {
    print_status "HEADER" "DNS CONNECTIVITY TESTS"

    # Determine DNS servers to test
    local dns_servers=()

    if [[ -n "$DNS_SERVER" ]]; then
        dns_servers+=("$DNS_SERVER")
    else
        # Get system DNS servers
        while IFS= read -r line; do
            local server=$(echo "$line" | awk '{print $2}')
            dns_servers+=("$server")
        done < <(grep -E "^nameserver" /etc/resolv.conf 2>/dev/null)
    fi

    if [[ ${#dns_servers[@]} -eq 0 ]]; then
        print_status "ERROR" "No DNS servers configured"
        return 1
    fi

    # Test each DNS server
    for server in "${dns_servers[@]}"; do
        print_status "INFO" "Testing DNS server: $server"

        # Test TCP port 53
        if timeout 2 nc -zv $server 53 &> /dev/null; then
            print_status "OK" "TCP port 53 is open on $server"
        else
            print_status "WARNING" "TCP port 53 is not accessible on $server"
        fi

        # Test UDP port 53 (using dig)
        if command -v dig &> /dev/null; then
            if timeout 2 dig @$server +short google.com &> /dev/null; then
                print_status "OK" "UDP port 53 is working on $server"
            else
                print_status "ERROR" "UDP port 53 is not working on $server"
            fi
        fi

        # Test ICMP connectivity
        if ping -c 1 -W 2 $server &> /dev/null; then
            print_status "OK" "Can ping DNS server $server"
        else
            print_status "WARNING" "Cannot ping DNS server $server (may be blocked)"
        fi
    done
}

# Test DNS resolution
test_dns_resolution() {
    print_status "HEADER" "DNS RESOLUTION TESTS"

    local test_domains=("google.com" "cloudflare.com" "github.com" "localhost")
    local dns_servers=()

    if [[ -n "$DNS_SERVER" ]]; then
        dns_servers+=("$DNS_SERVER")
    else
        # Get system DNS servers
        while IFS= read -r line; do
            local server=$(echo "$line" | awk '{print $2}')
            dns_servers+=("$server")
        done < <(grep -E "^nameserver" /etc/resolv.conf 2>/dev/null)
    fi

    # Test with each DNS server
    for server in "${dns_servers[@]}"; do
        print_status "INFO" "Testing resolution via $server:"

        for domain in "${test_domains[@]}"; do
            if command -v dig &> /dev/null; then
                local result=$(timeout 2 dig @$server +short $domain 2>/dev/null | head -1)
                if [[ -n "$result" ]]; then
                    print_status "OK" "$domain → $result"
                else
                    print_status "ERROR" "$domain → FAILED"
                fi
            elif command -v nslookup &> /dev/null; then
                if timeout 2 nslookup $domain $server &> /dev/null; then
                    print_status "OK" "$domain → Resolved"
                else
                    print_status "ERROR" "$domain → FAILED"
                fi
            elif command -v host &> /dev/null; then
                if timeout 2 host $domain $server &> /dev/null; then
                    print_status "OK" "$domain → Resolved"
                else
                    print_status "ERROR" "$domain → FAILED"
                fi
            fi
        done
    done

    # Test reverse DNS
    print_status "INFO" "Testing reverse DNS lookup:"
    local my_ip=$(ip route get 1 | awk '{print $7; exit}')
    if [[ -n "$my_ip" ]]; then
        if command -v dig &> /dev/null; then
            local ptr=$(dig +short -x $my_ip 2>/dev/null)
            if [[ -n "$ptr" ]]; then
                print_status "OK" "Reverse lookup for $my_ip: $ptr"
            else
                print_status "INFO" "No reverse DNS for $my_ip"
            fi
        fi
    fi
}

# Test DNS response times
test_response_times() {
    print_status "HEADER" "DNS RESPONSE TIME TESTS"

    local dns_servers=()

    if [[ -n "$DNS_SERVER" ]]; then
        dns_servers+=("$DNS_SERVER")
    else
        # Get system DNS servers
        while IFS= read -r line; do
            local server=$(echo "$line" | awk '{print $2}')
            dns_servers+=("$server")
        done < <(grep -E "^nameserver" /etc/resolv.conf 2>/dev/null)
    fi

    for server in "${dns_servers[@]}"; do
        print_status "INFO" "Testing response time for $server:"

        if command -v dig &> /dev/null; then
            # Perform multiple queries and calculate average
            local total_time=0
            local successful_queries=0

            for i in {1..5}; do
                local start_time=$(date +%s%N)
                if timeout 2 dig @$server google.com +short &> /dev/null; then
                    local end_time=$(date +%s%N)
                    local query_time=$(( ($end_time - $start_time) / 1000000 ))
                    total_time=$((total_time + query_time))
                    successful_queries=$((successful_queries + 1))
                    echo "  Query $i: ${query_time}ms" | tee -a "$LOG_FILE"
                else
                    echo "  Query $i: FAILED" | tee -a "$LOG_FILE"
                fi
            done

            if [[ $successful_queries -gt 0 ]]; then
                local avg_time=$((total_time / successful_queries))
                if [[ $avg_time -lt 50 ]]; then
                    print_status "OK" "Average response time: ${avg_time}ms (Excellent)"
                elif [[ $avg_time -lt 100 ]]; then
                    print_status "OK" "Average response time: ${avg_time}ms (Good)"
                elif [[ $avg_time -lt 500 ]]; then
                    print_status "WARNING" "Average response time: ${avg_time}ms (Slow)"
                else
                    print_status "ERROR" "Average response time: ${avg_time}ms (Very slow)"
                fi
            else
                print_status "ERROR" "All queries failed"
            fi
        fi
    done
}

# Check for DNS hijacking
check_dns_hijacking() {
    print_status "HEADER" "DNS HIJACKING CHECK"

    # Test with a non-existent domain
    local test_domain="this-domain-definitely-does-not-exist-$(date +%s).com"

    if command -v dig &> /dev/null; then
        local result=$(dig +short $test_domain 2>/dev/null)
        if [[ -n "$result" ]]; then
            print_status "WARNING" "Possible DNS hijacking detected!"
            print_status "WARNING" "Non-existent domain resolved to: $result"
            print_status "INFO" "Your ISP or DNS provider may be hijacking NXDOMAIN responses"
        else
            print_status "OK" "No DNS hijacking detected"
        fi
    fi

    # Test common hijacking patterns
    print_status "INFO" "Testing for ISP DNS manipulation..."
    local known_ip="8.8.8.8"  # Google DNS
    if command -v dig &> /dev/null; then
        local resolved=$(dig +short google-public-dns-a.google.com)
        if [[ "$resolved" == "$known_ip" ]]; then
            print_status "OK" "DNS responses appear unmodified"
        else
            print_status "WARNING" "Unexpected response for known domain"
        fi
    fi
}

# Check DNSSEC validation
check_dnssec() {
    print_status "HEADER" "DNSSEC VALIDATION CHECK"

    if command -v dig &> /dev/null; then
        # Test a known DNSSEC-signed domain
        print_status "INFO" "Testing DNSSEC validation..."

        # Check if DNSSEC validation is available
        local ad_flag=$(dig +dnssec cloudflare.com | grep -c "flags:.*ad")
        if [[ $ad_flag -gt 0 ]]; then
            print_status "OK" "DNSSEC validation is available"
        else
            print_status "INFO" "DNSSEC validation may not be enabled"
        fi

        # Test a known bad DNSSEC domain
        local fail_test=$(dig +dnssec dnssec-failed.org 2>/dev/null | grep -c "SERVFAIL")
        if [[ $fail_test -gt 0 ]]; then
            print_status "OK" "DNSSEC validation is working (bad signatures detected)"
        else
            print_status "INFO" "DNSSEC validation may not be fully functional"
        fi
    else
        print_status "INFO" "dig not available - skipping DNSSEC tests"
    fi
}

# Check local hosts file
check_hosts_file() {
    print_status "HEADER" "LOCAL HOSTS FILE CHECK"

    if [[ -f /etc/hosts ]]; then
        print_status "OK" "/etc/hosts file exists"

        local entries=$(grep -v "^#" /etc/hosts | grep -v "^$" | wc -l)
        print_status "INFO" "Active entries in /etc/hosts: $entries"

        # Check for localhost entries
        if grep -q "127.0.0.1.*localhost" /etc/hosts; then
            print_status "OK" "localhost entry is configured"
        else
            print_status "WARNING" "localhost entry missing in /etc/hosts"
        fi

        # Show custom entries (non-localhost)
        local custom=$(grep -v "^#" /etc/hosts | grep -v "localhost" | grep -v "^$" | head -5)
        if [[ -n "$custom" ]]; then
            print_status "INFO" "Custom hosts entries (first 5):"
            echo "$custom" | while read line; do
                echo "  - $line" | tee -a "$LOG_FILE"
            done
        fi
    else
        print_status "ERROR" "/etc/hosts file not found"
    fi
}

# Generate recommendations
generate_recommendations() {
    print_status "HEADER" "RECOMMENDATIONS"

    echo -e "\nBased on the checks performed, here are some recommendations:" | tee -a "$LOG_FILE"
    echo "────────────────────────────────────────────────────────────" | tee -a "$LOG_FILE"

    # Check if DNS servers are configured
    if ! grep -q "^nameserver" /etc/resolv.conf 2>/dev/null; then
        echo "• Configure DNS servers in /etc/resolv.conf or network settings" | tee -a "$LOG_FILE"
        echo "  Example: echo 'nameserver 8.8.8.8' | sudo tee -a /etc/resolv.conf" | tee -a "$LOG_FILE"
    fi

    # Check for slow response times
    echo "• If experiencing slow DNS:" | tee -a "$LOG_FILE"
    echo "  - Try using public DNS servers (8.8.8.8, 1.1.1.1)" | tee -a "$LOG_FILE"
    echo "  - Consider running a local DNS cache (dnsmasq, unbound)" | tee -a "$LOG_FILE"
    echo "  - Check network latency to DNS servers" | tee -a "$LOG_FILE"

    # DNSSEC recommendations
    echo "• For better security:" | tee -a "$LOG_FILE"
    echo "  - Enable DNSSEC validation if not already enabled" | tee -a "$LOG_FILE"
    echo "  - Use DNS-over-HTTPS (DoH) or DNS-over-TLS (DoT)" | tee -a "$LOG_FILE"

    # Troubleshooting commands
    echo "" | tee -a "$LOG_FILE"
    echo "Useful troubleshooting commands:" | tee -a "$LOG_FILE"
    echo "  - dig @$DNS_SERVER example.com" | tee -a "$LOG_FILE"
    echo "  - nslookup example.com $DNS_SERVER" | tee -a "$LOG_FILE"
    echo "  - tcpdump -i any -n port 53" | tee -a "$LOG_FILE"
    echo "  - systemd-resolve --flush-caches" | tee -a "$LOG_FILE"

    echo "" | tee -a "$LOG_FILE"
    echo "For more detailed analysis, check the log file: $LOG_FILE" | tee -a "$LOG_FILE"
}

# Main execution
main() {
    echo "DNSMasq Client Troubleshooting Script"
    echo "======================================"

    if [[ -n "$1" ]]; then
        echo "Testing against DNS server: $1"
    else
        echo "Testing system-configured DNS servers"
        echo "Usage: $0 [DNS_SERVER_IP]"
    fi

    echo "Log file: $LOG_FILE"
    echo ""

    check_privileges
    gather_system_info
    check_dns_tools
    check_network_config
    check_dns_config
    test_dns_connectivity
    test_dns_resolution
    test_response_times
    check_dns_hijacking
    check_dnssec
    check_hosts_file
    generate_recommendations

    print_status "HEADER" "TROUBLESHOOTING COMPLETE"
    print_status "INFO" "Full log saved to: $LOG_FILE"
}

# Run main function
main "$@"