#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, and pipeline failures
IFS=$'\n\t'       # Stricter word splitting

# If anything below fails or the script is interrupted, block all traffic
# instead of leaving the container open
FIREWALL_OK=0
fail_closed() {
    if [ "$FIREWALL_OK" != 1 ]; then
        echo "ERROR: Firewall setup did not complete - blocking all traffic"
        for cmd in iptables ip6tables; do
            $cmd -P INPUT DROP || true
            $cmd -P FORWARD DROP || true
            $cmd -P OUTPUT DROP || true
            $cmd -F || true
            $cmd -A INPUT -i lo -j ACCEPT || true
            $cmd -A OUTPUT -o lo -j ACCEPT || true
        done
    fi
}
trap fail_closed EXIT
trap 'exit 1' INT TERM HUP

# Start the VS Code socket cleanup first, so it runs even if the firewall setup fails.
# setsid detaches it from sudo, so it runs purely as root and node can't signal it.
if ! pgrep -u root -f '^/bin/bash /usr/local/bin/socket-cleanup.sh$' >/dev/null; then
    setsid /usr/local/bin/socket-cleanup.sh </dev/null >/dev/null 2>&1 &
fi

# 1. Gather everything that needs the network BEFORE changing any rules

# Extract Docker DNS info before any flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Only the container's own resolver may be used for DNS
DNS_SERVERS=$(awk '$1 == "nameserver" {print $2}' /etc/resolv.conf)
if [ -z "$DNS_SERVERS" ]; then
    echo "ERROR: No nameserver found in /etc/resolv.conf"
    exit 1
fi
while read -r dns; do
    if [[ ! "$dns" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "ERROR: Invalid nameserver in /etc/resolv.conf: $dns"
        exit 1
    fi
done < <(echo "$DNS_SERVERS")

# Fetch GitHub meta information and aggregate their IP ranges
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s https://api.github.com/meta)
if [ -z "$gh_ranges" ]; then
    echo "ERROR: Failed to fetch GitHub IP ranges"
    exit 1
fi

if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
    echo "ERROR: GitHub API response missing required fields"
    exit 1
fi

GH_CIDRS=$(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)
while read -r cidr; do
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "ERROR: Invalid CIDR range from GitHub meta: $cidr"
        exit 1
    fi
done < <(echo "$GH_CIDRS")

# Resolve other allowed domains
DOMAIN_IPS=""
for domain in \
    "registry.npmjs.org" \
    "api.anthropic.com"; do
    echo "Resolving $domain..."
    ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
    if [ -z "$ips" ]; then
        echo "ERROR: Failed to resolve $domain"
        exit 1
    fi

    while read -r ip; do
        if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "ERROR: Invalid IP from DNS for $domain: $ip"
            exit 1
        fi
    done < <(echo "$ips")
    DOMAIN_IPS+="$ips"$'\n'
done

# 2. Block everything first, then add the allowlist
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT DROP

# Flush existing rules and delete existing ipsets
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ip6tables -F
ip6tables -X
ipset destroy allowed-domains 2>/dev/null || true

# Selectively restore ONLY internal Docker DNS resolution
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# Allow localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A OUTPUT -o lo -j ACCEPT

# Allow replies to connections we allowed
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow outbound DNS to the container's resolver only
while read -r dns; do
    echo "Allowing DNS to $dns"
    iptables -A OUTPUT -p udp -d "$dns" --dport 53 -j ACCEPT
done < <(echo "$DNS_SERVERS")

# Build the allowlist
ipset create allowed-domains hash:net
while read -r cidr; do
    echo "Adding GitHub range $cidr"
    ipset add -exist allowed-domains "$cidr"
done < <(echo "$GH_CIDRS")
while read -r ip; do
    echo "Adding $ip"
    ipset add -exist allowed-domains "$ip"
done < <(printf '%s' "$DOMAIN_IPS")

# Allow only HTTPS to allowed domains
iptables -A OUTPUT -p tcp --dport 443 -m set --match-set allowed-domains dst -j ACCEPT

# Explicitly REJECT all other outbound traffic for immediate feedback
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited
ip6tables -A OUTPUT -j REJECT --reject-with icmp6-adm-prohibited

echo "Firewall configuration complete"
echo "Verifying firewall rules..."
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://example.com"
    exit 1
else
    echo "Firewall verification passed - unable to reach https://example.com as expected"
fi

# Verify GitHub API access
if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - unable to reach https://api.github.com"
    exit 1
else
    echo "Firewall verification passed - able to reach https://api.github.com as expected"
fi

FIREWALL_OK=1
