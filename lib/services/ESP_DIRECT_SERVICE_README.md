# EspDirectService — Complete Function Guide

**File:** `lib/services/esp_direct_service.dart`  
**Purpose:** Handles direct WebSocket communication with the ESP32 microcontroller when the phone is connected to the valve's WiFi hotspot. No server, no internet, no database — just phone ↔ valve on a local network.  
**Type:** Singleton instance (one shared instance accessed via `EspDirectService.instance`).

---

## How This File Fits in the App

```
                    ┌──────────────────┐
                    │   ESP32 Valve     │
                    │  192.168.4.1:80   │
                    └────────┬─────────┘
                             │
                  WebSocket at /ws path
                  Passkey auth ("12345")
                             │
                    ┌────────▼─────────┐
                    │ EspDirectService  │
                    │   (singleton)     │
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
     connectionStream  deviceInfoStream  valveDataStream
              │              │              │
         HomeScreen     HomeScreen    DeviceDetailScreen
     (shows "Direct    (gets device   (valve controls,
      Connected")       ID after       angle, open/close)
                        auth)
```

---

## How Direct Mode Is Different from Server Mode

| | Server Mode | Direct Mode |
|---|---|---|
| **Network** | Phone → Internet → Cloud Server → MQTT → ESP32 | Phone → Valve's WiFi hotspot → ESP32 |
| **Service used** | WebSocketService | EspDirectService |
| **Connection** | ws://82.29.161.52:8084 | ws://192.168.4.1:80/ws |
| **Auth method** | JWT token in header | Passkey "12345" in message |
| **Data updates** | Server pushes every 2 seconds | App polls every 2 seconds |
| **Who sends commands** | REST API (control_device.php) | EspDirectService (direct to valve) |
| **Internet needed** | Yes | No |
| **Schedule/Sensor** | Available | Not available |

---

## Why Singleton Instead of Static?

WebSocketService uses static methods and variables. EspDirectService uses a singleton pattern instead:

```dart
static EspDirectService? _instance;
static EspDirectService get instance => _instance ??= EspDirectService._();
```

This is because the service needs to track **per-connection state** like `connectedDeviceId` and `isAuthenticated`. With static, these would be class-level and harder to reset cleanly. The singleton pattern gives a proper instance that can be fully reset on disconnect.

**How it's accessed everywhere:**
```dart
EspDirectService.instance.connect();
EspDirectService.instance.authenticate(passkey: '12345');
EspDirectService.instance.setValveAngle(angle: 90);
EspDirectService.instance.isConnected;  // true or false
```

---

## Configuration Constants

```dart
defaultApIp = '192.168.4.1'    // ESP32's default gateway IP in AP mode
defaultPort = 80                // ESP32 httpd server port
wsPath = '/ws'                  // WebSocket handler URI registered in C firmware
```

**Why these values?**

- `192.168.4.1` — When the ESP32 creates a WiFi hotspot, it always assigns itself this IP. It's hardcoded in the ESP-IDF framework.
- Port `80` — The ESP32 runs a standard HTTP server (httpd). The WebSocket handler is registered on this same server.
- `/ws` — The path where the WebSocket handler is registered in the C firmware (`websocket_server_fn.c → start_webserver()`).

The full URL becomes: `ws://192.168.4.1:80/ws`

---

## State Variables

### `_channel` (WebSocketChannel?, instance)
The WebSocket connection to the ESP32. `null` when not connected.

**Why WebSocketChannel (not IOWebSocketChannel)?**  
Unlike the server WebSocket, ESP32 doesn't need JWT in headers. Auth is done by sending a passkey in a message after connecting. So the simpler `WebSocketChannel.connect()` works fine.

### `_isConnected` (bool)
`true` when WebSocket connection is open and ready.

### `_isAuthenticated` (bool)
`true` after the ESP32 has verified the passkey and responded with `device_info`. 

**This is critical:** The ESP32 firmware silently ignores ALL commands until the passkey is verified. If you send `set_valve_basic` before authenticating, nothing happens — the valve won't move, no error is returned, the message is just dropped.

