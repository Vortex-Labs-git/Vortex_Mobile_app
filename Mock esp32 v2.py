#!/usr/bin/env python3
"""
Mock ESP32 WebSocket Server for Vortex Labs
Message structure follows Vortex_WiFi_Valve_Software_Architecture.pdf

Run: python mock_esp32_v2.py
Listens on: ws://0.0.0.0:9090
"""

import asyncio
import websockets
import json
from datetime import datetime, timezone
import random

# Device state simulation
device_state = {
    "device_id": "dev0016",
    "device_name": "VortexValve_001",
    "valve_angle": 0,
    "is_open": False,
    "is_close": True,
    "schedule_enabled": False,
    "sensor_enabled": False,
    "is_ap_mode": True,
    "ip_address": "192.168.4.1",
    "sta_ssid": "",
    "sta_connected": False,
}

# Simulated WiFi networks
wifi_networks = [
    {"ssid": "HomeNetwork", "rssi": -45, "secure": True},
    {"ssid": "OfficeWiFi", "rssi": -55, "secure": True},
    {"ssid": "GuestNetwork", "rssi": -65, "secure": False},
    {"ssid": "Neighbor_5G", "rssi": -75, "secure": True},
    {"ssid": "CoffeeShop", "rssi": -80, "secure": True},
]

def get_timestamp():
    """Get ISO 8601 timestamp"""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def create_device_info_response():
    """
    Response to: request_device_info
    Doc Page 10: ESP32 response - device_info
    """
    return {
        "event": "device_info",
        "timestamp": get_timestamp(),
        "device_id": device_state["device_id"],
        "device_name": device_state["device_name"],
        "is_ap_mode": device_state["is_ap_mode"],
        "ip_address": device_state["ip_address"],
    }

def create_valve_data_response():
    """
    Response to: device_basic_info
    Doc Page 11: ESP32 Response Messages - valve_data
    """
    return {
        "event": "valve_data",
        "timestamp": get_timestamp(),
        "device_id": device_state["device_id"],
        "get_controller": {
            "schedule": device_state["schedule_enabled"],
            "sensor": device_state["sensor_enabled"],
        },
        "get_valvedata": {
            "angle": device_state["valve_angle"],
            "is_open": device_state["is_open"],
            "is_close": device_state["is_close"],
        },
        "get_limitdata": {
            "is_open_limit": True,
            "open_limit": device_state["is_open"],
            "is_close_limit": True,
            "close_limit": device_state["is_close"],
        },
        "Error": "",
    }

def create_wifi_scan_response():
    """Response for WiFi scan request"""
    # Randomize RSSI slightly for realism
    networks = []
    for net in wifi_networks:
        networks.append({
            "ssid": net["ssid"],
            "rssi": net["rssi"] + random.randint(-5, 5),
            "secure": net["secure"],
        })
    return {
        "event": "wifi_scan_result",
        "timestamp": get_timestamp(),
        "networks": networks,
    }

def create_wifi_saved_response(ssid):
    """Response after WiFi credentials are saved"""
    return {
        "event": "wifi_saved",
        "timestamp": get_timestamp(),
        "ssid": ssid,
        "message": f"WiFi credentials saved. Device will connect to '{ssid}' on next restart.",
    }

def create_state_update_response():
    """Real-time state update notification"""
    return {
        "event": "state_update",
        "timestamp": get_timestamp(),
        "device_id": device_state["device_id"],
        "valve_state": "Open" if device_state["is_open"] else "Closed",
        "angle": device_state["valve_angle"],
    }

