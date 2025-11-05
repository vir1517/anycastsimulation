sudo docker exec clab-anycast-network-router1 ip addr add 10.0.1.1/24 dev eth1  # to server1
sudo docker exec clab-anycast-network-router1 ip addr add 10.0.2.1/24 dev eth2  # to server2
sudo docker exec clab-anycast-network-router1 ip addr add 192.168.1.1/24 dev eth3  # to client1
sudo docker exec clab-anycast-network-router1 ip addr add 10.0.10.1/24 dev eth4  # to router2

# Configure Router2 interfaces
echo "--- Configuring Router2 ---"
sudo docker exec clab-anycast-network-router2 ip addr add 10.0.3.1/24 dev eth1  # to server3
sudo docker exec clab-anycast-network-router2 ip addr add 192.168.2.1/24 dev eth2  # to client2
sudo docker exec clab-anycast-network-router2 ip addr add 10.0.10.2/24 dev eth3  # to router1

# Configure Anycast Servers
echo "--- Configuring Anycast Servers ---"
sudo docker exec clab-anycast-network-anycast-server1 ip addr add 10.0.1.10/24 dev eth1
sudo docker exec clab-anycast-network-anycast-server2 ip addr add 10.0.2.10/24 dev eth1
sudo docker exec clab-anycast-network-anycast-server3 ip addr add 10.0.3.10/24 dev eth1

# Configure Clients
echo "--- Configuring Clients ---"
sudo docker exec clab-anycast-network-client1 ip addr add 192.168.1.100/24 dev eth1
sudo docker exec clab-anycast-network-client2 ip addr add 192.168.2.100/24 dev eth1

echo "--- IPv4 Configuration Complete ---"
EOF

chmod +x configure-ipv4-addresses.sh
./configure-ipv4-addresses.sh
cat > setup-anycast-routing.sh << 'EOF'
#!/bin/bash

ANYCAST_IP="10.0.0.100"

echo "=== Setting Up Anycast Routing ==="

# Remove any existing anycast IPs
for server in 1 2 3; do
    sudo docker exec clab-anycast-network-anycast-server$server ip addr del $ANYCAST_IP/32 dev eth1 2>/dev/null || true
    sudo docker exec clab-anycast-network-anycast-server$server ip addr del $ANYCAST_IP/32 dev lo 2>/dev/null || true
done

# Add anycast IP to all servers
echo "--- Adding Anycast IP to Servers ---"
for server in 1 2 3; do
    sudo docker exec clab-anycast-network-anycast-server$server ip addr add $ANYCAST_IP/32 dev lo
    echo "Anycast IP $ANYCAST_100 added to anycast-server$server loopback"
done

# Configure routing on routers
echo "--- Configuring Router Routes ---"

# Enable IP forwarding
sudo docker exec clab-anycast-network-router1 bash -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
sudo docker exec clab-anycast-network-router2 bash -c "echo 1 > /proc/sys/net/ipv4/ip_forward"

# Clear any existing routes to anycast IP
sudo docker exec clab-anycast-network-router1 ip route del $ANYCAST_IP/32 2>/dev/null || true
sudo docker exec clab-anycast-network-router2 ip route del $ANYCAST_IP/32 2>/dev/null || true

# Add routes to anycast IP via servers
sudo docker exec clab-anycast-network-router1 ip route add $ANYCAST_IP/32 via 10.0.1.10 dev eth1
sudo docker exec clab-anycast-network-router1 ip route add $ANYCAST_IP/32 via 10.0.2.10 dev eth2
sudo docker exec clab-anycast-network-router2 ip route add $ANYCAST_IP/32 via 10.0.3.10 dev eth1

# Configure client routing
echo "--- Configuring Client Routes ---"

# Client1 routes anycast traffic via Router1
sudo docker exec clab-anycast-network-client1 ip route del $ANYCAST_IP/32 2>/dev/null || true
sudo docker exec clab-anycast-network-client1 ip route add $ANYCAST_IP/32 via 192.168.1.1 dev eth1

# Client2 routes anycast traffic via Router2
sudo docker exec clab-anycast-network-client2 ip route del $ANYCAST_IP/32 2>/dev/null || true
sudo docker exec clab-anycast-network-client2 ip route add $ANYCAST_IP/32 via 192.168.2.1 dev eth1

# Add default routes for clients
sudo docker exec clab-anycast-network-client1 ip route add default via 192.168.1.1 dev eth1
sudo docker exec clab-anycast-network-client2 ip route add default via 192.168.2.1 dev eth1

# Configure inter-router routing for anycast
sudo docker exec clab-anycast-network-router1 ip route add 192.168.2.0/24 via 10.0.10.2 dev eth4
sudo docker exec clab-anycast-network-router2 ip route add 192.168.1.0/24 via 10.0.10.1 dev eth3

echo "--- Anycast Routing Configuration Complete ---"
EOF

chmod +x setup-anycast-routing.sh
./setup-anycast-routing.sh
clear
echo "=== Verifying Network Configuration ==="
# Check all interfaces have IPv4 addresses
for container in router1 router2 client1 client2 anycast-server1 anycast-server2 anycast-server3; do     echo "--- $container IPv4 Addresses ---";     sudo docker exec clab-anycast-network-$container ip -4 addr show;     echo; done
# Check routing tables
for container in router1 router2 client1 client2; do     echo "--- $container Routing Table ---";     sudo docker exec clab-anycast-network-$container ip route show;     echo; done
clear
cat > restart-anycast-servers.sh << 'EOF'
#!/bin/bash

echo "=== Restarting Anycast HTTP Servers ==="

# Kill any existing servers
for server in 1 2 3; do
    sudo docker exec clab-anycast-network-anycast-server$server pkill -f "python3" || true
done

# Start HTTP servers on all anycast servers
for server in 1 2 3; do
    echo "Starting server on anycast-server$server"
    sudo docker exec -d clab-anycast-network-anycast-server$server bash -c 'cat > /tmp/anycast-server.py << "PYEOF"
from http.server import HTTPServer, BaseHTTPRequestHandler
import socket
import time

class AnycastHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        hostname = socket.gethostname()
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        response = f"Anycast Response from {hostname} (Server {socket.gethostname()[-1]})\n"
        self.wfile.write(response.encode())
        print(f"Request served by {hostname}")
    
    def log_message(self, format, *args):
        print(f"{socket.gethostname()}: {format % args}")

print(f"Starting anycast server on {socket.gethostname()}...")
server = HTTPServer(("0.0.0.0", 8080), AnycastHandler)
server.serve_forever()
PYEOF'
    
    sudo docker exec -d clab-anycast-network-anycast-server$server python3 /tmp/anycast-server.py
    sleep 1
done

echo "All anycast servers started"
EOF

chmod +x restart-anycast-servers.sh
./restart-anycast-servers.sh
clea
clear
echo "=== Testing Anycast Connectivity ==="
# Test from routers to anycast IP first
echo "--- Testing from Routers ---"
for router in 1 2; do     echo "Router$router to anycast IP:";     sudo docker exec clab-anycast-network-router$router ping -c 2 -W 1 10.0.0.100;     sudo docker exec clab-anycast-network-router$router curl -s --connect-timeout 2 http://10.0.0.100:8080 || echo "HTTP failed";     echo; done
# Test from clients
echo "--- Testing from Clients ---"
for client in 1 2; do     echo "Client$client to anycast IP:";     sudo docker exec clab-anycast-network-client$client ping -c 3 -W 1 10.0.0.100;     sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 3 http://10.0.0.100:8080 || echo "HTTP failed";     echo; done
clear
echo "=== Testing Anycast Connectivity ==="
# Test from routers to anycast IP first
echo "--- Testing from Routers ---"
for router in 1 2; do     echo "Router$router to anycast IP:";     sudo docker exec clab-anycast-network-router$router ping -c 2 -W 1 10.0.0.100;     sudo docker exec clab-anycast-network-router$router curl -s --connect-timeout 2 http://10.0.0.100:8080 || echo "HTTP failed";     echo; done
# Test from clients
echo "--- Testing from Clients ---"
for client in 1 2; do     echo "Client$client to anycast IP:";     sudo docker exec clab-anycast-network-client$client ping -c 3 -W 1 10.0.0.100;     sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 3 http://10.0.0.100:8080 || echo "HTTP failed";     echo; done
clear
ls
clear
cat > fix-client-connectivity.sh << 'EOF'
#!/bin/bash

ANYCAST_IP="10.0.0.100"

echo "=== Fixing Client Connectivity ==="

# First, ensure clients have proper default routes
echo "--- Configuring Client Default Routes ---"

# Client1 configuration
sudo docker exec clab-anycast-network-client1 ip route del default 2>/dev/null || true
sudo docker exec clab-anycast-network-client1 ip route add default via 192.168.1.1 dev eth1

# Client2 configuration
sudo docker exec clab-anycast-network-client2 ip route del default 2>/dev/null || true
sudo docker exec clab-anycast-network-client2 ip route add default via 192.168.2.1 dev eth1

# Ensure routers have proper routes back to clients
echo "--- Configuring Router Return Routes ---"

# Router1 needs route to Client2 network via Router2
sudo docker exec clab-anycast-network-router1 ip route del 192.168.2.0/24 2>/dev/null || true
sudo docker exec clab-anycast-network-router1 ip route add 192.168.2.0/24 via 10.0.10.2 dev eth4

# Router2 needs route to Client1 network via Router1
sudo docker exec clab-anycast-network-router2 ip route del 192.168.1.0/24 2>/dev/null || true
sudo docker exec clab-anycast-network-router2 ip route add 192.168.1.0/24 via 10.0.10.1 dev eth3

# Enable proxy ARP on routers to help with anycast routing
echo "--- Enabling Proxy ARP ---"
for router in 1 2; do
    sudo docker exec clab-anycast-network-router$router bash -c "echo 1 > /proc/sys/net/ipv4/conf/all/proxy_arp"
done