### `_connectedDeviceIp` (String?)
The IP address of the connected ESP32. Usually `192.168.4.1` in AP mode.

### `_connectedDeviceId` (String?)
The device ID received from the ESP32 after authentication (e.g., `"VA202601001"`). This is set when the ESP32 responds with `device_info`.

---

## Stream Controllers

All streams are **broadcast** — multiple listeners can subscribe.

### `connectionStream` → Stream\<bool\>
Emits `true` on connect, `false` on disconnect.

**Who listens:**
- HomeScreen — updates the ESP status indicator in debug panel
- DeviceDetailScreen — shows connection icon color

### `deviceInfoStream` → Stream\<Map\>
Emits the ESP32's authentication response containing the device ID.

**Who listens:**  
HomeScreen (`_setupEspListeners`) — receives the device ID, matches it with the cached device list, injects the `_esp_connected` flag, shows "Direct Connected" on the card.

**Example data:**
```json
{
  "event": "device_info",
  "timestamp": "1970-01-01T00:13:09",
  "device_id": "VA202601001"
}
```

**Note:** The timestamp from ESP32 is often `1970-01-01...` because the ESP32 doesn't have a real-time clock and starts counting from epoch on boot.

### `valveDataStream` → Stream\<Map\>
Emits the full valve state when requested.

**Who listens:**  
DeviceDetailScreen (`_setupEspDirect`) — maps ESP32 fields to server DB field equivalents so all UI logic works in both modes.

**Example data:**
```json
{
  "event": "valve_data",
  "timestamp": "1970-01-01T00:15:22",
  "device_id": "VA202601001",
  "get_controller": {
    "schedule": false,
    "sensor": false
  },
  "get_valvedata": {
    "angle": 90,
    "is_open": true,
    "is_close": false
  },
  "get_limitdata": {
    "upper": 90,
    "lower": 0
  },
  "Error": ""
}
```

**How DeviceDetailScreen maps this to server fields:**
```dart
// ESP32 sends:          // App maps to:
angle          →         _device['vwv_pos'] = "90"
is_open        →         _device['vwv_is_open'] = 1
is_close       →         _device['vwv_is_close'] = 0
```

This mapping allows the same UI code (`_getActualPosition()`, `_isValveOpen()`, confirmation check) to work identically in both server and direct mode.

### `errorStream` → Stream\<Map\>
Emits error broadcasts from the ESP32.

**Who listens:** HomeScreen debug panel — logs errors.

**Example data:**
```json
{
  "event": "valve_error",
  "timestamp": "...",
  "device_id": "VA202601001",
  "error": "Motor stall detected"
}
```

---

## Functions

---

### `connect({ip, port})` → Future\<bool\>

**What it does:**  
Opens a WebSocket connection to the ESP32.

**When it's called:**
- By `connectAndAuthenticate()` (which is called by HomeScreen `_connectToEsp32()`)
- By HomeScreen debug panel "Connect ESP" button

**Parameters:**
- `ip` — Default `192.168.4.1` (ESP32 AP gateway)
- `port` — Default `80` (ESP32 httpd port)

**How it works step by step:**

1. Disconnect any existing connection first (`await disconnect()`)
2. Build the WebSocket URI: `ws://192.168.4.1:80/ws`
3. Call `WebSocketChannel.connect(uri)`
4. Await `_channel.ready` (waits for connection to establish)
5. Set `_isConnected = true`, `_isAuthenticated = false`
6. Save `_connectedDeviceIp`
7. Emit `true` to `connectionStream`
8. Set up stream listener with `_handleMessage`, `onError`, `onDone`
9. Return `true`

**On failure:** Calls `_handleDisconnect()` and returns `false`.

**Important:** After `connect()` succeeds, `_isAuthenticated` is `false`. You MUST call `authenticate()` before sending any commands. The ESP32 will ignore everything until the passkey is verified.

---

### `disconnect()` → Future\<void\>

