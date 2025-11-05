#!/bin/bash

ANYCAST_IP="10.0.0.100"

echo "=== QUICK ANYCAST TEST ==="

# Test 1: Basic connectivity
echo "1. Testing basic connectivity..."
for client in 1 2; do
    echo "Client$client to anycast IP:"
    sudo docker exec clab-anycast-network-client$client ping -c 2 -W 1 $ANYCAST_IP
    response=$(sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 2 http://$ANYCAST_IP:8080)
    echo "HTTP response: ${response:-FAILED}"
    echo
done

# Test 2: Show which servers are responding
echo "2. Identifying active servers..."
for client in 1 2; do
    echo "Client$client sees:"
    for i in {1..3}; do
        response=$(sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 2 http://$ANYCAST_IP:8080)
        echo "  Request $i: ${response:-FAILED}"
    done
    echo
done
