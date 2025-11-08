#!/bin/bash

echo "=== MANUAL FAILOVER DEMONSTRATION ==="
echo ""

# Function to check which nodes have BIRD running
check_active_nodes() {
  ACTIVE_NODES=""
  for i in 1 2 3; do
    if docker exec anycast${i} pgrep bird > /dev/null 2>&1; then
      ACTIVE_NODES="$ACTIVE_NODES $i"
    fi
  done
  echo "$ACTIVE_NODES"
}

# Function to restore a node
restore_node() {
  local NODE=$1
  echo "Restoring Node $NODE..."
  docker exec anycast${NODE} ip addr add 172.20.255.1/32 dev lo 2>/dev/null || true
  docker exec anycast${NODE} mkdir -p /run/bird 2>/dev/null
  docker exec -d anycast${NODE} bird -c /etc/bird/bird.conf -d 2>/dev/null
  docker exec anycast${NODE} service nginx start 2>&1 | grep -v "already"
}

# Check current state
echo "Checking system state..."
ACTIVE_NODES=$(check_active_nodes)
echo "Active nodes (with BIRD running):$ACTIVE_NODES"
echo ""

# Show current active node
echo "Current active node:"
CURRENT=$(docker exec client curl -s http://172.20.255.1 2>/dev/null)
if [ -z "$CURRENT" ]; then
  echo "ERROR: No node is responding! Need to restore at least one node."
  echo ""
  echo "Available restore commands:"
  echo "  Node 1: restore_node 1"
  echo "  Node 2: restore_node 2"
  echo "  Node 3: restore_node 3"
  echo ""
  read -p "Which node to restore? (1/2/3): " RESTORE_CHOICE
  restore_node $RESTORE_CHOICE
  echo ""
  echo "Waiting for BGP..."
  sleep 8
  CURRENT=$(docker exec client curl -s http://172.20.255.1)
fi

echo "$CURRENT"
CURRENT_NODE=$(echo "$CURRENT" | grep -oP 'NODE \K[0-9]')
echo ""

# Show all routes
echo "All available routes:"
docker exec client birdc show route for 172.20.255.1
echo ""

read -p "Press ENTER to fail Node $CURRENT_NODE..."

# Fail current node
echo ""
echo "Failing Node $CURRENT_NODE..."
docker exec anycast${CURRENT_NODE} pkill -9 bird
echo ""

# Show real-time failover
echo "Watching failover (15 seconds):"
docker exec client bash -c 'for i in {1..15}; do RESP=$(curl -s http://172.20.255.1 2>/dev/null); if [ -z "$RESP" ]; then echo "$(date +%T) - FAILED/SWITCHING..."; else echo "$(date +%T) - $RESP"; fi; sleep 1; done'
echo ""

# Show new state
echo "New active node:"
NEW=$(docker exec client curl -s http://172.20.255.1 2>/dev/null)
if [ -z "$NEW" ]; then
  echo "ERROR: No nodes left! All nodes are down."
  echo "Need to restore at least one node manually."
  exit 1
fi
echo "$NEW"
NEW_NODE=$(echo "$NEW" | grep -oP 'NODE \K[0-9]')
echo ""

echo "Updated routing table:"
docker exec client birdc show route for 172.20.255.1
echo ""

# Check which nodes are down
echo "Checking for failed nodes..."
FAILED_NODES=""
for i in 1 2 3; do
  if ! docker exec anycast${i} pgrep bird > /dev/null 2>&1; then
    FAILED_NODES="$FAILED_NODES $i"
  fi
done

if [ -z "$FAILED_NODES" ]; then
  echo "All nodes are running. Demonstration complete!"
  exit 0
fi

echo "Failed nodes:$FAILED_NODES"
echo ""

read -p "Press ENTER to restore failed node(s) and bring them back online..."

# Restore all failed nodes
for NODE in $FAILED_NODES; do
  echo ""
  restore_node $NODE
done

echo ""
echo "Waiting for BGP to establish..."
sleep 10
echo ""

echo "BGP Status:"
docker exec client birdc show protocols | grep anycast
echo ""

echo "All routes now available:"
docker exec client birdc show route for 172.20.255.1
echo ""

echo "Testing traffic distribution (may stay on current node or switch based on routing):"
for i in {1..8}; do
  docker exec client curl -s http://172.20.255.1
  sleep 1
done
echo ""

echo "Final system state:"
ACTIVE_NODES=$(check_active_nodes)
echo "Active nodes:$ACTIVE_NODES"
echo ""

echo "=== DEMONSTRATION COMPLETE ==="
echo ""
echo "Quick commands for manual testing:"
echo "  - Fail a node: docker exec anycastX pkill -9 bird"
echo "  - Check status: docker exec client curl -s http://172.20.255.1"
echo "  - View routes: docker exec client birdc show route for 172.20.255.1"
