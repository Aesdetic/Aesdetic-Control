# WLED API Implementation Coverage Analysis

Last updated: 2026-06-04 (Asia/Hong_Kong)

## ✅ Implemented Core Functions

### State Management
- ✅ `getState()` - GET `/json` - Fetch device state and info
- ✅ `updateState()` - POST `/json` - Update device state
- ✅ `setPower()` - Power on/off control
- ✅ `setBrightness()` - Brightness control (0-255)
- ✅ `setColor()` - RGB/RGBW color control
- ✅ `setCCT()` - CCT control (0-255 and Kelvin)

### Segments
- ✅ `setSegmentPixels()` - Per-LED control with chunking
- ✅ Segment updates (fx, sx, ix, pal, cct, col, etc.)
- ✅ Multi-segment support

### Effects & Palettes
- ✅ `fetchEffectNames()` - GET `/json/effects` - Effects list
- ✅ `fetchFxData()` / effect metadata - GET `/json/fxdata` - Effect metadata
- ✅ `fetchPaletteNames()` - GET `/json/palettes` - Palettes list
- ✅ `fetchPalettePreviewPage()` - GET `/json/palx?page=...` - Palette preview pages
- ✅ `setEffect()` - Apply effect with speed/intensity/palette

### Presets
- ✅ `fetchPresets()` - GET `/json/presets` - List presets
- ✅ `savePreset()` - POST `/json/presets` - Save preset
- ✅ `applyPreset()` - Apply preset with transition
- ✅ Full `presets.json` rewrite create/delete helpers with preflight, local backup, upload, readback, and verification

### Playlists
- ✅ `fetchPlaylists()` / playlist parsing from WLED preset-store records
- ✅ `savePlaylist()` / playlist upsert through full `presets.json` rewrite
- ✅ `applyPlaylist()` / playlist start through WLED state playlist target
- ✅ Playlist delete through verified full `presets.json` rewrite

### Configuration
- ✅ `updateConfig()` - POST `/json/cfg` - Update device config (name)
- ✅ `getLEDConfiguration()` - GET `/json/cfg` - Get LED config
- ✅ `updateLEDConfiguration()` - POST `/json/cfg` - Update LED config
- ✅ `updateLEDSettings()` - Partial LED config update

### Advanced Features
- ✅ `configureNightLight()` - Night light configuration
- ✅ `setUDPSync()` - UDP sync control (send/recv/network)
- ✅ WebSocket integration (via WLEDWebSocketManager)
- ✅ Batch operations (`setBatchState`, `applyBatchPreset`)

### Real-time
- ✅ WebSocket state updates
- ✅ Connection management
- ✅ Priority-based connections

## ⚠️ Missing Standard WLED API Endpoints

### 1. Network Nodes
```swift
// MISSING: GET /json/nodes
func fetchNodes(for device: WLEDDevice) async throws -> [WLEDNode] {
    // Returns discovered WLED nodes on network
}
```

**Impact**: Low - Discovery service handles this differently.

### 2. Time Sync
```swift
// MISSING: POST /json/time
func syncTime(for device: WLEDDevice) async throws {
    // Sync device time with server
}
```

**Impact**: Low - Usually handled automatically.

### 3. WiFi Info (Partial)
```swift
// PARTIAL: GET /json/info (used in WiFiSetupView, not in WLEDAPIService)
// Should be centralized in WLEDAPIService
func getWiFiInfo(for device: WLEDDevice) async throws -> WiFiInfo {
    // Get WiFi connection info
}
```

**Impact**: Low - Exists but not centralized.

### 4. File System (Advanced)
```swift
// MISSING: GET /json/fs
func getFileSystem(for device: WLEDDevice) async throws -> FileSystemInfo {
    // Get file system info (for custom presets/effects)
}
```

**Impact**: Low - Advanced feature, rarely needed.

### 5. Peers Discovery
```swift
// MISSING: GET /json/peers
func fetchPeers(for device: WLEDDevice) async throws -> [WLEDPeer] {
    // Get discovered peer devices
}
```

**Impact**: Low - Discovery service handles this.

## 📊 Coverage Summary

### Core Control: ✅ 100%
- Power, brightness, color, CCT, effects, segments, presets
- All essential functions are implemented correctly

### Advanced Features: ✅ 95%
- Night light, UDP sync, batch operations, WebSocket
- Playlists are implemented through WLED preset-store records and state playlist apply.
- Remaining advanced gaps are mostly optional metadata/network/file-system endpoints.

### Metadata: ✅ 100% for current UI needs
- Effect names: ✅
- Effect metadata: ✅
- Palette names: ✅
- Palette preview pages: ✅

### Configuration: ✅ 100%
- Device config, LED config, WiFi (partial)

### Network Features: ⚠️ 70%
- Discovery: ✅ (via WLEDDiscoveryService)
- Nodes: ❌ (handled differently)
- Peers: ❌ (handled differently)

## 🎯 Recommendations

### Low Priority (optional)
1. Centralize WiFi info fetching in WLEDAPIService if more screens need the same payload.
2. Add explicit `/json/time` sync only if field devices need app-forced time correction.
3. Add `/json/fs` if custom preset/effect file management becomes a customer feature.
4. Add `/json/nodes` or `/json/peers` only if native WLED peer browsing becomes more useful than the existing discovery service.

## ✅ Conclusion

**The app implements the essential WLED functions needed for production control, saves, playlists, and on-device automation.**

The missing pieces are mostly:
- **Optional network/filesystem metadata endpoints** (`/json/nodes`, `/json/peers`, `/json/fs`)

Everything else in the core flow (power, brightness, color, CCT, effects, segments, presets, playlists, timer-backed automations, and verified preset-store rewrites) is implemented for the current app behavior.

The implementation follows WLED API specifications correctly and handles edge cases well (validation, error handling, caching, batch operations).
