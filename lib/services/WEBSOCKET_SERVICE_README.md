# WebSocketService — Complete Function Guide

**File:** `lib/services/websocket_service.dart`  
**Purpose:** Maintains a single persistent WebSocket connection to the Vortex cloud server. All screens share this one connection and receive real-time data through broadcast streams.  
**Type:** Static class (no instances, all methods and variables are static, one global connection for the entire app).

---

## How This File Fits in the App

```
                    ┌─────────────────────┐
                    │   PHP Ratchet Server │
                    │   82.29.161.52:8084  │
                    └──────────┬──────────┘
                               │
                    WebSocket (persistent connection)
                    JWT token in Authorization header
                               │
                    ┌──────────▼──────────┐
                    │  WebSocketService    │
                    │  (single connection) │
                    └──────────┬──────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
    deviceListStream   deviceDetailStream  scheduleStream
              │                │                │
         HomeScreen    DeviceDetailScreen  DeviceDetailScreen
     (shows all valves)  (controls valve)   (schedule data)
```

The app **never sends valve commands** over WebSocket. WebSocket is **read-only** from the app's perspective — the server pushes data, the app listens. All commands (open/close valve, save schedule, change name) go through the REST API (`control_device.php`).

---

## Important Concept: How WebSocket Differs from REST API

| | REST API | WebSocket |
|---|---|---|
| **Direction** | App → Server (app sends commands) | Server → App (server pushes data) |
| **When used** | User taps Open/Close, saves schedule | Continuous — every 2 seconds |
| **Connection** | One-time request/response | Persistent open connection |
| **Example** | POST to control_device.php | Server pushes devices_data event |

---

## Configuration Constants

```dart
_wsHost = '82.29.161.52'        // Server IP address
_wsPort = 8084                   // WebSocket port (PHP Ratchet server)
_reconnectDelay = 3 seconds      // Wait time between reconnect attempts
_maxReconnectAttempts = 5         // Give up after 5 failed reconnects
_connectTimeout = 5 seconds      // Max wait for initial connection
```

**Why 5-second timeout?**  
When the phone is connected to the ESP32 valve hotspot (no internet), a WebSocket connection to the cloud server would hang forever. The 5-second timeout ensures the app doesn't freeze — it fails fast and continues in offline/direct mode.

---

## State Variables

### `_channel` (IOWebSocketChannel?, static)
The actual WebSocket connection object. `null` when not connected.

**Why IOWebSocketChannel and not WebSocketChannel?**  
Only `IOWebSocketChannel.connect()` supports custom headers. The server requires `Authorization: Bearer <token>` in the connection headers. `WebSocketChannel.connect()` does not support headers — using it causes immediate server rejection.

### `_isConnected` (bool, static)
`true` when the WebSocket is connected and ready to receive data.

### `_isConnecting` (bool, static)
`true` while a connection attempt is in progress. Prevents duplicate connection attempts — if `connect()` is called while already connecting, it returns immediately.

### `_reconnectAttempts` (int, static)
Counts how many reconnect attempts have been made. Resets to 0 on successful connect or when `resetReconnectAttempts()` is called.

### `_currentSubscription` / `_currentDeviceId` (String?, static)
Tracks what the app is currently subscribed to. Two possible values:
- `"device_list"` — HomeScreen wants the list of all devices
- `"device_detail"` + device ID — DeviceDetailScreen wants data for one specific valve

These are stored so that after a reconnect, the service can **automatically re-subscribe** to whatever the app was listening to before the disconnect.

### `_isRefreshing` (bool, static)
Prevents multiple simultaneous token refresh attempts. Without this guard:
```
Auth rejection → _handleAuthRejection() starts refreshing
Server sends another rejection → _handleAuthRejection() starts ANOTHER refresh
Both try to reconnect → chaos
```
With the guard, only the first rejection triggers a refresh. The second one sees `_isRefreshing = true` and skips.

### `lastServerTimestamp` (DateTime?, static)
Parsed from the `"timestamp"` field in every `devices_data` message from the server. Used by HomeScreen to determine if a valve is online or offline.

**Why not use the phone's clock?**  
The server runs in Sri Lanka time (UTC+5:30). The phone could be in any timezone. If we compared `vwv_last_seen` against the phone's clock, timezone mismatches would cause false offline readings. By using the server's own timestamp as the reference point, the comparison is always accurate.

---