# Add specific anycast routes on clients (remove and re-add)
echo "--- Refreshing Anycast Routes ---"
for client in 1 2; do
    sudo docker exec clab-anycast-network-client$client ip route del $ANYCAST_IP/32 2>/dev/null || true
    if [ "$client" = "1" ]; then
        sudo docker exec clab-anycast-network-client1 ip route add $ANYCAST_IP/32 via 192.168.1.1 dev eth1
    else
        sudo docker exec clab-anycast-network-client2 ip route add $ANYCAST_IP/32 via 192.168.2.1 dev eth1
    fi
done

echo "--- Client Connectivity Fix Complete ---"
EOF

chmod +x fix-client-connectivity.sh
./fix-client-connectivity.sh
clear
echo "=== Step-by-Step Connectivity Test ==="
# Test 1: Client to gateway
echo "1. Testing client to gateway connectivity:"
for client in 1 2; do     if [ "$client" = "1" ]; then         GATEWAY="192.168.1.1";     else         GATEWAY="192.168.2.1";     fi;     echo "Client$client to gateway $GATEWAY:";     sudo docker exec clab-anycast-network-client$client ping -c 2 -W 1 $GATEWAY; done
# Test 2: Trace route to anycast IP
echo -e "\n2. Tracing route to anycast IP:"
for client in 1 2; do     echo "Client$client route to anycast:";     sudo docker exec clab-anycast-network-client$client ip route get 10.0.0.100; done
# Test 3: Test anycast connectivity
echo -e "\n3. Testing anycast connectivity:"
for client in 1 2; do     echo "Client$client to anycast IP:";     sudo docker exec clab-anycast-network-client$client ping -c 2 -W 1 10.0.0.100;     sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 2 http://10.0.0.100:8080 || echo "HTTP failed";     echo; done
clear
echo "=== Checking for Firewall/NAT Issues ==="
# Check if there are any iptables rules blocking traffic
for router in 1 2; do     echo "--- Router$router iptables ---";     sudo docker exec clab-anycast-network-router$router iptables -L -n -v || echo "iptables not available";     echo; done
# Flush any potentially problematic iptables rules
for router in 1 2; do     echo "Flushing iptables on Router$router:";     sudo docker exec clab-anycast-network-router$router iptables -F 2>/dev/null || true;     sudo docker exec clab-anycast-network-router$router iptables -t nat -F 2>/dev/null || true; done
lear
clear
echo "=== Checking for Firewall/NAT Issues ==="
# Check if there are any iptables rules blocking traffic
for router in 1 2; do     echo "--- Router$router iptables ---";     sudo docker exec clab-anycast-network-router$router iptables -L -n -v || echo "iptables not available";     echo; done
# Flush any potentially problematic iptables rules
for router in 1 2; do     echo "Flushing iptables on Router$router:";     sudo docker exec clab-anycast-network-router$router iptables -F 2>/dev/null || true;     sudo docker exec clab-anycast-network-router$router iptables -t nat -F 2>/dev/null || true; done
sudo docker ps
clear
docker ps
sudo docker ps
clear
echo "=== Testing Connectivity Between All Nodes ==="
# Test client to router connectivity
echo "1. Client to Router connectivity:"
for client in 1 2; do     if [ "$client" = "1" ]; then         ROUTER_IP="192.168.1.1";     else         ROUTER_IP="192.168.2.1";     fi;     echo "Client$client to Router:";     sudo docker exec clab-anycast-network-client$client ping -c 2 -W 1 $ROUTER_IP; done
# Test router to server connectivity
echo -e "\n2. Router to Server connectivity:"
echo "Router1 to Server1 (10.0.1.10):"
sudo docker exec clab-anycast-network-router1 ping -c 2 -W 1 10.0.1.10
echo "Router1 to Server2 (10.0.2.10):"
sudo docker exec clab-anycast-network-router1 ping -c 2 -W 1 10.0.2.10
echo "Router2 to Server3 (10.0.3.10):"
sudo docker exec clab-anycast-network-router2 ping -c 2 -W 1 10.0.3.10
# Test inter-router connectivity
echo -e "\n3. Inter-Router connectivity:"
echo "Router1 to Router2 (10.0.10.2):"
sudo docker exec clab-anycast-network-router1 ping -c 2 -W 1 10.0.10.2
echo "Router2 to Router1 (10.0.10.1):"
sudo docker exec clab-anycast-network-router2 ping -c 2 -W 1 10.0.10.1
clear
cat > comprehensive-routing-fix.sh << 'EOF'
#!/bin/bash

ANYCAST_IP="10.0.0.100"

echo "=== Comprehensive Routing Fix ==="

# First, let's verify the current state
echo "--- Current State Verification ---"
for client in 1 2; do
    echo "Client$client default route:"
    sudo docker exec clab-anycast-network-client$client ip route show | grep default || echo "No default route"
done

# Fix 1: Ensure proper default routes on clients
echo "--- Fixing Client Default Routes ---"
sudo docker exec clab-anycast-network-client1 ip route del default 2>/dev/null || true
sudo docker exec clab-anycast-network-client1 ip route add default via 192.168.1.1 dev eth1

sudo docker exec clab-anycast-network-client2 ip route del default 2>/dev/null || true
sudo docker exec clab-anycast-network-client2 ip route add default via 192.168.2.1 dev eth1

# Fix 2: Ensure routers have routes to client networks
echo "--- Fixing Router Routes to Client Networks ---"

# Router1 should know about Client2 network via Router2
sudo docker exec clab-anycast-network-router1 ip route del 192.168.2.0/24 2>/dev/null || true
sudo docker exec clab-anycast-network-router1 ip route add 192.168.2.0/24 via 10.0.10.2 dev eth4

# Router2 should know about Client1 network via Router1
sudo docker exec clab-anycast-network-router2 ip route del 192.168.1.0/24 2>/dev/null || true
sudo docker exec clab-anycast-network-router2 ip route add 192.168.1.0/24 via 10.0.10.1 dev eth3

# Fix 3: Ensure anycast routes are correct on routers
echo "--- Verifying Anycast Routes on Routers ---"

# Clear and re-add anycast routes
sudo docker exec clab-anycast-network-router1 ip route del $ANYCAST_IP/32 2>/dev/null || true
sudo docker exec clab-anycast-network-router1 ip route add $ANYCAST_IP/32 via 10.0.1.10 dev eth1
sudo docker exec clab-anycast-network-router1 ip route add $ANYCAST_IP/32 via 10.0.2.10 dev eth2

sudo docker exec clab-anycast-network-router2 ip route del $ANYCAST_IP/32 2>/dev/null || true
sudo docker exec clab-anycast-network-router2 ip route add $ANYCAST_IP/32 via 10.0.3.10 dev eth1

# Fix 4: Enable proxy ARP and IP forwarding
echo "--- Enabling Network Features ---"
for router in 1 2; do
    sudo docker exec clab-anycast-network-router$router bash -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
    sudo docker exec clab-anycast-network-router$router bash -c "echo 1 > /proc/sys/net/ipv4/conf/all/proxy_arp"
done

# Fix 5: Add specific anycast routes to clients
echo "--- Adding Anycast Routes to Clients ---"
for client in 1 2; do
    sudo docker exec clab-anycast-network-client$client ip route del $ANYCAST_IP/32 2>/dev/null || true
    if [ "$client" = "1" ]; then
        sudo docker exec clab-anycast-network-client1 ip route add $ANYCAST_IP/32 via 192.168.1.1 dev eth1
    else
        sudo docker exec clab-anycast-network-client2 ip route add $ANYCAST_IP/32 via 192.168.2.1 dev eth1
    fi
done

echo "--- Routing Fix Complete ---"
EOF

