import asyncio
import websockets
import json

# --- CONFIGURATION ---
# We use your PC's Hotspot IP so the phone can find it
HOST = "192.168.137.1" 
PORT = 9090  # We use 9090 to avoid conflicts with your PHP server (8080)

print(f"🤖 Mock ESP32 Started on ws://{HOST}:{PORT}")

# --- MOCK DATA (Matches your Architecture Doc) ---
DEVICE_INFO_RESPONSE = {
    "event": "device_info",
    "timestamp": "2025-01-15T10:30:00Z",
    "device_id": "dev0016"
}

# Response when app asks for status
VALVE_DATA_RESPONSE = {
    "event": "valve_data",
    "timestamp": "2025-01-15T10:30:00Z",
    "device_id": "dev0016",
    "get_controller": { "schedule": True, "sensor": False },
    "get_valvedata": { "angle": 45, "is_open": True, "is_close": False },
    "get_limitdata": { "is_open_limit": True, "open_limit": False, "is_close_limit": False, "close_limit": True },
    "Error": ""
}

async def esp32_handler(websocket):
    print(f"📱 Phone Connected!")
    
    try:
        async for message in websocket:
            print(f"\n📩 Received: {message}")
            data = json.loads(message)
            event = data.get("event")
            response = None
            
            # 1. Identify the Device (Architecture Doc)
            if event == "request_device_info":
                print("   ➡ Event: Request Device Info")
                response = DEVICE_INFO_RESPONSE
                
            # 2. Get Valve Status (Architecture Doc)
            elif event == "device_basic_info":
                print("   ➡ Event: Request Valve Data")
                response = VALVE_DATA_RESPONSE
            
            # 3. Set WiFi Credentials (Architecture Doc)
            elif event == "set_valve_wifi":
                print("   ➡ Event: WiFi Credentials Received")
                wifi_data = data.get("wifi_data", {})
                print(f"   ✅ Connecting to WiFi: {wifi_data.get('ssid')}...")
                # Real ESP32 would restart here
                response = {"event": "wifi_set_success", "message": "Credentials received."}

            # Send Response
            if response:
                json_response = json.dumps(response)
                await websocket.send(json_response)
                print(f"📤 Sent: {json_response}")

    except websockets.exceptions.ConnectionClosed:
        print("🔴 Phone Disconnected")

async def main():
    print("📡 Waiting for App to connect...")
    async with websockets.serve(esp32_handler, HOST, PORT):
        await asyncio.Future()  # Run forever

if __name__ == "__main__":
    asyncio.run(main())