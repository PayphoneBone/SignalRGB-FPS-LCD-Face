// FPS Bridge Sensor - SignalRGB network plugin
// Receives game FPS from fps_bridge.ps1 over local UDP and publishes it
// as a SignalRGB sensor named "Game FPS" (reported via the temperature
// sensor API, so it may show a °C unit; the value is FPS).
// Install: Documents\WhirlwindFX\Plugins\FPS_Bridge_Sensor.js, restart SignalRGB.

import udp from "@SignalRGB/udp";

const SERVICE_ID = "fps-bridge-local";
const BRIDGE_IP = "127.0.0.1";
const DISCOVERY_PORT = 41730; // plugin -> bridge (not required)
const REPLY_PORT = 41731;     // bridge -> plugin discovery replies
const DATA_PORT = 41732;      // bridge -> plugin FPS values
const SENSOR = "Game FPS";

let sock = null;
let fps = 0;
let lastData = 0;
let lastDiscovery = 0;
let lastDecodeLog = 0;

export function Name() { return "FPS Bridge"; }
export function Version() { return "1.1.0"; }
export function Publisher() { return "Bone"; }
export function Type() { return "network"; }
export function Size() { return [1, 1]; }
export function DefaultPosition() { return [0, 0]; }
export function DefaultScale() { return 1.0; }
export function SubdeviceController() { return false; }
export function LedNames() { return []; }
export function LedPositions() { return []; }
export function DeviceMessage() {
    return ["FPS Bridge", "Run fps_bridge.ps1 to feed live game FPS into the 'Game FPS' sensor."];
}

function toText(data, depth = 0) {
    if (depth > 4 || data === null || data === undefined) return "";
    if (typeof data === "string") return data;
    if (typeof data !== "object") return "";
    for (const key of ["data", "message", "response", "payload", "buffer"]) {
        try {
            if (data[key] !== undefined && data[key] !== data) {
                const text = toText(data[key], depth + 1);
                if (text) return text;
            }
        } catch (e) {}
    }
    try {
        const bytes = Array.from(data);
        if (bytes.length && bytes.every(x => typeof x === "number")) {
            return bytes.map(x => String.fromCharCode(x & 255)).join("");
        }
    } catch (e) {}
    return "";
}

export function Initialize() {
    device.setName("FPS Bridge");
    try { device.createTemperatureSensor(SENSOR); }
    catch (e) { device.log("FPS Bridge: createTemperatureSensor failed: " + e); }

    sock = udp.createSocket();
    sock.on("message", data => {
        const text = toText(data).replace(/\0/g, "").trim();
        if (!/^\d+(?:\.\d+)?$/.test(text)) {
            let details = "";
            try { details = JSON.stringify(data); } catch (e) {}
            let keys = "";
            try { keys = Object.keys(data).join(","); } catch (e) {}
            if (Date.now() - lastDecodeLog > 30000) {
                lastDecodeLog = Date.now();
                device.log("FPS decode failed: keys=" + keys + " object=" + details);
            }
            return;
        }
        fps = Number(text);
        lastData = Date.now();
    });
    sock.on("error", err => device.log("FPS Bridge UDP error: " + err));
    sock.bind(DATA_PORT);
    device.log("FPS Bridge: listening on UDP " + DATA_PORT);
}

export function Render() {
    const v = (Date.now() - lastData > 3000) ? 0 : fps;
    try { device.SetTemperature(SENSOR, v); } catch (e) { device.log("FPS sensor update error: " + e); }
}

export function Shutdown() {
    try { device.removeTemperatureSensor(SENSOR); } catch (e) { }
    if (sock) { try { sock.close(); } catch (e) { } }
    sock = null;
}

// ---- Discovery: the bridge announces itself on REPLY_PORT every few seconds ----
export function DiscoveryService() {
    this.IconUrl = "";
    this.UdpBroadcastPort = DISCOVERY_PORT;
    this.UdpListenPort = REPLY_PORT;
    this.UdpBroadcastAddress = BRIDGE_IP;

    this.Initialize = function () {
        service.log("FPS Bridge: waiting for fps_bridge.ps1");
    };

    this.Update = function () {
        const now = Date.now();
        if (now - lastDiscovery < 5000) return;
        lastDiscovery = now;
        service.broadcast(JSON.stringify({ service: SERVICE_ID, command: "discover" }));
    };

    this.Discovered = function (value) {
        let msg;
        try { msg = JSON.parse(value.response); } catch (e) { return; }
        if (!msg || msg.service !== SERVICE_ID || msg.command !== "device") return;

        let c = service.getController(SERVICE_ID);
        if (!c) {
            c = new FpsBridgeController();
            service.addController(c);
        }
        c.update();
    };

    this.remove = function (c) {
        if (c) service.removeController(c);
    };
}

class FpsBridgeController {
    constructor() {
        this.id = SERVICE_ID;
        this.name = "FPS Bridge";
        this.ip = BRIDGE_IP;
        this.port = DATA_PORT;
        this.initialized = false;
    }
    update() {
        if (this.initialized) return;
        this.initialized = true;
        service.updateController(this);
        service.announceController(this);
    }
}
