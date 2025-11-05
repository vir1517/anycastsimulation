#!/bin/bash

ANYCAST_IP="10.0.0.100"

echo "=== FIXING ANYCAST FAILOVER ==="

# Remove existing anycast routes
sudo docker exec clab-anycast-network-router1 ip route del $ANYCAST_IP/32 2>/dev/null || true
sudo docker exec clab-anycast-network-router2 ip route del $ANYCAST_IP/32 2>/dev/null || true

# Configure Router1 with multiple routes (Linux will try them in order)
echo "Configuring Router1 with failover routes..."
sudo docker exec clab-anycast-network-router1 ip route add $ANYCAST_IP/32 via 10.0.1.10 dev eth1
sudo docker exec clab-anycast-network-router1 ip route add $ANYCAST_IP/32 via 10.0.2.10 dev eth2
sudo docker exec clab-anycast-network-router1 ip route add $ANYCAST_IP/32 via 10.0.10.2 dev eth4

# Configure Router2 with multiple routes
echo "Configuring Router2 with failover routes..."
sudo docker exec clab-anycast-network-router2 ip route add $ANYCAST_IP/32 via 10.0.3.10 dev eth1
sudo docker exec clab-anycast-network-router2 ip route add $ANYCAST_IP/32 via 10.0.10.1 dev eth3

echo "=== FAILOVER CONFIGURATION COMPLETE ==="

# Test the new routing
echo -e "\nTesting new routing..."
for client in 1 2; do
    echo "Client$client:"
    for i in {1..5}; do
        response=$(sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 2 http://$ANYCAST_IP:8080 | head -1)
        echo "  Request $i: ${response:-FAILED}"
    done
done