async def handle_message(websocket, message):
    """Process incoming messages from mobile app"""
    global device_state
    
    try:
        data = json.loads(message)
        event = data.get("event", data.get("action", ""))
        
        print(f"\n📨 Received: {event}")
        print(f"   Full message: {json.dumps(data, indent=2)}")
        
        response = None
        
        # Handle different event types based on architecture document
        
        # 1. Request device info (Doc Page 10)
        if event == "request_device_info":
            print("   → Sending device_info response")
            response = create_device_info_response()
        
        # 2. Request valve data (Doc Page 11)
        elif event == "device_basic_info":
            print("   → Sending valve_data response")
            response = create_valve_data_response()
        
        # 3. Set valve basic data (Doc Page 12)
        elif event == "set_valve_basic":
            valve_data = data.get("valve_data", {})
            controller = data.get("set_controller", {})
            
            # Update device state
            if "angle" in valve_data:
                new_angle = valve_data["angle"]
                device_state["valve_angle"] = new_angle
                device_state["is_open"] = new_angle > 0
                device_state["is_close"] = new_angle == 0
                print(f"   → Valve angle set to {new_angle}°")
            
            if "name" in valve_data:
                device_state["device_name"] = valve_data["name"]
                print(f"   → Device name changed to '{valve_data['name']}'")
            
            if "schedule" in controller:
                device_state["schedule_enabled"] = controller["schedule"]
            if "sensor" in controller:
                device_state["sensor_enabled"] = controller["sensor"]
            
            # Send state update
            response = create_state_update_response()
        
        # 4. Set WiFi credentials (Doc Page 13)
        elif event == "set_valve_wifi":
            wifi_data = data.get("wifi_data", {})
            ssid = wifi_data.get("ssid", "")
            password = wifi_data.get("password", "")
            
            device_state["sta_ssid"] = ssid
            print(f"   → WiFi credentials saved: SSID='{ssid}'")
            
            response = create_wifi_saved_response(ssid)
        
        # 5. Scan WiFi networks
        elif event == "scan_wifi":
            print("   → Scanning WiFi networks...")
            await asyncio.sleep(1)  # Simulate scan delay
            response = create_wifi_scan_response()
        
        # 6. Restart device
        elif event == "restart_device":
            print("   → Device restart requested")
            response = {
                "event": "device_restarting",
                "timestamp": get_timestamp(),
                "message": "Device will restart in 3 seconds...",
            }
        
        # Legacy support for old message format
        elif event == "get_info" or data.get("action") == "get_info":
            print("   → [Legacy] Sending device_info response")
            response = create_device_info_response()
        
        elif data.get("action") == "control":
            command = data.get("command", "")
            if command == "open":
                device_state["valve_angle"] = 90
                device_state["is_open"] = True
                device_state["is_close"] = False
            elif command == "close":
                device_state["valve_angle"] = 0
                device_state["is_open"] = False
                device_state["is_close"] = True
            print(f"   → [Legacy] Valve {command}")
            response = create_state_update_response()
        
        elif data.get("action") == "scan_wifi":
            print("   → [Legacy] Scanning WiFi...")
            await asyncio.sleep(1)
            response = create_wifi_scan_response()
        
        elif data.get("action") == "set_wifi":
            ssid = data.get("ssid", "")
            device_state["sta_ssid"] = ssid
            print(f"   → [Legacy] WiFi set: {ssid}")
            response = create_wifi_saved_response(ssid)
        
        else:
            print(f"   ⚠️ Unknown event: {event}")
            response = {
                "event": "error",
                "timestamp": get_timestamp(),
                "message": f"Unknown event: {event}",
            }
        
        if response:
            response_json = json.dumps(response)
            print(f"📤 Sending: {response_json[:100]}...")
            await websocket.send(response_json)
            
    except json.JSONDecodeError as e:
        print(f"❌ JSON Parse Error: {e}")
        error_response = json.dumps({
            "event": "error",
            "timestamp": get_timestamp(),
            "message": f"Invalid JSON: {str(e)}",
        })
        await websocket.send(error_response)

async def handler(websocket, path=None):
    """Handle WebSocket connection"""
    client_ip = websocket.remote_address[0] if websocket.remote_address else "unknown"
    print(f"\n✅ Client connected from {client_ip}")
    
    # Send initial device info on connection
    initial_response = create_device_info_response()
    await websocket.send(json.dumps(initial_response))
    print(f"📤 Sent initial device_info")
    
    try:
        async for message in websocket:
            await handle_message(websocket, message)
    except websockets.exceptions.ConnectionClosed:
        print(f"👋 Client disconnected: {client_ip}")
    except Exception as e:
        print(f"❌ Error: {e}")

async def main():
    """Start the mock ESP32 WebSocket server"""
    host = "0.0.0.0"
    port = 9090
    
    print("=" * 60)
    print("  Vortex Labs - Mock ESP32 WebSocket Server v2.0")
    print("  Message structure: Vortex_WiFi_Valve_Software_Architecture.pdf")
    print("=" * 60)
    print(f"\n🚀 Starting server on ws://{host}:{port}")
    print(f"📱 Device ID: {device_state['device_id']}")
    print(f"📱 Device Name: {device_state['device_name']}")
    print("\nSupported events (Architecture Document):")
    print("  - request_device_info  → device_info")
    print("  - device_basic_info    → valve_data")
    print("  - set_valve_basic      → state_update")
    print("  - set_valve_wifi       → wifi_saved")
    print("  - scan_wifi            → wifi_scan_result")
    print("\nLegacy events (backward compatibility):")
    print("  - action: get_info     → device_info")
    print("  - action: control      → state_update")
    print("  - action: set_wifi     → wifi_saved")
    print("\n⏳ Waiting for connections...")
    print("-" * 60)
    
    async with websockets.serve(handler, host, port):
        await asyncio.Future()  # Run forever

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n\n🛑 Server stopped by user")