**What it does:**  
Closes the WebSocket connection and resets all state.

**When it's called:**
- By `connect()` before establishing a new connection (ensures clean state)
- By HomeScreen when switching from direct mode to server mode
- By `dispose()`

**How it works:**

1. If `_channel` is not null, close it with `goingAway` status code
2. Set `_channel = null`
3. Call `_handleDisconnect()` to reset all flags

---

### `_handleDisconnect()`

**What it does:**  
Resets all connection state to defaults.

**How it works:**

1. `_isConnected = false`
2. `_isAuthenticated = false`
3. `_connectedDeviceIp = null`
4. `_connectedDeviceId = null`
5. Emit `false` to `connectionStream`

**Note:** Unlike WebSocketService, there is **no auto-reconnect**. If the connection drops, the user must reconnect manually (or the app will reconnect when it detects the hotspot SSID again via `_checkWifiConnection()`).

---

### `authenticate({passkey, userId})`

**What it does:**  
Sends the authentication message to the ESP32. This MUST be the first thing sent after connecting.

**When it's called:**
- By `connectAndAuthenticate()` immediately after a successful `connect()`
- By HomeScreen `_setupEspListeners()` when connection is established

**Parameters:**
- `passkey` (required) — Must match ESP32's `CONFIG_WS_PASSKEY_VALUE` (default: `"12345"`)
- `userId` (optional) — Defaults to `"app_user"`

**What it sends:**
```json
{
  "event": "request_device_info",
  "timestamp": "2026-04-05T10:30:00.000Z",
  "user_id": "app_user",
  "passkey": "12345"
}
```

**What ESP32 responds with (if passkey is correct):**
```json
{
  "event": "device_info",
  "timestamp": "1970-01-01T00:13:09",
  "device_id": "VA202601001"
}
```

**What happens when response arrives:**  
`_handleMessage()` receives it → sets `_isAuthenticated = true` → stores `_connectedDeviceId = "VA202601001"` → emits to `deviceInfoStream` → HomeScreen listener picks it up and sets `_esp_connected = true` on the matching device card.

**If passkey is wrong:**  
The ESP32 simply doesn't respond. No error message, no connection close — just silence. The app stays connected but `_isAuthenticated` remains `false`, so all command methods will refuse to send.

---

### `requestValveData({userId, deviceId, deviceName})`

**What it does:**  
Asks the ESP32 to send back the full valve state (position, open/close status, controller mode, limits, errors).

**When it's called:**
- By DeviceDetailScreen `_requestEspValveData()` on initial load
- By DeviceDetailScreen's 2-second poll timer
- By HomeScreen debug panel "Request Info" button

**Guards:**  
If `_isAuthenticated` is `false`, prints warning and returns without sending.

**What it sends:**
```json
{
  "event": "device_basic_info",
  "timestamp": "2026-04-05T10:30:00.000Z",
  "data": {
    "user_id": "5",
    "device_id": "VA202601001",
    "device_name": "MainValve01"
  }
}
```

**What ESP32 responds with:**
```json
{
  "event": "valve_data",
  "device_id": "VA202601001",
  "get_controller": { "schedule": false, "sensor": false },
  "get_valvedata": { "angle": 90, "is_open": true, "is_close": false },
  "get_limitdata": { "upper": 90, "lower": 0 },
  "Error": ""
}
```

**Architecture Doc Reference:** Page 11 — device_basic_info request format.

**Important:** Unlike the server WebSocket which pushes data automatically every 2 seconds, the ESP32 only sends data **when asked**. That's why DeviceDetailScreen runs a `Timer.periodic` every 2 seconds to keep polling.

---

### `setValveAngle({angle, deviceName})`

**What it does:**  
Commands the ESP32 to move the valve to a specific angle (0° = fully closed, 90° = fully open).

**When it's called:**
- By DeviceDetailScreen `_sendControlCommand()` in direct mode
- By DeviceDetailScreen `_sendAngleCommand()` in direct mode
- By `openValve()` and `closeValve()` convenience methods

