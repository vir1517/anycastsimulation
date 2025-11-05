#!/bin/bash

ANYCAST_IP="10.0.0.100"

echo "=== ANYCAST ROUTE MANAGER ==="

# Function to update routes based on server status
update_routes() {
    echo "Updating routes based on server status..."
    
    # Router1: Clear all anycast routes
    sudo docker exec clab-anycast-network-router1 ip route del $ANYCAST_IP/32 2>/dev/null || true
    
    # Router2: Clear all anycast routes  
    sudo docker exec clab-anycast-network-router2 ip route del $ANYCAST_IP/32 2>/dev/null || true
    
    # Add routes only for running servers
    for server in 1 2 3; do
        status=$(sudo docker exec clab-anycast-network-anycast-server$server ps aux | grep python | grep -v grep | wc -l)
        if [ $status -eq 1 ]; then
            echo "🟢 Server$server is RUNNING - adding route"
            if [ $server -eq 1 ]; then
                sudo docker exec clab-anycast-network-router1 ip route add $ANYCAST_IP/32 via 10.0.1.10 dev eth1
            elif [ $server -eq 2 ]; then
                sudo docker exec clab-anycast-network-router1 ip route add $ANYCAST_IP/32 via 10.0.2.10 dev eth2
            elif [ $server -eq 3 ]; then
                sudo docker exec clab-anycast-network-router2 ip route add $ANYCAST_IP/32 via 10.0.3.10 dev eth1
            fi
        else
            echo "🔴 Server$server is STOPPED - skipping route"
        fi
    done
    
    # Always add cross-router backup routes (they'll only work if the other router has active servers)
    sudo docker exec clab-anycast-network-router1 ip route add $ANYCAST_IP/32 via 10.0.10.2 dev eth4 metric 100
    sudo docker exec clab-anycast-network-router2 ip route add $ANYCAST_IP/32 via 10.0.10.1 dev eth3 metric 100
    
    echo "Route update complete!"
}

# Update routes immediately
update_routes

# Show current status
echo -e "\n=== CURRENT ROUTES ==="
echo "Router1:"
sudo docker exec clab-anycast-network-router1 ip route show | grep $ANYCAST_IP || echo "  No routes found"
echo "Router2:"
sudo docker exec clab-anycast-network-router2 ip route show | grep $ANYCAST_IP || echo "  No routes found"

echo -e "\n=== TESTING CONNECTIVITY ==="
for client in 1 2; do
    echo "Client$client:"
    for i in {1..3}; do
        response=$(sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 2 http://$ANYCAST_IP:8080 | head -1)
        echo "  Request $i: ${response:-FAILED}"
    done
done
