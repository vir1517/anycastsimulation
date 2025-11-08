#!/bin/bash

echo "========================================="
echo "ANYCAST NETWORK DEMONSTRATION"
echo "========================================="
echo ""

# Function to wait with progress
wait_with_progress() {
  local duration=$1
  local message=$2
  echo -n "$message"
  for i in $(seq 1 $duration); do
    echo -n "."
    sleep 1
  done
  echo " Done!"
}

echo "Step 1: Starting containers..."
docker start anycast1 anycast2 anycast3 client > /dev/null 2>&1
wait_with_progress 2 "Waiting for containers"

echo ""
echo "Step 2: Starting BIRD (BGP daemon) on all nodes..."
docker exec anycast1 mkdir -p /run/bird 2>/dev/null
docker exec anycast2 mkdir -p /run/bird 2>/dev/null
docker exec anycast3 mkdir -p /run/bird 2>/dev/null
docker exec client mkdir -p /run/bird 2>/dev/null

docker exec -d anycast1 bird -c /etc/bird/bird.conf -d 2>/dev/null
docker exec -d anycast2 bird -c /etc/bird/bird.conf -d 2>/dev/null
docker exec -d anycast3 bird -c /etc/bird/bird.conf -d 2>/dev/null
docker exec -d client bird -c /etc/bird/bird.conf -d 2>/dev/null

wait_with_progress 10 "Waiting for BGP to establish"

echo ""
echo "Step 3: Configuring anycast IPs..."
docker exec anycast1 ip addr add 172.20.255.1/32 dev lo 2>/dev/null || true
docker exec anycast2 ip addr add 172.20.255.1/32 dev lo 2>/dev/null || true
docker exec anycast3 ip addr add 172.20.255.1/32 dev lo 2>/dev/null || true

echo ""
echo "Step 4: Starting web services..."
docker exec anycast1 service nginx start 2>&1 | grep -v "already"
docker exec anycast2 service nginx start 2>&1 | grep -v "already"
docker exec anycast3 service nginx start 2>&1 | grep -v "already"

echo ""
echo "========================================="
echo "NETWORK ARCHITECTURE"
echo "========================================="
echo "Anycast IP: 172.20.255.1 (advertised by all 3 nodes)"
echo "Node 1: 172.20.0.11"
echo "Node 2: 172.20.0.12"
echo "Node 3: 172.20.0.13"
echo "Client: 172.20.0.100"
echo ""

echo "========================================="
echo "BGP ROUTING STATUS"
echo "========================================="
docker exec client birdc show protocols
echo ""

echo "All routes to anycast IP (showing redundancy):"
docker exec client birdc show route for 172.20.255.1
echo ""

echo "========================================="
echo "CURRENT ACTIVE NODE"
echo "========================================="
echo "Testing which node is currently serving traffic:"
RESPONSE=$(docker exec client curl -s http://172.20.255.1)
echo "$RESPONSE"
echo ""

echo "========================================="
echo "STARTING REAL-TIME MONITORING"
echo "========================================="
docker exec client rm -f /tmp/monitor.log 2>/dev/null
docker exec -d client bash -c 'while true; do echo "$(date +%T) - $(curl -s http://172.20.255.1 2>/dev/null)"; sleep 1; done >> /tmp/monitor.log 2>&1'

wait_with_progress 5 "Collecting baseline traffic"
echo ""
echo "Last 5 requests:"
docker exec client tail -5 /tmp/monitor.log
echo ""

read -p "Press ENTER to simulate node failure and watch anycast flip..."

echo ""
echo "========================================="
echo "SIMULATING NODE FAILURE"
echo "========================================="

# Determine active node and fail it
ACTIVE_NODE=$(echo "$RESPONSE" | grep -oP 'NODE \K[0-9]')
echo "Failing Node $ACTIVE_NODE (killing BGP daemon)..."

if [ "$ACTIVE_NODE" == "1" ]; then
  docker exec anycast1 pkill -9 bird
elif [ "$ACTIVE_NODE" == "2" ]; then
  docker exec anycast2 pkill -9 bird
else
  docker exec anycast3 pkill -9 bird
fi

wait_with_progress 10 "Waiting for BGP reconvergence"

echo ""
echo "========================================="
echo "ANYCAST FLIP DETECTED!"
echo "========================================="
echo "Traffic flow during and after failure:"
docker exec client tail -20 /tmp/monitor.log
echo ""

echo "New routing table (failed node removed):"
docker exec client birdc show route for 172.20.255.1
echo ""

echo "========================================="
echo "DEMONSTRATION COMPLETE"
echo "========================================="
echo ""
echo "To continue monitoring: docker exec client tail -f /tmp/monitor.log"
echo "To check BGP status: docker exec client birdc show protocols"
echo "To restore failed node: See restoration commands in README"
