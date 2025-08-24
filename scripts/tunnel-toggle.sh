#!/bin/bash

# Cloudflare Tunnel Toggle Script
# Usage: ./tunnel-toggle.sh [on|off|status]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES_DIR="$SCRIPT_DIR/../02-services"
cd "$SERVICES_DIR"

check_status() {
    echo "🔍 Checking tunnel status..."
    
    # Check if deployment exists
    if kubectl get deployment cloudflare-tunnel >/dev/null 2>&1; then
        REPLICAS=$(kubectl get deployment cloudflare-tunnel -o jsonpath='{.spec.replicas}')
        READY=$(kubectl get deployment cloudflare-tunnel -o jsonpath='{.status.readyReplicas}')
        
        if [ "$REPLICAS" = "1" ] && [ "$READY" = "1" ]; then
            echo "✅ Tunnel is ON and running"
            kubectl get pods -l app=cloudflare-tunnel
            echo ""
            echo "📊 Tunnel Metrics: https://tunnel-metrics.cdklein.com/metrics (TinyAuth required)"
        elif [ "$REPLICAS" = "0" ]; then
            echo "❌ Tunnel is OFF (scaled to 0)"
        else
            echo "⚠️  Tunnel deployment exists but not ready (replicas: $REPLICAS, ready: $READY)"
            kubectl get pods -l app=cloudflare-tunnel
        fi
    else
        echo "❌ Tunnel is OFF (no deployment found)"
    fi
}

turn_on() {
    echo "🚀 Turning tunnel ON..."
    
    # Method 1: Scale deployment if it exists
    if kubectl get deployment cloudflare-tunnel >/dev/null 2>&1; then
        echo "📈 Scaling deployment to 1 replica..."
        kubectl scale deployment cloudflare-tunnel --replicas=1
        echo "⏳ Waiting for pod to be ready..."
        kubectl wait --for=condition=ready pod -l app=cloudflare-tunnel --timeout=60s
        echo "✅ Tunnel is now ON"
    else
        echo "🏗️  Creating tunnel resources with Terraform..."
        terraform apply -var="tunnel_enabled=true" -auto-approve
        echo "✅ Tunnel is now ON"
    fi
    
    check_status
}

turn_off() {
    echo "🛑 Turning tunnel OFF..."
    
    # Method 1: Scale deployment to 0 (fastest)
    if kubectl get deployment cloudflare-tunnel >/dev/null 2>&1; then
        echo "📉 Scaling deployment to 0 replicas..."
        kubectl scale deployment cloudflare-tunnel --replicas=0
        echo "✅ Tunnel is now OFF"
    else
        echo "ℹ️  Tunnel is already OFF (no deployment found)"
    fi
    
    check_status
}

destroy_tunnel() {
    echo "💥 Destroying tunnel resources completely..."
    terraform apply -var="tunnel_enabled=false" -auto-approve
    echo "✅ All tunnel resources destroyed"
}

show_help() {
    echo "Cloudflare Tunnel Control Script"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  on        Turn tunnel ON (scale to 1 replica or create resources)"
    echo "  off       Turn tunnel OFF (scale to 0 replicas - fastest)"
    echo "  destroy   Completely destroy all tunnel resources"
    echo "  status    Show current tunnel status"
    echo "  help      Show this help message"
    echo ""
    echo "Quick Methods:"
    echo "  kubectl scale deployment cloudflare-tunnel --replicas=1  # Turn ON"
    echo "  kubectl scale deployment cloudflare-tunnel --replicas=0  # Turn OFF"
    echo ""
    echo "Terraform Methods:"
    echo "  terraform apply -var=\"tunnel_enabled=true\"   # Create/Enable"
    echo "  terraform apply -var=\"tunnel_enabled=false\"  # Destroy"
    echo ""
    echo "Example Usage:"
    echo "  ./scripts/tunnel-toggle.sh on      # Turn on external access"
    echo "  ./scripts/tunnel-toggle.sh off     # Turn off external access"
    echo "  ./scripts/tunnel-toggle.sh status  # Check current status"
}

# Main logic
case "${1:-help}" in
    "on"|"enable"|"start")
        turn_on
        ;;
    "off"|"disable"|"stop")
        turn_off
        ;;
    "destroy"|"remove")
        destroy_tunnel
        ;;
    "status"|"check")
        check_status
        ;;
    "help"|"--help"|"-h")
        show_help
        ;;
    *)
        echo "❌ Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