## Stream Controllers

All streams are **broadcast** — multiple listeners can subscribe simultaneously. This is important because when IndexedStack keeps all tabs alive, multiple screens might be listening at the same time.

### `_connectionController` → Stream\<bool\>
Emits `true` when connected, `false` when disconnected.

**Who listens:** HomeScreen (shows green "Live updates" or "Offline" banner), DeviceDetailScreen (shows WiFi icon color).

### `_deviceListController` → Stream\<List\<dynamic\>\>
Emits the full device list every ~2 seconds (server push interval).

**Who listens:** HomeScreen — updates the device cards, saves to local cache.

**Example data received:**
```json
{
  "event": "devices_data",
  "timestamp": "2026-04-04T10:30:00+00:00",
  "device_list": [
    {
      "id": "VA202601001",
      "vwv_name": "MainValve01",
      "vwv_pos": "90",
      "vwv_is_open": 1,
      "vwv_last_seen": "2026-04-04T10:29:58+00:00"
    }
  ]
}
```

### `_deviceDetailController` → Stream\<Map\<String, dynamic\>\>
Emits single device data every ~2 seconds when subscribed to `device_detail`.

**Who listens:** DeviceDetailScreen — updates valve position, open/close state, checks confirmation target.

**Example data received:**
```json
{
  "event": "device_detail",
  "device_id": "VA202601001",
  "data": {
    "id": "VA202601001",
    "vwv_pos": "90",
    "vwv_is_open": 1,
    "vwv_is_close": 0,
    "vwv_last_seen": "2026-04-04T10:29:58+00:00",
    "user_schedule_ctrl": 0
  }
}
```

### `_scheduleController` → Stream\<Map\<String, dynamic\>\>
Emits schedule data when the server sends a `device_schedule` event.