**Parameters:**
- `angle` (required) — Value between 0 and 90. Automatically clamped with `.clamp(0, 90)`
- `deviceName` (optional) — Defaults to `"Valve"`

**Guards:**  
If `_isAuthenticated` is `false`, prints warning and returns without sending.

**What it sends:**
```json
{
  "event": "set_valve_basic",
  "timestamp": "2026-04-05T10:30:00.000Z",
  "device_id": "VA202601001",
  "set_controller": { "schedule": false, "sensor": false },
  "valve_data": {
    "name": "MainValve01",
    "set_angle": true,
    "angle": 45
  },
  "ota_update": false
}
```

**What happens physically:**  
The ESP32 receives this, drives the motor to the specified angle, and updates its internal state. On the next `requestValveData()` call (2 seconds later from the poll timer), the new angle will be reflected in the response.

**Architecture Doc Reference:** Page 12 — set_valve_basic command format.

**Important note about the ESP32 firmware:**  
The ESP32 ignores fields it doesn't recognize. So sending extra fields doesn't cause errors — but sending WRONG field names for fields it DOES expect will cause the command to be silently ignored. Always match the exact field names from the architecture doc.

---

### `openValve({deviceName})`

**What it does:**  
Opens the valve fully. Convenience wrapper that calls `setValveAngle(angle: 90)`.

**When it's called:**  
By HomeScreen debug panel "Open Valve" button.

---

### `closeValve({deviceName})`

**What it does:**  
Closes the valve fully. Convenience wrapper that calls `setValveAngle(angle: 0)`.

**When it's called:**  
By HomeScreen debug panel "Close Valve" button.

---

### `setWifiCredentials({ssid, password})`

**What it does:**  
Sends home WiFi credentials to the ESP32 so it can connect to the user's network and go online.

**When it's called:**  
By DeviceDetailScreen `_showWifiCredentialsDialog()` when the user enters WiFi name and password.

**Parameters:**
- `ssid` (required) — The home/office WiFi network name
- `password` (required) — The WiFi password

**Guards:**  
If `_isAuthenticated` is `false`, prints warning and returns without sending.

**What it sends:**
```json
{
  "event": "set_valve_wifi",
  "timestamp": "2026-04-05T10:30:00.000Z",
  "device_id": "VA202601001",
  "wifi_data": {
    "ssid": "MyHomeWiFi",
    "password": "wifi_password_123"
  }
}
```

**⚠️ WARNING: After receiving this, the ESP32 will:**
1. Save the credentials to its non-volatile storage (NVS)
2. **Restart itself**
3. Boot up and connect to the provided WiFi network
4. The WebSocket connection **will be lost** (valve is restarting)
5. The valve's hotspot disappears (it's now on home WiFi)
6. The valve starts reporting to the cloud server
7. It appears as "Online" in the app once the phone switches back to home WiFi

**Architecture Doc Reference:** Page 13 — set_valve_wifi format.

---

### `connectAndAuthenticate({ip, port, passkey})` → Future\<bool\>

**What it does:**  
Convenience method that combines `connect()` and `authenticate()` into one call.

**When it's called:**  
By HomeScreen `_connectToEsp32()` when the app detects the valve hotspot.

**How it works:**

1. Call `connect(ip: ip, port: port)`
2. If connected → call `authenticate(passkey: passkey)`
3. Return `true` if connection succeeded

**Important:** This returns `true` when the **connection** is established and the auth **message was sent**. It does NOT wait for the ESP32's `device_info` response. To know if authentication actually succeeded, listen to `deviceInfoStream`.

```dart
// Usage:
final sent = await EspDirectService.instance.connectAndAuthenticate(passkey: '12345');
// sent == true means: connected + auth message sent
// BUT _isAuthenticated is still false at this point!

// Authentication is confirmed asynchronously:
EspDirectService.instance.deviceInfoStream.listen((data) {
    // NOW _isAuthenticated is true
    // data['device_id'] contains the valve ID
});
```

