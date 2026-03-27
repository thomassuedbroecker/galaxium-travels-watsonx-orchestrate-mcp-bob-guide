#!/bin/bash

# Script to display all network interfaces and their IP addresses
# Useful for identifying host machine IP addresses for network configuration

# Function to display all IP addresses from all interfaces
display_all_ips() {
    echo "=========================================="
    echo "ALL NETWORK INTERFACES AND IP ADDRESSES"
    echo "=========================================="
    echo ""
    
    # Use ifconfig to get all interface information
    local ifconfig_output=$(ifconfig 2>/dev/null)
    
    if [ -z "$ifconfig_output" ]; then
        echo "Error: Failed to retrieve network interface information" >&2
        exit 1
    fi
    
    # Parse ifconfig output
    local current_interface=""
    local found_any=false
    
    while IFS= read -r line; do
        # Check if this is a new interface line (starts without whitespace)
        if [[ $line =~ ^([a-z0-9]+): ]]; then
            current_interface="${BASH_REMATCH[1]}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Interface: $current_interface"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        # Check for IPv4 address
        elif [[ $line =~ inet[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
            echo "  IPv4: ${BASH_REMATCH[1]}"
            found_any=true
        # Check for IPv6 address
        elif [[ $line =~ inet6[[:space:]]+([a-f0-9:]+) ]]; then
            echo "  IPv6: ${BASH_REMATCH[1]}"
            found_any=true
        # Check for netmask
        elif [[ $line =~ netmask[[:space:]]+([x0-9a-f]+) ]]; then
            echo "  Netmask: ${BASH_REMATCH[1]}"
        # Check for broadcast
        elif [[ $line =~ broadcast[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
            echo "  Broadcast: ${BASH_REMATCH[1]}"
        # Check for status
        elif [[ $line =~ status:[[:space:]]+(.+)$ ]]; then
            echo "  Status: ${BASH_REMATCH[1]}"
        fi
    done <<< "$ifconfig_output"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if [ "$found_any" = false ]; then
        echo "No IP addresses found on any interface"
        echo "Please ensure you are connected to a network"
    fi
    
    echo "=========================================="
}

# Display all IP addresses
display_all_ips