chmod +x comprehensive-routing-fix.sh
./comprehensive-routing-fix.sh
clear
echo "=== Testing Packet Flow ==="
# Install traceroute if not available
for client in 1 2; do     echo "Installing traceroute on client$client...";     sudo docker exec clab-anycast-network-client$client apt-get update > /dev/null 2>&1;     sudo docker exec clab-anycast-network-client$client apt-get install -y traceroute > /dev/null 2>&1 || echo "Traceroute install failed, continuing..."; done
echo "=== Final Connectivity Test ==="
# Test basic connectivity first
for client in 1 2; do     echo "--- Client$client Basic Tests ---";     if [ "$client" = "1" ]; then         GATEWAY="192.168.1.1";     else         GATEWAY="192.168.2.1";     fi         echo "Ping to gateway $GATEWAY:";     sudo docker exec clab-anycast-network-client$client ping -c 2 -W 1 $GATEWAY         echo "Ping to anycast IP 10.0.0.100:";     sudo docker exec clab-anycast-network-client$client ping -c 2 -W 1 10.0.0.100         echo "HTTP request to anycast:";     sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 3 http://10.0.0.100:8080 || echo "HTTP failed";     echo; done
clear
echo "=== Comprehensive Packet Debugging ==="
# Start packet capture on multiple points simultaneously
echo "Starting packet capture on all critical points..."
# Capture on Router1 client interface
sudo docker exec -d clab-anycast-network-router1 bash -c "tcpdump -i eth3 -n 'host 10.0.0.100 or host 192.168.1.100' -w /tmp/router1_eth3.pcap 2>/dev/null"
# Capture on Router1 server interfaces
sudo docker exec -d clab-anycast-network-router1 bash -c "tcpdump -i eth1 -n 'host 10.0.0.100' -w /tmp/router1_eth1.pcap 2>/dev/null"
sudo docker exec -d clab-anycast-network-router1 bash -c "tcpdump -i eth2 -n 'host 10.0.0.100' -w /tmp/router1_eth2.pcap 2>/dev/null"
# Capture on the servers
sudo docker exec -d clab-anycast-network-anycast-server1 bash -c "tcpdump -i any -n 'host 10.0.0.100' -w /tmp/server1.pcap 2>/dev/null"
# Make test requests from clients
echo "Making test requests from clients..."
sudo docker exec clab-anycast-network-client1 ping -c 3 10.0.0.100 &
sudo docker exec clab-anycast-network-client1 curl -s --connect-timeout 3 http://10.0.0.100:8080 &
sleep 5
# Stop all tcpdump processes
for container in router1 anycast-server1; do     sudo docker exec clab-anycast-network-$container pkill tcpdump 2>/dev/null || true; done
# Analyze the captures
echo "=== Packet Capture Analysis ==="
echo "Router1 eth3 (client side) packets:"
sudo docker exec clab-anycast-network-router1 tcpdump -n -r /tmp/router1_eth3.pcap 2>/dev/null | head -20 || echo "No packets captured"
echo "Router1 eth1 (server1 side) packets:"
sudo docker exec clab-anycast-network-router1 tcpdump -n -r /tmp/router1_eth1.pcap 2>/dev/null | head -20 || echo "No packets captured"
echo "Server1 packets:"
sudo docker exec clab-anycast-network-anycast-server1 tcpdump -n -r /tmp/server1.pcap 2>/dev/null | head -20 || echo "No packets captured"
clear
echo "=== Comprehensive Packet Debugging ==="
# Start packet capture on multiple points simultaneously
echo "Starting packet capture on all critical points..."
# Capture on Router1 client interface
sudo docker exec -d clab-anycast-network-router1 bash -c "tcpdump -i eth3 -n 'host 10.0.0.100 or host 192.168.1.100' -w /tmp/router1_eth3.pcap 2>/dev/null"
# Capture on Router1 server interfaces
sudo docker exec -d clab-anycast-network-router1 bash -c "tcpdump -i eth1 -n 'host 10.0.0.100' -w /tmp/router1_eth1.pcap 2>/dev/null"
sudo docker exec -d clab-anycast-network-router1 bash -c "tcpdump -i eth2 -n 'host 10.0.0.100' -w /tmp/router1_eth2.pcap 2>/dev/null"
# Capture on the servers
sudo docker exec -d clab-anycast-network-anycast-server1 bash -c "tcpdump -i any -n 'host 10.0.0.100' -w /tmp/server1.pcap 2>/dev/null"
# Make test requests from clients
echo "Making test requests from clients..."
sudo docker exec clab-anycast-network-client1 ping -c 3 10.0.0.100 &
sudo docker exec clab-anycast-network-client1 curl -s --connect-timeout 3 http://10.0.0.100:8080 &
sleep 5
# Stop all tcpdump processes
for container in router1 anycast-server1; do     sudo docker exec clab-anycast-network-$container pkill tcpdump 2>/dev/null || true; done
# Analyze the captures
echo "=== Packet Capture Analysis ==="
echo "Router1 eth3 (client side) packets:"
sudo docker exec clab-anycast-network-router1 tcpdump -n -r /tmp/router1_eth3.pcap 2>/dev/null | head -20 || echo "No packets captured"
echo "Router1 eth1 (server1 side) packets:"
sudo docker exec clab-anycast-network-router1 tcpdump -n -r /tmp/router1_eth1.pcap 2>/dev/null | head -20 || echo "No packets captured"
echo "Server1 packets:"
sudo docker exec clab-anycast-network-anycast-server1 tcpdump -n -r /tmp/server1.pcap 2>/dev/null | head -20 || echo "No packets capturedclear
clear
echo "=== Comprehensive Packet Debugging ==="
# Start packet capture on multiple points simultaneously
echo "Starting packet capture on all critical points..."
# Capture on Router1 client interface
sudo docker exec -d clab-anycast-network-router1 bash -c "tcpdump -i eth3 -n 'host 10.0.0.100 or host 192.168.1.100' -w /tmp/router1_eth3.pcap 2>/dev/null"
# Capture on Router1 server interfaces
sudo docker exec -d clab-anycast-network-router1 bash -c "tcpdump -i eth1 -n 'host 10.0.0.100' -w /tmp/router1_eth1.pcap 2>/dev/null"
sudo docker exec -d clab-anycast-network-router1 bash -c "tcpdump -i eth2 -n 'host 10.0.0.100' -w /tmp/router1_eth2.pcap 2>/dev/null"
# Capture on the servers
sudo docker exec -d clab-anycast-network-anycast-server1 bash -c "tcpdump -i any -n 'host 10.0.0.100' -w /tmp/server1.pcap 2>/dev/null"
# Make test requests from clients
echo "Making test requests from clients..."
sudo docker exec clab-anycast-network-client1 ping -c 3 10.0.0.100 &
sudo docker exec clab-anycast-network-client1 curl -s --connect-timeout 3 http://10.0.0.100:8080 &
sleep 5
# Stop all tcpdump processes
for container in router1 anycast-server1; do     sudo docker exec clab-anycast-network-$container pkill tcpdump 2>/dev/null || true; done
# Analyze the captures
echo "=== Packet Capture Analysis ==="
echo "Router1 eth3 (client side) packets:"
sudo docker exec clab-anycast-network-router1 tcpdump -n -r /tmp/router1_eth3.pcap 2>/dev/null | head -20 || echo "No packets captured"
echo "Router1 eth1 (server1 side) packets:"
sudo docker exec clab-anycast-network-router1 tcpdump -n -r /tmp/router1_eth1.pcap 2>/dev/null | head -20 || echo "No packets captured"
echo "Server1 packets:"
sudo docker exec clab-anycast-network-anycast-server1 tcpdump -n -r /tmp/server1.pcap 2>/dev/null | head -20 || echo "No packets captured"
clear
cat > fix-return-path.sh << 'EOF'
#!/bin/bash

echo "=== Fixing Return Path Routing ==="

# The problem: Servers are sending responses directly back to clients via their default route
# But they need to send responses back through the routers

# Configure servers to use routers as default gateway
echo "--- Configuring Server Default Routes ---"

# Server1 should use Router1 as gateway
sudo docker exec clab-anycast-network-anycast-server1 ip route del default 2>/dev/null || true
sudo docker exec clab-anycast-network-anycast-server1 ip route add default via 10.0.1.1 dev eth1

# Server2 should use Router1 as gateway  
sudo docker exec clab-anycast-network-anycast-server2 ip route del default 2>/dev/null || true
sudo docker exec clab-anycast-network-anycast-server2 ip route add default via 10.0.2.1 dev eth1

# Server3 should use Router2 as gateway
sudo docker exec clab-anycast-network-anycast-server3 ip route del default 2>/dev/null || true
sudo docker exec clab-anycast-network-anycast-server3 ip route add default via 10.0.3.1 dev eth1

# Add specific routes for client networks on servers
echo "--- Adding Client Network Routes to Servers ---"

# Server1 and Server2 need route to Client2 network via Router1
for server in 1 2; do
    sudo docker exec clab-anycast-network-anycast-server$server ip route add 192.168.2.0/24 via 10.0.${server}.1 dev eth1
done

# Server3 needs route to Client1 network via Router2
sudo docker exec clab-anycast-network-anycast-server3 ip route add 192.168.1.0/24 via 10.0.3.1 dev eth1

# Ensure routers know how to route between their own networks
echo "--- Configuring Router Internal Routing ---"

# Router1 needs to route between its own networks
sudo docker exec clab-anycast-network-router1 ip route add 192.168.1.0/24 dev eth3
sudo docker exec clab-anycast-network-router1 ip route add 192.168.2.0/24 via 10.0.10.2 dev eth4

# Router2 needs to route between its own networks
sudo docker exec clab-anycast-network-router2 ip route add 192.168.2.0/24 dev eth2
sudo docker exec clab-anycast-network-router2 ip route add 192.168.1.0/24 via 10.0.10.1 dev eth3

echo "--- Return Path Routing Fixed ---"
EOF