---

### `requestCurrentValveData({userId})`

**What it does:**  
Convenience method that calls `requestValveData()` using the stored `_connectedDeviceId`. Saves you from having to pass the device ID every time.

**When it's called:**  
Not currently used in the app (available for future use). DeviceDetailScreen calls `requestValveData()` directly instead.

---

### `_handleMessage(message)`

**What it does:**  
Routes every incoming message from the ESP32 to the correct stream controller based on the `"event"` field.

**When it's called:**  
Every time the ESP32 sends a WebSocket message.

**How it works:**

1. Parse JSON from the message
2. Read the `event` field
3. Route by event type:

| Event | Action | Result |
|-------|--------|--------|
| `device_info` | Set `_isAuthenticated = true`, store `_connectedDeviceId`, emit to `deviceInfoStream` | HomeScreen shows "Direct Connected" |
| `valve_data` | Emit to `valveDataStream` | DeviceDetailScreen updates valve position |
| `valve_error` | Emit to `errorStream` | Error gets logged |
| Unknown | Print warning | Nothing |

---

### `_send(data)`

**What it does:**  
Internal helper that converts a Map to JSON and sends it through the WebSocket channel.

**Guards:**  
If not connected (`_isConnected == false` or `_channel == null`), prints warning and returns without sending.

**Used by:** `authenticate()`, `requestValveData()`, `setValveAngle()`, `setWifiCredentials()`

---

### `dispose()`

**What it does:**  
Permanently shuts down the service — disconnects and closes all stream controllers.

**When it's called:**  
Typically never in practice. Available for app cleanup.

---

## Complete Flow Diagrams

### Initial Connection (Phone connects to valve hotspot)

```
User connects phone WiFi to "Vortex_VA202601001"
       │
       ▼
HomeScreen._checkWifiConnection()
       │
       ├── SSID = "Vortex_VA202601001"
       ├── Starts with "Vortex_VA"? → YES
       └── _isEspApMode = true
              │
              ▼
       _connectToEsp32()
              │
              ▼
EspDirectService.connectAndAuthenticate(passkey: '12345')
       │
       ├── connect(ip: 192.168.4.1, port: 80)
       │       │
       │       └── WebSocket opens to ws://192.168.4.1:80/ws
       │           _isConnected = true
       │           connectionStream emits true
       │
       └── authenticate(passkey: '12345')
               │
               └── Sends: {"event":"request_device_info","passkey":"12345"}
                          │
                          ▼
                   ESP32 checks passkey
                          │
                          ├── Correct → responds: {"event":"device_info","device_id":"VA202601001"}
                          │       │
                          │       ▼
                          │   _handleMessage()
                          │       │
                          │       ├── _isAuthenticated = true
                          │       ├── _connectedDeviceId = "VA202601001"
                          │       └── deviceInfoStream emits data
                          │               │
                          │               ▼
                          │       HomeScreen listener
                          │               │
                          │               ├── Find "VA202601001" in _devices list
                          │               ├── Set _esp_connected = true on that device
                          │               └── Card shows "Direct Connected" (green)
                          │
                          └── Wrong passkey → ESP32 stays silent
                                  │
                                  └── _isAuthenticated stays false
                                      All commands are blocked
```

### Controlling the Valve in Direct Mode

```
User taps "Direct Connected" device card
       │
       ▼
DeviceDetailScreen(deviceData: device, isDirectMode: true)
       │
       ▼
initState() → _isDirectMode = true → _setupEspDirect()
       │
       ├── Listen to valveDataStream
       │       │
       │       └── Maps ESP32 fields → server fields:
       │           angle → vwv_pos
       │           is_open → vwv_is_open
       │           is_close → vwv_is_close
       │
       ├── Request initial valve data from ESP32
       │
       └── Start 2-second poll timer
               │
               └── Every 2 seconds: requestValveData() → ESP32 responds → valveDataStream → UI updates


User taps "Open" button:
       │
       ▼
_sendControlCommand("Open")
       │
       ├── _isDirectMode == true
       │
       └── EspDirectService.instance.setValveAngle(angle: 90)
               │
               └── Sends: {"event":"set_valve_basic","valve_data":{"set_angle":true,"angle":90}}
                          │
                          ▼
                   ESP32 drives motor to 90°
                          │
                          ▼
               Next poll (2 seconds later)
                          │
                          ▼
               requestValveData() → ESP32 responds with angle: 90
                          │
                          ▼
               valveDataStream → DeviceDetailScreen updates UI
                          │
                          └── Valve shows as "Open" at 90°
```

