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