chmod +x fix-return-path.sh
./fix-return-path.sh
clear
echo "=== Testing Fixed Routing ==="
# Test from Client1
echo "--- Client1 Tests ---"
sudo docker exec clab-anycast-network-client1 ping -c 3 -W 1 10.0.0.100
sudo docker exec clab-anycast-network-client1 curl -s --connect-timeout 3 http://10.0.0.100:8080 || echo "HTTP failed"
# Test from Client2
echo -e "\n--- Client2 Tests ---"
sudo docker exec clab-anycast-network-client2 ping -c 3 -W 1 10.0.0.100
sudo docker exec clab-anycast-network-client2 curl -s --connect-timeout 3 http://10.0.0.100:8080 || echo "HTTP failed"
clear
echo "=== Testing Anycast Flip Functionality ==="
# Test multiple requests to see which servers respond
echo "Multiple requests from Client1:"
for i in {1..10}; do     response=$(sudo docker exec clab-anycast-network-client1 curl -s --connect-timeout 2 http://10.0.0.100:8080 2>/dev/null | head -1);     if [ -n "$response" ]; then         echo "  Request $i: $response";     else         echo "  Request $i: FAILED";     fi; done
echo -e "\nMultiple requests from Client2:"
for i in {1..10}; do     response=$(sudo docker exec clab-anycast-network-client2 curl -s --connect-timeout 2 http://10.0.0.100:8080 2>/dev/null | head -1);     if [ -n "$response" ]; then         echo "  Request $i: $response";     else         echo "  Request $i: FAILED";     fi; done
clear
echo "=== Testing Anycast Flip Functionality ==="
# Test multiple requests to see which servers respond
echo "Multiple requests from Client1:"
for i in {1..10}; do     response=$(sudo docker exec clab-anycast-network-client1 curl -s --connect-timeout 2 http://10.0.0.100:8080 2>/dev/null | head -1);     if [ -n "$response" ]; then         echo "  Request $i: $response";     else         echo "  Request $i: FAILED";     fi; done
echo -e "\nMultiple requests from Client2:"
for i in {1..10}; do     response=$(sudo docker exec clab-anycast-network-client2 curl -s --connect-timeout 2 http://10.0.0.100:8080 2>/dev/null | head -1);     if [ -n "$response" ]; then         echo "  Request $i: $response";     else         echo "  Request $i: FAILED";     fi; done
clear
cat > anycast-flip-simulation.sh << 'EOF'
#!/bin/bash

ANYCAST_IP="10.0.0.100"

echo "=== Anycast Flip Simulation ==="

test_anycast() {
    echo "Current anycast responses:"
    for client in 1 2; do
        echo "Client$client:"
        responses=""
        for i in {1..3}; do
            response=$(sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 2 http://$ANYCAST_IP:8080 2>/dev/null | grep -o "Server [0-9]" | head -1)
            if [ -n "$response" ]; then
                echo "  Request $i: $response"
                responses+="$response "
            else
                echo "  Request $i: FAILED"
            fi
        done
        # Show which servers responded
        unique_servers=$(echo "$responses" | tr ' ' '\n' | sort | uniq | tr '\n' ' ')
        if [ -n "$unique_servers" ]; then
            echo "  Servers reached: $unique_servers"
        fi
        echo
    done
}

# Initial state
echo "=== INITIAL STATE ==="
test_anycast

echo "=== SIMULATION 1: Stop Server1 ==="
echo "Stopping anycast-server1..."
sudo docker exec clab-anycast-network-anycast-server1 pkill -f "python3"
sleep 3
test_anycast

echo "=== SIMULATION 2: Stop Server3 ==="
echo "Stopping anycast-server3..."
sudo docker exec clab-anycast-network-anycast-server3 pkill -f "python3"
sleep 3
test_anycast

echo "=== SIMULATION 3: Restore All Servers ==="
echo "Starting all servers..."
for server in 1 2 3; do
    sudo docker exec -d clab-anycast-network-anycast-server$server python3 /tmp/anycast-server.py
done
sleep 3
test_anycast

echo "=== Anycast Flip Simulation Complete ==="
EOF

chmod +x anycast-flip-simulation.sh
clear
# Run the simulation
./anycast-flip-simulation.sh
clear
cat > improve-anycast-failover.sh << 'EOF'
#!/bin/bash

ANYCAST_IP="10.0.0.100"

echo "=== Improving Anycast Failover ==="

# The issue: Router1 has ECMP but it's not working properly for failover
# Let's fix the routing to enable proper anycast failover

echo "--- Configuring Better Anycast Routing ---"

# Clear existing anycast routes
sudo docker exec clab-anycast-network-router1 ip route del $ANYCAST_IP/32 2>/dev/null || true
sudo docker exec clab-anycast-network-router2 ip route del $ANYCAST_IP/32 2>/dev/null || true

# Configure Router1 with proper ECMP for anycast
echo "Configuring Router1 ECMP routing..."
sudo docker exec clab-anycast-network-router1 ip route add $ANYCAST_IP/32 nexthop via 10.0.1.10 dev eth1 weight 1 nexthop via 10.0.2.10 dev eth2 weight 1

# Configure Router2 with route to anycast
sudo docker exec clab-anycast-network-router2 ip route add $ANYCAST_IP/32 via 10.0.3.10 dev eth1

# Add backup routes between routers for anycast failover
echo "Adding inter-router anycast backup routes..."

# Router1 should know about Server3 via Router2 as backup
sudo docker exec clab-anycast-network-router1 ip route add $ANYCAST_IP/32 via 10.0.10.2 dev eth4 metric 100

# Router2 should know about Server1 and Server2 via Router1 as backup
sudo docker exec clab-anycast-network-router2 ip route add $ANYCAST_IP/32 via 10.0.10.1 dev eth3 metric 100

# Configure route preferences (metrics) for better failover
echo "Configuring route metrics..."

# Make direct routes preferred over backup routes
sudo docker exec clab-anycast-network-router1 ip route change $ANYCAST_IP/32 nexthop via 10.0.1.10 dev eth1 weight 1 nexthop via 10.0.2.10 dev eth2 weight 1

# Enable BFD-like fast failure detection (using lower metrics for direct routes)
for router in 1 2; do
    # Enable TCP keepalives and lower TCP timeouts
    sudo docker exec clab-anycast-network-router$router bash -c "echo 10 > /proc/sys/net/ipv4/tcp_keepalive_time"
    sudo docker exec clab-anycast-network-router$router bash -c "echo 5 > /proc/sys/net/ipv4/tcp_keepalive_intvl"
done

echo "--- Anycast Failover Configuration Complete ---"
EOF

chmod +x improve-anycast-failover.sh
./improve-anycast-failover.sh
clear
echo "=== Testing Improved Anycast Failover ==="
# First, verify all servers are running
echo "Checking server status:"
for server in 1 2 3; do     status=$(sudo docker exec clab-anycast-network-anycast-server$server ps aux | grep python | grep -v grep | wc -l);     echo "Server$server: $([ $status -eq 1 ] && echo "RUNNING" || echo "STOPPED")"; done
# Test initial state
echo -e "\n=== Initial State ==="
for client in 1 2; do     echo "Client$client initial requests:";     for i in {1..5}; do         response=$(sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 2 http://10.0.0.100:8080 2>/dev/null | grep -o "Server [0-9]" | head -1);         echo "  Request $i: ${response:-FAILED}";     done; done
clear
cat > enhanced-anycast-flip.sh << 'EOF'
#!/bin/bash

ANYCAST_IP="10.0.0.100"

echo "=== Enhanced Anycast Flip Simulation ==="

test_anycast_detailed() {
    echo "=== Anycast Network Status ==="
    
    # Show which servers are running
    echo "Server Status:"
    for server in 1 2 3; do
        status=$(sudo docker exec clab-anycast-network-anycast-server$server ps aux | grep python | grep -v grep | wc -l)
        echo "  Server$server: $([ $status -eq 1 ] && echo "ACTIVE" || echo "INACTIVE")"
    done
    
    # Test connectivity from both clients
    echo -e "\nClient Connectivity:"
    for client in 1 2; do
        echo "Client$client:"
        servers_reached=""
        successful_requests=0
        
        for i in {1..5}; do
            response=$(sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 2 http://$ANYCAST_IP:8080 2>/dev/null | grep -o "Server [0-9]" | head -1)
            if [ -n "$response" ]; then
                echo "  ✓ Request $i: $response"
                servers_reached+="$response "
                ((successful_requests++))
            else
                echo "  ✗ Request $i: FAILED"
            fi
        done
        
        # Show summary
        unique_servers=$(echo "$servers_reached" | tr ' ' '\n' | sort | uniq | tr '\n' ',' | sed 's/,$//')
        if [ -n "$unique_servers" ]; then
            echo "  Summary: $successful_requests/5 successful, reached: $unique_servers"
        else
            echo "  Summary: 0/5 successful"
        fi
        echo
    done
}

# Initial state
echo ">>> PHASE 1: INITIAL STATE (All servers running)"
test_anycast_detailed

echo ">>> PHASE 2: STOP SERVER1 (Testing failover for Client1)"
echo "Stopping anycast-server1..."
sudo docker exec clab-anycast-network-anycast-server1 pkill -f "python3"
sleep 5  # Give time for routing to converge
test_anycast_detailed

echo ">>> PHASE 3: STOP SERVER3 (Testing failover for Client2)"
echo "Stopping anycast-server3..."
sudo docker exec clab-anycast-network-anycast-server3 pkill -f "python3"
sleep 5
test_anycast_detailed

echo ">>> PHASE 4: RESTORE ALL SERVERS"
echo "Starting all servers..."
for server in 1 2 3; do
    sudo docker exec -d clab-anycast-network-anycast-server$server python3 /tmp/anycast-server.py
done
sleep 5
test_anycast_detailed

echo "=== Simulation Complete ==="
EOF

chmod +x enhanced-anycast-flip.sh
clear
# Run the enhanced simulation
./enhanced-anycast-flip.sh
clear
cat > fix-anycast-ecmp.sh << 'EOF'
#!/bin/bash

ANYCAST_IP="10.0.0.100"

echo "=== Fixing Anycast ECMP Routing ==="

# Remove all existing anycast routes
sudo docker exec clab-anycast-network-router1 ip route del $ANYCAST_IP/32 2>/dev/null || true
sudo docker exec clab-anycast-network-router2 ip route del $ANYCAST_IP/32 2>/dev/null || true

# Clear route cache
sudo docker exec clab-anycast-network-router1 ip route flush cache 2>/dev/null || true
sudo docker exec clab-anycast-network-router2 ip route flush cache 2>/dev/null || true

# Configure Router1 with proper ECMP using multipath
echo "Configuring Router1 ECMP with multipath..."
# First add individual routes, then the multipath route
sudo docker exec clab-anycast-network-router1 ip route add $ANYCAST_IP/32 via 10.0.1.10 dev eth1
sudo docker exec clab-anycast-network-router1 ip route add $ANYCAST_IP/32 via 10.0.2.10 dev eth2

# Now add the multipath route (this should create proper ECMP)
sudo docker exec clab-anycast-network-router1 ip route change $ANYCAST_IP/32 nexthop via 10.0.1.10 dev eth1 weight 1 nexthop via 10.0.2.10 dev eth2 weight 1

# Configure Router2
sudo docker exec clab-anycast-network-router2 ip route add $ANYCAST_IP/32 via 10.0.3.10 dev eth1

# Add cross-router backup routes with higher metrics (lower priority)
echo "Adding cross-router backup routes..."
sudo docker exec clab-anycast-network-router1 ip route add $ANYCAST_IP/32 via 10.0.10.2 dev eth4 metric 100
sudo docker exec clab-anycast-network-router2 ip route add $ANYCAST_IP/32 via 10.0.10.1 dev eth3 metric 100

# Enable IP forwarding and other necessary kernel settings
for router in 1 2; do
    sudo docker exec clab-anycast-network-router$router bash -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
    sudo docker exec clab-anycast-network-router$router bash -c "echo 1 > /proc/sys/net/ipv4/conf/all/proxy_arp"
    # Enable route verification
    sudo docker exec clab-anycast-network-router$router bash -c "echo 1 > /proc/sys/net/ipv4/conf/all/rp_filter"
done

echo "--- ECMP Routing Configuration Complete ---"

# Verify the configuration
echo -e "\nVerifying Router1 anycast routes:"
sudo docker exec clab-anycast-network-router1 ip route show | grep 10.0.0.100

echo -e "\nVerifying Router2 anycast routes:"
sudo docker exec clab-anycast-network-router2 ip route show | grep 10.0.0.100
EOF

chmod +x fix-anycast-ecmp.sh
./fix-anycast-ecmp.sh
clear
echo "=== Testing ECMP Load Balancing ==="
# Test if Router1 is now load balancing between Server1 and Server2
echo "Testing from Client1 (should see both Server1 and Server2):"
for i in {1..10}; do     response=$(sudo docker exec clab-anycast-network-client1 curl -s --connect-timeout 2 http://10.0.0.100:8080 2>/dev/null | grep -o "Server [0-9]" | head -1);     echo "  Request $i: ${response:-FAILED}"; done
echo -e "\nTesting from Client2 (should see Server3):"
for i in {1..5}; do     response=$(sudo docker exec clab-anycast-network-client2 curl -s --connect-timeout 2 http://10.0.0.100:8080 2>/dev/null | grep -o "Server [0-9]" | head -1);     echo "  Request $i: ${response:-FAILED}"; done
qclear
clear
echo "=== Testing ECMP Load Balancing ==="
# Test if Router1 is now load balancing between Server1 and Server2
echo "Testing from Client1 (should see both Server1 and Server2):"
for i in {1..10}; do     response=$(sudo docker exec clab-anycast-network-client1 curl -s --connect-timeout 2 http://10.0.0.100:8080 2>/dev/null | grep -o "Server [0-9]" | head -1);     echo "  Request $i: ${response:-FAILED}"; done
echo -e "\nTesting from Client2 (should see Server3):"
for i in {1..5}; do     response=$(sudo docker exec clab-anycast-network-client2 curl -s --connect-timeout 2 http://10.0.0.100:8080 2>/dev/null | grep -o "Server [0-9]" | head -1);     echo "  Request $i: ${response:-FAILED}"; done
clear
cat > working-anycast-bgp-style.sh << 'EOF'
#!/bin/bash

ANYCAST_IP="10.0.0.100"

echo "=== Implementing Working Anycast with BGP-style Behavior ==="

# Remove all existing anycast routes
sudo docker exec clab-anycast-network-router1 ip route del $ANYCAST_IP/32 2>/dev/null || true
sudo docker exec clab-anycast-network-router2 ip route del $ANYCAST_IP/32 2>/dev/null || true

# Clear route cache
sudo docker exec clab-anycast-network-router1 ip route flush cache 2>/dev/null || true

echo "--- Configuring Router1 with Metric-based Routing ---"

# Add routes with different metrics (lower metric = higher priority)
# Primary: Server1 (metric 10)
sudo docker exec clab-anycast-network-router1 ip route add $ANYCAST_IP/32 via 10.0.1.10 dev eth1 metric 10

# Secondary: Server2 (metric 20) - will be used if Server1 fails
sudo docker exec clab-anycast-network-router1 ip route add $ANYCAST_IP/32 via 10.0.2.10 dev eth2 metric 20

# Tertiary: Via Router2 to Server3 (metric 30) - last resort
sudo docker exec clab-anycast-network-router1 ip route add $ANYCAST_IP/32 via 10.0.10.2 dev eth4 metric 30

echo "--- Configuring Router2 ---"
# Router2 primary: Server3
sudo docker exec clab-anycast-network-router2 ip route add $ANYCAST_IP/32 via 10.0.3.10 dev eth1 metric 10

# Router2 backup: Via Router1 to Server1 or Server2
sudo docker exec clab-anycast-network-router2 ip route add $ANYCAST_IP/32 via 10.0.10.1 dev eth3 metric 20

echo "--- Setting up Automatic Failover Script ---"

# Create a health check script on routers
for router in 1 2; do
    sudo docker exec clab-anycast-network-router$router bash -c 'cat > /tmp/anycast-healthcheck.sh << "SCRIPTEOF"
#!/bin/bash
ANYCAST_IP="10.0.0.100"

check_server() {
    local server_ip=$1
    local interface=$2
    local metric=$3
    
    # Ping the server
    if ping -c 1 -W 1 -I $interface $server_ip > /dev/null 2>&1; then
        # Server is up, ensure route exists with proper metric
        ip route replace $ANYCAST_IP/32 via $server_ip dev $interface metric $metric
        return 0
    else
        # Server is down, remove the route
        ip route del $ANYCAST_IP/32 via $server_ip dev $interface metric $metric 2>/dev/null || true
        return 1
    fi
}

# Check all servers
check_server 10.0.1.10 eth1 10
check_server 10.0.2.10 eth2 20
check_server 10.0.3.10 eth4 30  # This goes through Router2

SCRIPTEOF'
    
    sudo docker exec clab-anycast-network-router$router chmod +x /tmp/anycast-healthcheck.sh
done

echo "--- Running Initial Health Check ---"
sudo docker exec clab-anycast-network-router1 /tmp/anycast-healthcheck.sh
sudo docker exec clab-anycast-network-router2 /tmp/anycast-healthcheck.sh

echo "--- BGP-style Anycast Setup Complete ---"

# Show final routing
echo -e "\nFinal Router1 routes:"
sudo docker exec clab-anycast-network-router1 ip route show | grep 10.0.0.100

echo -e "\nFinal Router2 routes:"
sudo docker exec clab-anycast-network-router2 ip route show | grep 10.0.0.100
EOF

chmod +x working-anycast-bgp-style.sh
./working-anycast-bgp-style.sh
clear
echo "=== Testing BGP-style Anycast ==="
# Test initial state
echo "Initial state - all servers should be reachable:"
for client in 1 2; do     echo "Client$client:";     for i in {1..5}; do         response=$(sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 2 http://10.0.0.100:8080 2>/dev/null | grep -o "Server [0-9]" | head -1);         echo "  Request $i: ${response:-FAILED}";     done; done
cat > start-health-monitor.sh << 'EOF'
#!/bin/bash

echo "=== Starting Anycast Health Monitor ==="

# Kill any existing health monitors
for router in 1 2; do
    sudo docker exec clab-anycast-network-router$router pkill -f "anycast-healthcheck" 2>/dev/null || true
done

# Start health monitoring on both routers
for router in 1 2; do
    echo "Starting health monitor on Router$router..."
    sudo docker exec -d clab-anycast-network-router$router bash -c 'while true; do /tmp/anycast-healthcheck.sh; sleep 5; done'
done

echo "Health monitors started. They will check server status every 5 seconds."
echo "Run './test-anycast-flip.sh' to test failover."
EOF

chmod +x start-health-monitor.sh
./start-health-monitor.sh
cat > test-anycast-flip.sh << 'EOF'
#!/bin/bash

ANYCAST_IP="10.0.0.100"

echo "=== Comprehensive Anycast Flip Test ==="

show_status() {
    echo "=== Current Status ==="
    
    # Show server status
    echo "Server Status:"
    for server in 1 2 3; do
        status=$(sudo docker exec clab-anycast-network-anycast-server$server ps aux | grep python | grep -v grep | wc -l)
        echo "  Server$server: $([ $status -eq 1 ] && echo "✅ RUNNING" || echo "❌ STOPPED")"
    done
    
    # Show router routes
    echo -e "\nRouter1 anycast routes:"
    sudo docker exec clab-anycast-network-router1 ip route show | grep 10.0.0.100 || echo "  No routes found"
    
    echo -e "\nRouter2 anycast routes:"
    sudo docker exec clab-anycast-network-router2 ip route show | grep 10.0.0.100 || echo "  No routes found"
}

test_connectivity() {
    echo -e "\n=== Connectivity Test ==="
    for client in 1 2; do
        echo "Client$client:"
        success=0
        for i in {1..5}; do
            response=$(sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 2 http://$ANYCAST_IP:8080 2>/dev/null | grep -o "Server [0-9]" | head -1)
            if [ -n "$response" ]; then
                echo "  ✅ Request $i: $response"
                ((success++))
            else
                echo "  ❌ Request $i: FAILED"
            fi
        done
        echo "  Success rate: $success/5"
    done
}

# Initial state
echo ">>> PHASE 1: INITIAL STATE"
show_status
test_connectivity

echo -e "\n>>> PHASE 2: STOP SERVER1 (Client1 should failover to Server2)"
echo "Stopping Server1..."
sudo docker exec clab-anycast-network-anycast-server1 pkill -f "python3"
sleep 8  # Wait for health check to detect failure
show_status
test_connectivity

echo -e "\n>>> PHASE 3: STOP SERVER3 (Client2 should failover to Router1)"
echo "Stopping Server3..."
sudo docker exec clab-anycast-network-anycast-server3 pkill -f "python3"
sleep 8
show_status
test_connectivity

echo -e "\n>>> PHASE 4: RESTORE ALL SERVERS"
echo "Starting all servers..."
for server in 1 2 3; do
    sudo docker exec -d clab-anycast-network-anycast-server$server python3 /tmp/anycast-server.py
done
sleep 8
show_status
test_connectivity

echo -e "\n=== Anycast Flip Test Complete ==="
EOF

chmod +x test-anycast-flip.sh
clear
=clear
clear
cat > test-anycast-flip.sh << 'EOF'
#!/bin/bash

ANYCAST_IP="10.0.0.100"

echo "=== Comprehensive Anycast Flip Test ==="

show_status() {
    echo "=== Current Status ==="
    
    # Show server status
    echo "Server Status:"
    for server in 1 2 3; do
        status=$(sudo docker exec clab-anycast-network-anycast-server$server ps aux | grep python | grep -v grep | wc -l)
        echo "  Server$server: $([ $status -eq 1 ] && echo "✅ RUNNING" || echo "❌ STOPPED")"
    done
    
    # Show router routes
    echo -e "\nRouter1 anycast routes:"
    sudo docker exec clab-anycast-network-router1 ip route show | grep 10.0.0.100 || echo "  No routes found"
    
    echo -e "\nRouter2 anycast routes:"
    sudo docker exec clab-anycast-network-router2 ip route show | grep 10.0.0.100 || echo "  No routes found"
}

test_connectivity() {
    echo -e "\n=== Connectivity Test ==="
    for client in 1 2; do
        echo "Client$client:"
        success=0
        for i in {1..5}; do
            response=$(sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 2 http://$ANYCAST_IP:8080 2>/dev/null | grep -o "Server [0-9]" | head -1)
            if [ -n "$response" ]; then
                echo "  ✅ Request $i: $response"
                ((success++))
            else
                echo "  ❌ Request $i: FAILED"
            fi
        done
        echo "  Success rate: $success/5"
    done
}

# Initial state
echo ">>> PHASE 1: INITIAL STATE"
show_status
test_connectivity

echo -e "\n>>> PHASE 2: STOP SERVER1 (Client1 should failover to Server2)"
echo "Stopping Server1..."
sudo docker exec clab-anycast-network-anycast-server1 pkill -f "python3"
sleep 8  # Wait for health check to detect failure
show_status
test_connectivity

echo -e "\n>>> PHASE 3: STOP SERVER3 (Client2 should failover to Router1)"
echo "Stopping Server3..."
sudo docker exec clab-anycast-network-anycast-server3 pkill -f "python3"
sleep 8
show_status
test_connectivity

echo -e "\n>>> PHASE 4: RESTORE ALL SERVERS"
echo "Starting all servers..."
for server in 1 2 3; do
    sudo docker exec -d clab-anycast-network-anycast-server$server python3 /tmp/anycast-server.py
done
sleep 8
show_status
test_connectivity

echo -e "\n=== Anycast Flip Test Complete ==="
EOF

chmod +x test-anycast-flip.sh
clear
# Run the comprehensive anycast flip test
./test-anycast-flip.sh
clear
cat > fix-health-check.sh << 'EOF'
#!/bin/bash

echo "=== Fixing Health Check Script ==="

# Create a better health check script
for router in 1 2; do
    sudo docker exec clab-anycast-network-router$router bash -c 'cat > /tmp/anycast-healthcheck-fixed.sh << "SCRIPTEOF"
#!/bin/bash

ANYCAST_IP="10.0.0.100"

# Function to check if a server is reachable and update route
check_server_route() {
    local target_ip=$1
    local via_ip=$2
    local dev=$3
    local metric=$4
    
    echo "Checking server $target_ip via $via_ip on $dev..."
    
    # Try to ping the target IP (the server itself)
    if ping -c 1 -W 1 $target_ip > /dev/null 2>&1; then
        echo "  ✅ Server $target_ip is UP"
        # Add or replace the route
        ip route replace $ANYCAST_IP/32 via $via_ip dev $dev metric $metric 2>/dev/null
        return 0
    else
        echo "  ❌ Server $target_ip is DOWN"
        # Remove the route if it exists
        ip route del $ANYCAST_IP/32 via $via_ip dev $dev metric $metric 2>/dev/null || true
        return 1
    fi
}

echo "=== Running Health Check ==="

# Router1 specific checks
if [ "$(hostname)" = "router1" ]; then
    check_server_route 10.0.1.10 10.0.1.10 eth1 10
    check_server_route 10.0.2.10 10.0.2.10 eth2 20
    # For Server3 via Router2, check if Router2 is reachable
    if ping -c 1 -W 1 10.0.10.2 > /dev/null 2>&1; then
        echo "  ✅ Router2 is reachable"
        ip route replace $ANYCAST_IP/32 via 10.0.10.2 dev eth4 metric 30 2>/dev/null
    else
        echo "  ❌ Router2 is unreachable"
        ip route del $ANYCAST_IP/32 via 10.0.10.2 dev eth4 metric 30 2>/dev/null || true
    fi
fi

# Router2 specific checks
if [ "$(hostname)" = "router2" ]; then
    check_server_route 10.0.3.10 10.0.3.10 eth1 10
    # For Server1/Server2 via Router1, check if Router1 is reachable
    if ping -c 1 -W 1 10.0.10.1 > /dev/null 2>&1; then
        echo "  ✅ Router1 is reachable"
        ip route replace $ANYCAST_IP/32 via 10.0.10.1 dev eth3 metric 20 2>/dev/null
    else
        echo "  ❌ Router1 is unreachable"
        ip route del $ANYCAST_IP/32 via 10.0.10.1 dev eth3 metric 20 2>/dev/null || true
    fi
fi

echo "=== Health Check Complete ==="
echo "Current anycast routes:"
ip route show | grep $ANYCAST_IP || echo "  No anycast routes"

SCRIPTEOF'

    sudo docker exec clab-anycast-network-router$router chmod +x /tmp/anycast-healthcheck-fixed.sh
done

echo "--- Testing Fixed Health Check ---"

# Stop health monitors
for router in 1 2; do
    sudo docker exec clab-anycast-network-router$router pkill -f "anycast-healthcheck" 2>/dev/null || true
done

# Run the fixed health check
echo "Running fixed health check on Router1:"
sudo docker exec clab-anycast-network-router1 /tmp/anycast-healthcheck-fixed.sh

echo -e "\nRunning fixed health check on Router2:"
sudo docker exec clab-anycast-network-router2 /tmp/anycast-healthcheck-fixed.sh

echo "--- Fixed Health Check Complete ---"
EOF

chmod +x fix-health-check.sh
./fix-health-check.sh
clear
cat > start-fixed-health-monitor.sh << 'EOF'
#!/bin/bash

echo "=== Starting Fixed Health Monitor ==="

# Kill any existing health monitors
for router in 1 2; do
    sudo docker exec clab-anycast-network-router$router pkill -f "anycast-healthcheck" 2>/dev/null || true
done

# Start the fixed health monitoring
for router in 1 2; do
    echo "Starting fixed health monitor on Router$router..."
    sudo docker exec -d clab-anycast-network-router$router bash -c 'while true; do echo "$(date): Health check on $(hostname)"; /tmp/anycast-healthcheck-fixed.sh; sleep 5; done'
    echo "  Health monitor started on Router$router"
done

echo "=== Fixed Health Monitors Started ==="
echo "They will check server status every 5 seconds and log activity."
EOF

chmod +x start-fixed-health-monitor.sh
./start-fixed-health-monitor.sh
clear
echo "=== Testing Fixed Health Monitoring ==="
# Wait a moment for health checks to run
sleep 6
# Check current routes
echo "Current anycast routes after health checks:"
for router in 1 2; do     echo "Router$router:";     sudo docker exec clab-anycast-network-router$router ip route show | grep 10.0.0.100 || echo "  No routes"; done
# Test connectivity
echo -e "\nTesting connectivity with health monitoring:"
for client in 1 2; do     echo "Client$client:";     for i in {1..3}; do         response=$(sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 2 http://10.0.0.100:8080 2>/dev/null | grep -o "Server [0-9]" | head -1);         echo "  Request $i: ${response:-FAILED}";     done; done
clear
cat > working-anycast-flip-test.sh << 'EOF'
#!/bin/bash

ANYCAST_IP="10.0.0.100"

echo "=== WORKING ANYCAST FLIP TEST ==="

wait_for_health_check() {
    echo "Waiting for health checks to update routes..."
    sleep 7
}

show_detailed_status() {
    echo -e "\n=== DETAILED STATUS ==="
    
    # Server status
    echo "SERVER STATUS:"
    for server in 1 2 3; do
        status=$(sudo docker exec clab-anycast-network-anycast-server$server ps aux | grep python | grep -v grep | wc -l)
        echo "  Server$server: $([ $status -eq 1 ] && echo "🟢 RUNNING" || echo "🔴 STOPPED")"
    done
    
    # Router routes
    echo -e "\nROUTER ROUTES:"
    for router in 1 2; do
        echo "  Router$router:"
        routes=$(sudo docker exec clab-anycast-network-router$router ip route show | grep "$ANYCAST_IP" || echo "    No routes")
        echo "$routes" | sed 's/^/    /'
    done
}

test_connectivity_detailed() {
    echo -e "\n=== CONNECTIVITY TEST ==="
    for client in 1 2; do
        echo "Client$client:"
        results=()
        for i in {1..5}; do
            response=$(sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 2 http://$ANYCAST_IP:8080 2>/dev/null | grep -o "Server [0-9]" | head -1)
            if [ -n "$response" ]; then
                results+=("$response")
                echo "  ✅ Request $i: $response"
            else
                results+=("FAILED")
                echo "  ❌ Request $i: FAILED"
            fi
        done
        
        # Calculate success rate and servers reached
        success_count=0
        servers_reached=()
        for result in "${results[@]}"; do
            if [ "$result" != "FAILED" ]; then
                ((success_count++))
                server_num=$(echo "$result" | cut -d' ' -f2)
                servers_reached["$server_num"]=1
            fi
        done
        
        echo "  📊 Success: $success_count/5, Servers: ${!servers_reached[@]}"
    done
}

# PHASE 1: Initial State
echo ">>> PHASE 1: INITIAL STATE (All Servers Running)"
show_detailed_status
test_connectivity_detailed

# PHASE 2: Stop Server1
echo -e "\n>>> PHASE 2: STOPPING SERVER1 (Testing Failover)"
echo "Stopping Server1..."
sudo docker exec clab-anycast-network-anycast-server1 pkill -f "python3"
wait_for_health_check
show_detailed_status
test_connectivity_detailed

# PHASE 3: Stop Server3  
echo -e "\n>>> PHASE 3: STOPPING SERVER3 (Testing Cross-Router Failover)"
echo "Stopping Server3..."
sudo docker exec clab-anycast-network-anycast-server3 pkill -f "python3"
wait_for_health_check
show_detailed_status
test_connectivity_detailed

# PHASE 4: Restore All
echo -e "\n>>> PHASE 4: RESTORING ALL SERVERS"
echo "Starting all servers..."
for server in 1 2 3; do
    sudo docker exec -d clab-anycast-network-anycast-server$server python3 /tmp/anycast-server.py
done
wait_for_health_check
show_detailed_status
test_connectivity_detailed

echo -e "\n=== ANYCAST FLIP TEST COMPLETE ==="
EOF

chmod +x working-anycast-flip-test.sh
clear
# Run the working anycast flip test
./working-anycast-flip-test.sh
clear
ls
clear
ls
clear
# Remove all the scripts we created
rm -f *.sh *.yaml
# Stop any running health monitors in the containers
for router in 1 2; do     sudo docker exec clab-anycast-network-router$router pkill -f "anycast-healthcheck" 2>/dev/null || true;     sudo docker exec clab-anycast-network-router$router pkill -f "bash.*while" 2>/dev/null || true; done
echo "=== Cleaned up all scripts and processes ==="
clear
ls
clear
echo "=== Checking Container Status ==="
sudo containerlab inspect -t anycast-topology.yaml
clear
echo "=== Checking Container Status ==="
sudo containerlab inspect -t anycast-topology.yaml
clear
echo "=== Checking Container Status ==="
sudo containerlab inspect -t anycast-topology.yaml
clear
echo "=== Checking Running Containers ==="
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo -e "\n=== Checking ContainerLab Status ==="
sudo containerlab inspect --all
clear
echo "=== Checking Running Containers ==="
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo -e "\n=== Checking ContainerLab Status ==="
sudo containerlab inspect --all
clear
cat > quick-anycast.sh << 'EOF'
#!/bin/bash

ANYCAST_IP="10.0.0.100"

echo "=== QUICK ANYCAST SETUP (10 minutes) ==="

# Step 1: Install packages (2 minutes)
echo "1/5 Installing packages..."
for container in router1 router2 client1 client2 anycast-server1 anycast-server2 anycast-server3; do
    echo "  - $container"
    sudo docker exec clab-anycast-network-$container apt-get update > /dev/null 2>&1
    sudo docker exec clab-anycast-network-$container apt-get install -y iproute2 net-tools iputils-ping curl python3 > /dev/null 2>&1 &
done
wait

# Step 2: Configure IP addresses (2 minutes)
echo "2/5 Configuring IP addresses..."

# Router1
sudo docker exec clab-anycast-network-router1 ip addr add 10.0.1.1/24 dev eth1
sudo docker exec clab-anycast-network-router1 ip addr add 10.0.2.1/24 dev eth2
sudo docker exec clab-anycast-network-router1 ip addr add 192.168.1.1/24 dev eth3
sudo docker exec clab-anycast-network-router1 ip addr add 10.0.10.1/24 dev eth4

# Router2
sudo docker exec clab-anycast-network-router2 ip addr add 10.0.3.1/24 dev eth1
sudo docker exec clab-anycast-network-router2 ip addr add 192.168.2.1/24 dev eth2
sudo docker exec clab-anycast-network-router2 ip addr add 10.0.10.2/24 dev eth3

# Servers
sudo docker exec clab-anycast-network-anycast-server1 ip addr add 10.0.1.10/24 dev eth1
sudo docker exec clab-anycast-network-anycast-server2 ip addr add 10.0.2.10/24 dev eth1
sudo docker exec clab-anycast-network-anycast-server3 ip addr add 10.0.3.10/24 dev eth1

# Clients
sudo docker exec clab-anycast-network-client1 ip addr add 192.168.1.100/24 dev eth1
sudo docker exec clab-anycast-network-client2 ip addr add 192.168.2.100/24 dev eth1

# Step 3: Add anycast IP and enable forwarding (1 minute)
echo "3/5 Setting up anycast IP and routing..."
for server in 1 2 3; do
    sudo docker exec clab-anycast-network-anycast-server$server ip addr add $ANYCAST_IP/32 dev lo
done

sudo docker exec clab-anycast-network-router1 bash -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
sudo docker exec clab-anycast-network-router2 bash -c "echo 1 > /proc/sys/net/ipv4/ip_forward"

# Step 4: Configure routes (2 minutes)
echo "4/5 Configuring routes..."

# Router routes to anycast
sudo docker exec clab-anycast-network-router1 ip route add $ANYCAST_IP/32 via 10.0.1.10 dev eth1
sudo docker exec clab-anycast-network-router1 ip route add $ANYCAST_IP/32 via 10.0.2.10 dev eth2
sudo docker exec clab-anycast-network-router2 ip route add $ANYCAST_IP/32 via 10.0.3.10 dev eth1

# Client default routes
sudo docker exec clab-anycast-network-client1 ip route add default via 192.168.1.1 dev eth1
sudo docker exec clab-anycast-network-client2 ip route add default via 192.168.2.1 dev eth1

# Server default routes
for server in 1 2 3; do
    sudo docker exec clab-anycast-network-anycast-server$server ip route add default via 10.0.$server.1 dev eth1
done

# Step 5: Start HTTP servers (1 minute)
echo "5/5 Starting HTTP servers..."
for server in 1 2 3; do
    sudo docker exec -d clab-anycast-network-anycast-server$server python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
import socket

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        hostname = socket.gethostname()
        self.wfile.write(f'Response from {hostname} (Server {hostname[-1]})'.encode())
    def log_message(self, *args):
        pass

HTTPServer(('0.0.0.0', 8080), Handler).serve_forever()
" &
done

echo "=== SETUP COMPLETE ==="
EOF

chmod +x quick-anycast.sh
./quick-anycast.sh
clear
cat > quick-test.sh << 'EOF'
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
EOF

chmod +x quick-test.sh
./quick-test.sh
clear
clear
cat > quick-test.sh << 'EOF'
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
EOF

chmod +x quick-test.sh
./quick-test.sh
clear
cat > quick-flip-demo.sh << 'EOF'
#!/bin/bash

ANYCAST_IP="10.0.0.100"

echo "=== QUICK ANYCAST FLIP DEMO ==="

test_anycast() {
    echo "Current state:"
    for client in 1 2; do
        echo -n "Client$client: "
        response=$(sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 2 http://$ANYCAST_IP:8080 | head -1)
        echo "${response:-NO RESPONSE}"
    done
    echo
}

echo ">>> PHASE 1: Initial state (all servers running)"
test_anycast

echo ">>> PHASE 2: Stopping Server1"
sudo docker exec clab-anycast-network-anycast-server1 pkill -f "python3"
sleep 2
test_anycast

echo ">>> PHASE 3: Stopping Server3"  
sudo docker exec clab-anycast-network-anycast-server3 pkill -f "python3"
sleep 2
test_anycast

echo ">>> PHASE 4: Restarting all servers"
for server in 1 2 3; do
    sudo docker exec -d clab-anycast-network-anycast-server$server python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
import socket

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        hostname = socket.gethostname()
        self.wfile.write(f'Response from {hostname} (Server {hostname[-1]})'.encode())
    def log_message(self, *args):
        pass

HTTPServer(('0.0.0.0', 8080), Handler).serve_forever()
" &
done
sleep 3
test_anycast

echo "=== DEMO COMPLETE ==="
EOF

chmod +x quick-flip-demo.sh
clear
# Run the quick anycast flip demo
./quick-flip-demo.sh
clear
# Run the quick anycast flip demo
./quick-flip-demo.sh
clear
cat > fix-failover.sh << 'EOF'
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
EOF

chmod +x fix-failover.sh
./fix-failover.sh
clear
cat > enhanced-flip-demo.sh << 'EOF'
#!/bin/bash

ANYCAST_IP="10.0.0.100"

echo "=== ENHANCED ANYCAST FLIP DEMO ==="

test_anycast_detailed() {
    echo "=== CURRENT STATE ==="
    
    # Show server status
    echo "Server Status:"
    for server in 1 2 3; do
        status=$(sudo docker exec clab-anycast-network-anycast-server$server ps aux | grep python | grep -v grep | wc -l)
        echo "  Server$server: $([ $status -eq 1 ] && echo "🟢 RUNNING" || echo "🔴 STOPPED")"
    done
    
    # Test connectivity
    echo -e "\nConnectivity:"
    for client in 1 2; do
        echo "Client$client:"
        responses=()
        for i in {1..5}; do
            response=$(sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 2 http://$ANYCAST_IP:8080 | head -1)
            if [ -n "$response" ]; then
                responses+=("$response")
                echo "  ✅ Request $i: $response"
            else
                responses+=("FAILED")
                echo "  ❌ Request $i: FAILED"
            fi
        done
        
        # Calculate success and unique servers
        success=0
        servers=()
        for response in "${responses[@]}"; do
            if [ "$response" != "FAILED" ]; then
                ((success++))
                server_num=$(echo "$response" | grep -o "Server [0-9]" | cut -d' ' -f2)
                servers["$server_num"]=1
            fi
        done
        
        server_list=$(echo "${!servers[@]}" | tr ' ' ',')
        echo "  📊 Success: $success/5, Servers: ${server_list:-none}"
    done
    echo
}

echo ">>> PHASE 1: INITIAL STATE (All servers running)"
test_anycast_detailed

echo ">>> PHASE 2: STOP SERVER1 (Client1 should failover to Server2)"
sudo docker exec clab-anycast-network-anycast-server1 pkill -f "python3"
sleep 3
test_anycast_detailed

echo ">>> PHASE 3: STOP SERVER3 (Client2 should failover to Router1)"
sudo docker exec clab-anycast-network-anycast-server3 pkill -f "python3"
sleep 3
test_anycast_detailed

echo ">>> PHASE 4: RESTART ALL SERVERS"
for server in 1 2 3; do
    sudo docker exec -d clab-anycast-network-anycast-server$server python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
import socket

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        hostname = socket.gethostname()
        self.wfile.write(f'Response from {hostname} (Server {hostname[-1]})'.encode())
    def log_message(self, *args):
        pass

HTTPServer(('0.0.0.0', 8080), Handler).serve_forever()
" &
done
sleep 3
test_anycast_detailed

echo "=== DEMO COMPLETE ==="
EOF

chmod +x enhanced-flip-demo.shclear
cat > enhanced-flip-demo.sh << 'EOF'
#!/bin/bash

ANYCAST_IP="10.0.0.100"

echo "=== ENHANCED ANYCAST FLIP DEMO ==="

test_anycast_detailed() {
    echo "=== CURRENT STATE ==="
    
    # Show server status
    echo "Server Status:"
    for server in 1 2 3; do
        status=$(sudo docker exec clab-anycast-network-anycast-server$server ps aux | grep python | grep -v grep | wc -l)
        echo "  Server$server: $([ $status -eq 1 ] && echo "🟢 RUNNING" || echo "🔴 STOPPED")"
    done
    
    # Test connectivity
    echo -e "\nConnectivity:"
    for client in 1 2; do
        echo "Client$client:"
        responses=()
        for i in {1..5}; do
            response=$(sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 2 http://$ANYCAST_IP:8080 | head -1)
            if [ -n "$response" ]; then
                responses+=("$response")
                echo "  ✅ Request $i: $response"
            else
                responses+=("FAILED")
                echo "  ❌ Request $i: FAILED"
            fi
        done
        
        # Calculate success and unique servers
        success=0
        servers=()
        for response in "${responses[@]}"; do
            if [ "$response" != "FAILED" ]; then
                ((success++))
                server_num=$(echo "$response" | grep -o "Server [0-9]" | cut -d' ' -f2)
                servers["$server_num"]=1
            fi
        done
        
        server_list=$(echo "${!servers[@]}" | tr ' ' ',')
        echo "  📊 Success: $success/5, Servers: ${server_list:-none}"
    done
    echo
}

echo ">>> PHASE 1: INITIAL STATE (All servers running)"
test_anycast_detailed

echo ">>> PHASE 2: STOP SERVER1 (Client1 should failover to Server2)"
sudo docker exec clab-anycast-network-anycast-server1 pkill -f "python3"
sleep 3
test_anycast_detailed

echo ">>> PHASE 3: STOP SERVER3 (Client2 should failover to Router1)"
sudo docker exec clab-anycast-network-anycast-server3 pkill -f "python3"
sleep 3
test_anycast_detailed

echo ">>> PHASE 4: RESTART ALL SERVERS"
for server in 1 2 3; do
    sudo docker exec -d clab-anycast-network-anycast-server$server python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
import socket

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        hostname = socket.gethostname()
        self.wfile.write(f'Response from {hostname} (Server {hostname[-1]})'.encode())
    def log_message(self, *args):
        pass

HTTPServer(('0.0.0.0', 8080), Handler).serve_forever()
" &
done
sleep 3
test_anycast_detailed

echo "=== DEMO COMPLETE ==="
EOF

chmod +x enhanced-flip-demo.sh
clear
# Run the enhanced anycast flip demo
./enhanced-flip-demo.sh
clear
clear
# Run the enhanced anycast flip demo
./enhanced-flip-demo.sh
clear
cat > anycast-route-manager.sh << 'EOF'
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
EOF

chmod +x anycast-route-manager.sh
clear
cat > working-flip-demo.sh << 'EOF'
#!/bin/bash

ANYCAST_IP="10.0.0.100"

echo "=== WORKING ANYCAST FLIP DEMO ==="

show_status() {
    echo "=== SYSTEM STATUS ==="
    echo "Servers:"
    for server in 1 2 3; do
        status=$(sudo docker exec clab-anycast-network-anycast-server$server ps aux | grep python | grep -v grep | wc -l)
        echo "  Server$server: $([ $status -eq 1 ] && echo "🟢 RUNNING" || echo "🔴 STOPPED")"
    done
}

test_connectivity() {
    echo -e "\n=== CONNECTIVITY TEST ==="
    for client in 1 2; do
        echo "Client$client:"
        success=0
        servers_reached=()
        for i in {1..5}; do
            response=$(sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 2 http://$ANYCAST_IP:8080 | head -1)
            if [ -n "$response" ]; then
                echo "  ✅ $response"
                ((success++))
                # Extract server number
                server_num=$(echo "$response" | grep -o "Server [0-9]" | cut -d' ' -f2)
                servers_reached["$server_num"]=1
            else
                echo "  ❌ FAILED"
            fi
        done
        server_list=$(echo "${!servers_reached[@]}" | tr ' ' ',')
        echo "  📊 Success: $success/5, Servers: ${server_list:-none}"
    done
}

# PHASE 1: Initial setup
echo ">>> PHASE 1: INITIAL SETUP"
./anycast-route-manager.sh
show_status
test_connectivity

# PHASE 2: Stop Server1 - should failover to Server2
echo -e "\n>>> PHASE 2: STOP SERVER1 (Testing failover to Server2)"
echo "Stopping Server1..."
sudo docker exec clab-anycast-network-anycast-server1 pkill -f "python3"
sleep 2
./anycast-route-manager.sh
show_status
test_connectivity

# PHASE 3: Stop Server3 - should failover to Router1 (Server2)
echo -e "\n>>> PHASE 3: STOP SERVER3 (Testing cross-router failover)"
echo "Stopping Server3..."
sudo docker exec clab-anycast-network-anycast-server3 pkill -f "python3"
sleep 2
./anycast-route-manager.sh
show_status
test_connectivity

# PHASE 4: Restore all servers
echo -e "\n>>> PHASE 4: RESTORE ALL SERVERS"
echo "Starting all servers..."
for server in 1 2 3; do
    sudo docker exec -d clab-anycast-network-anycast-server$server python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
import socket

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        hostname = socket.gethostname()
        self.wfile.write(f'Response from {hostname} (Server {hostname[-1]})'.encode())
    def log_message(self, *args):
        pass

HTTPServer(('0.0.0.0', 8080), Handler).serve_forever()
" &
done
sleep 3
./anycast-route-manager.sh
show_status
test_connectivity

echo -e "\n=== DEMO COMPLETE ==="
EOF

chmod +x working-flip-demo.sh
clear
cat > anycast-auto-manager.sh << 'EOF'
#!/bin/bash

ANYCAST_IP="10.0.0.100"

case "$1" in
    "start")
        echo "Starting server $2..."
        sudo docker exec -d clab-anycast-network-anycast-server$2 python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
import socket

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        hostname = socket.gethostname()
        self.wfile.write(f'Response from {hostname} (Server {hostname[-1]})'.encode())
    def log_message(self, *args):
        pass

HTTPServer(('0.0.0.0', 8080), Handler).serve_forever()
" &
        sleep 2
        ./anycast-route-manager.sh
        ;;
    "stop")
        echo "Stopping server $2..."
        sudo docker exec clab-anycast-network-anycast-server$2 pkill -f "python3"
        sleep 2
        ./anycast-route-manager.sh
        ;;
    "status")
        echo "=== ANYCAST STATUS ==="
        for server in 1 2 3; do
            status=$(sudo docker exec clab-anycast-network-anycast-server$server ps aux | grep python | grep -v grep | wc -l)
            echo "Server$server: $([ $status -eq 1 ] && echo "🟢 RUNNING" || echo "🔴 STOPPED")"
        done
        echo -e "\n=== ROUTES ==="
        echo "Router1:"
        sudo docker exec clab-anycast-network-router1 ip route show | grep $ANYCAST_IP || echo "  No routes"
        echo "Router2:"
        sudo docker exec clab-anycast-network-router2 ip route show | grep $ANYCAST_IP || echo "  No routes"
        ;;
    "test")
        echo "=== ANYCAST TEST ==="
        for client in 1 2; do
            echo "Client$client:"
            for i in {1..3}; do
                response=$(sudo docker exec clab-anycast-network-client$client curl -s --connect-timeout 2 http://$ANYCAST_IP:8080 | head -1)
                echo "  $([ -n "$response" ] && echo "✅ $response" || echo "❌ FAILED")"
            done
        done
        ;;
    "demo")
        ./working-flip-demo.sh
        ;;
    "monitor")
        echo "Starting anycast monitor (Ctrl+C to stop)..."
        while true; do
            clear
            ./anycast-auto-manager.sh status
            echo -e "\nPress Ctrl+C to stop monitoring"
            sleep 5
        done
        ;;
    *)
        echo "Usage: $0 {start|stop <server_num>|status|test|demo|monitor}"
        echo ""
        echo "Examples:"
        echo "  $0 status          - Show server status and routes"
        echo "  $0 test            - Test anycast connectivity"
        echo "  $0 stop 1          - Stop server 1 and update routes"
        echo "  $0 start 1         - Start server 1 and update routes" 
        echo "  $0 demo            - Run complete flip demo"
        echo "  $0 monitor         - Continuous monitoring"
        ;;
esac
EOF

chmod +x anycast-auto-manager.sh
clear
# First, update all routes based on current server status
./anycast-route-manager.sh
# Test the current state
./anycast-auto-manager.sh status
./anycast-auto-manager.sh test
# Run the complete working demo
./working-flip-demo.sh
./working-flip-demo.sh
clear
./working-flip-demo.sh
clear
ls
./working-flip-demo.sh
clear
clear
ls
clear
git init
git add .
cat > .gitignore << 'EOF'
clab-anycast-network/
containerlab*
*.pcap
*.log
tmp/
EOF

git rm -r --cached clab-anycast-network/ containerlab* 2>/dev/null || true
git status
clear
git commit -m "Initial commit: Complete anycast network simulation with automatic failover"
git config --global user.email "virfiver@gmail.com"
git config --global user.name "vir1517"
git commit -m "Initial commit: Complete anycast network simulation with automatic failover"
git remote add origin https://github.com/vir1517/anycastsimulation.git
git push -u origin main
git push -u origin master
git push -u origin main
clear
git branch -a
git branch -M main
git push -u origin main