### WiFi Setup (Provisioning valve to home network)

```
User opens WiFi credentials dialog in DeviceDetailScreen
       │
       ▼
Enters SSID: "MyHomeWiFi" and password: "secret123"
       │
       ▼
EspDirectService.instance.setWifiCredentials(ssid: "MyHomeWiFi", password: "secret123")
       │
       └── Sends: {"event":"set_valve_wifi","wifi_data":{"ssid":"MyHomeWiFi","password":"secret123"}}
                  │
                  ▼
           ESP32 saves credentials to NVS
                  │
                  ▼
           ESP32 RESTARTS ← WebSocket connection is lost here!
                  │
                  ▼
           ESP32 boots up → connects to "MyHomeWiFi"
                  │
                  ▼
           ESP32 starts sending heartbeats to cloud server
                  │
                  ▼
           Server sets vwv_last_seen → Valve appears "Online"
                  │
                  ▼
           User reconnects phone to home WiFi
                  │
                  ▼
           App detects normal WiFi → switches to server mode
                  │
                  ▼
           HomeScreen shows device as "Online" (green)
```

---

## Important Rules from ESP32 Firmware

1. **Always authenticate first.** The ESP32 ignores all events except `request_device_info` until a valid passkey is received.

2. **ESP32 doesn't push data.** Unlike the server WebSocket, the ESP32 only sends data when asked. The app must poll with `requestValveData()`.

3. **ESP32 ignores unknown fields.** You can send extra fields and they won't cause errors. But if you misspell a field the ESP32 DOES expect (e.g., `set_angel` instead of `set_angle`), the command is silently ignored.

4. **Wrong passkey = silence.** The ESP32 doesn't send an error for wrong passkeys. It just doesn't respond. The app stays connected but unauthenticated.

5. **`setWifiCredentials` restarts the ESP32.** The WebSocket connection will drop. The valve's hotspot will disappear. This is expected and permanent — the valve is now on the home network.

6. **No auto-reconnect.** Unlike WebSocketService (which has 5-attempt auto-reconnect), EspDirectService does NOT auto-reconnect. If the connection drops, the app relies on `_checkWifiConnection()` to detect the hotspot SSID and reconnect.

---

## Who Calls What — Quick Reference

| Caller | Method | When |
|--------|--------|------|
| HomeScreen `_connectToEsp32()` | `connectAndAuthenticate()` | Valve hotspot detected |
| HomeScreen `_setupEspListeners()` | `authenticate()` | Connection established |
| HomeScreen debug panel | `connect()`, `openValve()`, `closeValve()`, `requestValveData()` | Debug buttons tapped |
| DeviceDetailScreen `_setupEspDirect()` | `valveDataStream.listen()` | Screen opens in direct mode |
| DeviceDetailScreen `_requestEspValveData()` | `requestValveData()` | Initial load + every 2 seconds |
| DeviceDetailScreen `_sendControlCommand()` | `setValveAngle()` | User taps Open/Close |
| DeviceDetailScreen `_sendAngleCommand()` | `setValveAngle()` | User sets specific angle |
| DeviceDetailScreen `_showWifiCredentialsDialog()` | `setWifiCredentials()` | User enters home WiFi |
| HomeScreen `_restoreEspState()` | `isConnected`, `isAuthenticated`, `connectedDeviceId` | Tab switch in IndexedStack |

---

*Document Version: April 2026 — Vortex Labs Official*