**Who listens:** DeviceDetailScreen — populates the schedule table (only if user hasn't made local edits).

### `_rawMessageController` → Stream\<String\>
Emits every raw message as a string. Used by the debug terminal in HomeScreen for development.

---

## Functions

---

### `connect({skipExpiryCheck})` → Future\<bool\>

**What it does:**  
Opens a WebSocket connection to the server. This is the main entry point for establishing the connection.

**When it's called:**
- By `AuthService.checkLoginStatus()` at app startup (fire-and-forget)
- By `AuthService.login()` after successful login (awaited)
- By `_scheduleReconnect()` during auto-reconnect attempts
- By `AuthService.refreshTokenAndReconnect()` after getting a fresh token
- By `HomeScreen.didChangeAppLifecycleState()` when app resumes

**Parameters:**
- `skipExpiryCheck` (bool, default `false`) — Set to `true` when calling after a token refresh to prevent infinite loop

**How it works step by step:**

1. **Guard check:** If already connected or currently connecting → return immediately (prevents duplicate connections)
2. Set `_isConnecting = true`
3. Read `access_token` from SharedPreferences
4. If no token found → return `false`
5. **Token expiry check** (unless `skipExpiryCheck` is true):
   - Call `AuthService.isTokenExpired()`
   - If expired → set `_isConnecting = false`, call `AuthService.refreshTokenAndReconnect()`, return its result
   - This delegates the entire refresh-and-reconnect flow to AuthService
6. Call `_connectWithToken(token)` to do the actual connection
7. **Error handling:**
   - `TimeoutException` → Close channel, emit disconnected, do NOT auto-reconnect (user may be in AP mode)
   - Other errors → Emit disconnected, schedule auto-reconnect

**Why skipExpiryCheck exists:**
```
Without the flag, this infinite loop would happen:
connect() → isTokenExpired() = true → refreshTokenAndReconnect()
→ disconnect() + connect() → isTokenExpired() = true → refreshTokenAndReconnect()
→ ... forever

With the flag:
connect(skipExpiryCheck: true) → skips expiry check → uses the fresh token directly
```

---

### `_connectWithToken(token)` → Future\<bool\>

**What it does:**  
The internal method that performs the actual WebSocket connection using a specific token string. Separated from `connect()` so both fresh and refreshed tokens can use the same connection logic.

**How it works step by step:**

1. Create `IOWebSocketChannel.connect()` with:
   - URL: `ws://82.29.161.52:8084`
   - Header: `Authorization: Bearer <token>`
2. Await `_channel.ready` with 5-second timeout
   - If times out → throws `TimeoutException` (caught by `connect()`)
3. On successful connection:
   - Set `_isConnected = true`, `_isConnecting = false`
   - Reset `_reconnectAttempts = 0` and `_isRefreshing = false`
   - Emit `true` to `_connectionController`
4. Set up stream listener with three handlers:
   - `_handleMessage` — processes incoming data
   - `onError` — calls `_handleDisconnect()`
   - `onDone` — **checks close code for auth rejection** before calling `_handleDisconnect()`
5. If `_currentSubscription` is set (reconnect scenario) → re-subscribe automatically

**Auth rejection detection in onDone:**
```
When the server closes the connection because of an expired/invalid token,
it sends a close code and/or reason. The service checks for:

Close codes:
  4001 → Custom auth failure code
  4003 → Custom forbidden code
  1008 → Policy violation (standard WebSocket code)

Close reason text containing:
  "auth", "token", "expired", "unauthorized"

If any match → _handleAuthRejection() instead of normal _handleDisconnect()
```

---

### `subscribeTo(process, {deviceId})`

**What it does:**  
Tells the server what data to push. The server has two modes: push the full device list, or push detailed data for one specific device.

**When it's called:**
- By HomeScreen → `subscribeTo('device_list')` — wants list of all devices
- By DeviceDetailScreen → `subscribeTo('device_detail', deviceId: 'VA202601001')` — wants one device's data
- By `_connectWithToken()` after reconnect → re-subscribes to whatever was active before disconnect

**How it works step by step:**

1. Store `_currentSubscription` and `_currentDeviceId` (for reconnect recovery)
2. If not connected → print warning and return (the subscription will be sent when connection is established in `_connectWithToken`)
3. Send JSON message to server:

For device list:
```json
{"event": "subscribe", "process": "device_list"}
```

For device detail:
```json
{"event": "subscribe", "process": "device_detail", "device_id": "VA202601001"}
```

**Important behavior:**  
The server only pushes ONE type of data at a time. When DeviceDetailScreen subscribes to `device_detail`, HomeScreen stops receiving `devices_data`. When the user goes back to HomeScreen, `DeviceDetailScreen.dispose()` calls `subscribeTo('device_list')` to switch back.

---

### `_handleMessage(message)`

**What it does:**  
Routes every incoming WebSocket message to the correct stream controller based on the `"event"` field.

**When it's called:**  
Every time the server sends a message (approximately every 2 seconds).

**How it works step by step:**

1. Convert message to string, print it (debug), emit to `_rawMessageController`
2. Parse JSON
3. Read `event` field
4. Switch on event type:

| Event | Action |
|-------|--------|
| `devices_data` | Extract `device_list` array, parse server `timestamp` into `lastServerTimestamp`, emit list to `_deviceListController` |
| `device_detail` | Extract `data` map, emit to `_deviceDetailController` |
| `device_schedule` | Emit full message to `_scheduleController` |
| Default (unknown) | Check if message contains `"error"` key → if error text contains "token"/"auth"/"expired"/"unauthorized"/"jwt" → trigger `_handleAuthRejection()` |

**Auth error detection in messages:**  
Some servers send auth errors as regular messages instead of closing the connection. For example:
```json
{"error": "Token expired, please re-authenticate"}
```
The default case catches these and triggers the same token refresh flow as a connection close.

---

### `_handleAuthRejection()`

**What it does:**  
Automatically refreshes the JWT token and reconnects when the server rejects the connection due to authentication failure.

**When it's called:**
- By `_connectWithToken()` onDone handler when auth-related close code/reason is detected
- By `_handleMessage()` when an auth-related error message is received

**How it works step by step:**

1. **Guard check:** If `_isRefreshing` is already `true` → skip (prevents parallel refreshes)
2. Set `_isRefreshing = true`
3. Set `_isConnected = false`, `_isConnecting = false`, `_channel = null`
4. Emit `false` to `_connectionController` (UI shows disconnected)
5. Call `AuthService.refreshTokenAndReconnect()`:
   - This calls `_silentRefresh()` → POST to `login.php` with saved credentials → get fresh token
   - Then calls `disconnect()` + `connect(skipExpiryCheck: true)` → new connection with fresh token
6. If success:
   - Re-subscribe to `_currentSubscription` (so HomeScreen or DeviceDetailScreen continues receiving data)
7. If failure:
   - Set `_isRefreshing = false`
   - Do NOT schedule normal reconnect (would fail with same expired token)
   - User may need to log in manually

**Why not just schedule a normal reconnect?**  
Normal reconnect would read the same expired token from SharedPreferences and try to connect with it again — the server would reject it again — reconnect again — rejected again — until max attempts reached. Token refresh is the only solution.

---

### `disconnect()`

**What it does:**  
Full cleanup — closes the WebSocket connection, cancels timers, resets all state.

**When it's called:**
- By `AuthService.logout()` — user logs out
- By `AuthService.refreshTokenAndReconnect()` — before reconnecting with fresh token
- By `dispose()` — app fully closing

**How it works step by step:**

1. Cancel `_reconnectTimer` (stop any pending reconnect attempts)
2. Reset `_reconnectAttempts = 0`
3. Clear `_currentSubscription` and `_currentDeviceId`
4. Close the WebSocket channel with `goingAway` status code (tells the server it was an intentional close)
5. Set `_channel = null`, `_isConnected = false`, `_isConnecting = false`
6. Emit `false` to `_connectionController`

---

### `_handleDisconnect()`

**What it does:**  
Handles unexpected disconnection (server went down, network lost, etc). Unlike `disconnect()`, this triggers auto-reconnect.

**When it's called:**
- By the stream `onError` handler when a WebSocket error occurs
- By the stream `onDone` handler when the connection closes (and it's NOT an auth rejection)

**How it works:**

1. Set `_isConnected = false`, `_isConnecting = false`, `_channel = null`
2. Emit `false` to `_connectionController`
3. Call `_scheduleReconnect()`

---

### `_scheduleReconnect()`

**What it does:**  
Schedules an automatic reconnection attempt after a delay.

**When it's called:**
- By `_handleDisconnect()` after unexpected disconnection
- By `connect()` catch block on non-timeout errors

**How it works step by step:**

1. Check if `_reconnectAttempts >= 5` → if yes, give up and log "Max reconnect attempts reached"
2. Increment `_reconnectAttempts`
3. Cancel any existing reconnect timer
4. Start a new timer: after 3 seconds, call `connect()`

**Reconnect sequence example:**
```
Connection lost
  → Wait 3s → Attempt 1/5 → Failed
  → Wait 3s → Attempt 2/5 → Failed
  → Wait 3s → Attempt 3/5 → Success! (reset counter to 0)

Or:
  → Wait 3s → Attempt 1/5 → Failed
  → ... 
  → Wait 3s → Attempt 5/5 → Failed
  → "Max reconnect attempts reached" → Stop trying
```

**Why not reconnect on timeout?**  
When `connect()` times out, the phone is probably on the ESP32 hotspot (no internet). Auto-reconnecting would just timeout again and again. Better to stop and let the user switch WiFi. When they do, `didChangeAppLifecycleState` in HomeScreen will call `resetReconnectAttempts()` and try again.

---

### `resetReconnectAttempts()`

**What it does:**  
Resets the reconnect attempt counter to 0 and clears the `_isRefreshing` flag. Gives the service a fresh set of reconnect attempts.

**When it's called:**
- By `HomeScreen.didChangeAppLifecycleState()` when the app resumes from background — the user may have switched from ESP32 hotspot to home WiFi, so we should try connecting again

**How it works:**

1. Set `_reconnectAttempts = 0`
2. Set `_isRefreshing = false`

After this, the next call to `_scheduleReconnect()` or `connect()` will have a full 5 attempts available.

---

### `dispose()`

**What it does:**  
Permanently shuts down the service and closes all stream controllers. Only called when the app is fully closing.

**When it's called:**  
Typically never in practice (Flutter apps don't usually have a clean shutdown path), but available for completeness.

**How it works:**

1. Call `disconnect()` to close the WebSocket
2. Close all 5 stream controllers (connectionController, deviceListController, deviceDetailController, scheduleController, rawMessageController)

**Warning:** After `dispose()`, the stream controllers cannot be used again. This is a one-way operation.

---

## Data Flow Diagrams

### Normal Operation (HomeScreen)
```
Server pushes every 2 seconds:
  {"event":"devices_data","device_list":[...],"timestamp":"..."}
       │
       ▼
  _handleMessage()
       │
       ├── Parse device_list array
       ├── Save server timestamp to lastServerTimestamp
       └── Emit to _deviceListController
              │
              ▼
       HomeScreen._deviceListSub listener
              │
              ├── Update _devices list
              ├── Save to LocalStorageService cache
              └── setState() → UI rebuilds with new data
```

### Normal Operation (DeviceDetailScreen)
```
User taps device card in HomeScreen
       │
       ▼
DeviceDetailScreen opens → _setupWebSocket()
       │
       ▼
subscribeTo('device_detail', deviceId: 'VA202601001')
       │
       ▼
Server starts pushing every 2 seconds:
  {"event":"device_detail","device_id":"VA202601001","data":{...}}
       │
       ▼
  _handleMessage()
       │
       └── Emit to _deviceDetailController
              │
              ▼
       DeviceDetailScreen._detailSub listener
              │
              ├── Merge data into _device map
              ├── Check confirmation (vwv_pos == target?)
              ├── Update slider angle
              └── setState() → UI rebuilds
```

### Connection Lost → Auto-Reconnect
```
WiFi drops or server restarts
       │
       ▼
  onDone fires → _handleDisconnect()
       │
       ├── _isConnected = false
       ├── Emit false to connectionStream
       │         │
       │         ▼
       │    HomeScreen shows "Offline" banner
       │
       └── _scheduleReconnect()
              │
              ▼
         Wait 3 seconds → connect()
              │
              ├── Success → _connectWithToken() → re-subscribe → data flows again
              └── Failure → _scheduleReconnect() → try again (up to 5 times)
```

### Token Expired → Auto-Refresh
```
Server closes connection with code 4001 or reason "token expired"
       │
       ▼
  onDone fires → detects auth rejection → _handleAuthRejection()
       │
       ▼
  AuthService.refreshTokenAndReconnect()
       │
       ├── _silentRefresh() → POST login.php with saved credentials → fresh token
       │
       ▼
  disconnect() → connect(skipExpiryCheck: true) → _connectWithToken(freshToken)
       │
       ▼
  Connected! → re-subscribe to _currentSubscription → data flows again
  (User never noticed anything happened)
```

### App Resume After WiFi Switch
```
User was on ESP32 hotspot (no internet)
User switches to home WiFi
User opens the app
       │
       ▼
  didChangeAppLifecycleState(resumed) in HomeScreen
       │
       ▼
  resetReconnectAttempts() → counter = 0
       │
       ▼
  connect() → _connectWithToken() → subscribeTo('device_list')
       │
       ▼
  HomeScreen starts receiving live device data again
```

---

## Subscription Switching

The server only sends one type of data at a time. The app switches between them:

```
HomeScreen active:
  subscribeTo('device_list')
  → Server pushes devices_data every 2s
  → HomeScreen shows all device cards

User taps device card:
  DeviceDetailScreen opens
  subscribeTo('device_detail', deviceId: 'VA202601001')
  → Server stops pushing devices_data
  → Server starts pushing device_detail every 2s
  → DeviceDetailScreen shows valve controls

User presses back:
  DeviceDetailScreen.dispose()
  subscribeTo('device_list')   ← automatically called in dispose()
  → Server stops pushing device_detail
  → Server starts pushing devices_data again
  → HomeScreen resumes showing all device cards
```

---

## Who Calls What — Quick Reference

| Caller | Method | When |
|--------|--------|------|
| `AuthService.checkLoginStatus()` | `connect()` | App startup (fire-and-forget) |
| `AuthService.login()` | `connect()` | After successful login (awaited) |
| `AuthService.logout()` | `disconnect()` | User logs out |
| `AuthService.refreshTokenAndReconnect()` | `disconnect()` + `connect(skipExpiryCheck: true)` | After getting fresh token |
| `HomeScreen._setupWebSocket()` | `subscribeTo('device_list')` | HomeScreen initializes |
| `HomeScreen.didChangeAppLifecycleState()` | `resetReconnectAttempts()` + `connect()` | App resumes from background |
| `DeviceDetailScreen._setupWebSocket()` | `subscribeTo('device_detail', deviceId)` | DeviceDetailScreen opens |
| `DeviceDetailScreen.dispose()` | `subscribeTo('device_list')` | User navigates back |
| Internal `_scheduleReconnect()` | `connect()` | After 3-second delay, up to 5 times |
| Internal `_handleAuthRejection()` | `AuthService.refreshTokenAndReconnect()` | Server rejected expired token |

---

*Document Version: April 2026 — Vortex Labs Official*
