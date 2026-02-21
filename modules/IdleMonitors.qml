pragma ComponentBehavior: Bound

import "lock"
import qs.config
import qs.services
import Caelestia.Internal
import Quickshell
import Quickshell.Wayland

Scope {
    id: root

    required property Lock lock
    readonly property bool enabled: !Config.general.idle.inhibitWhenAudio || !Players.list.some(p => p.isPlaying)

    // Allowlist of Hyprland dispatcher prefixes safe for idle actions.
    readonly property list<string> allowedHyprDispatchers: ["dpms ", "screencast"]

    // Allowlist of safe system command arrays for idle actions.
    // First element (the executable) must be one of these.
    readonly property list<string> allowedIdleCommands: [
        "systemctl", "loginctl", "hyprlock", "swaylock", "brightnessctl"
    ]

    function handleIdleAction(action: var): void {
        if (!action)
            return;

        if (action === "lock") {
            lock.lock.locked = true;
        } else if (action === "unlock") {
            lock.lock.locked = false;
        } else if (typeof action === "string") {
            // Only allow known-safe Hyprland dispatcher prefixes
            const allowed = allowedHyprDispatchers.some(prefix => action.startsWith(prefix));
            if (!allowed) {
                console.warn("IdleMonitors: rejected disallowed Hyprland dispatch:", action);
                return;
            }
            Hypr.dispatch(action);
        } else if (Array.isArray(action) && action.length > 0) {
            // Only allow known-safe executables as the first element
            const exe = action[0];
            if (!allowedIdleCommands.includes(exe)) {
                console.warn("IdleMonitors: rejected disallowed idle command:", exe);
                return;
            }
            Quickshell.execDetached(action);
        } else {
            console.warn("IdleMonitors: rejected unrecognised idle action type");
        }
    }

    LogindManager {
        onAboutToSleep: {
            if (Config.general.idle.lockBeforeSleep)
                root.lock.lock.locked = true;
        }
        onLockRequested: root.lock.lock.locked = true
        onUnlockRequested: root.lock.lock.unlock()
    }

    Variants {
        model: Config.general.idle.timeouts

        IdleMonitor {
            required property var modelData

            enabled: root.enabled && (modelData.enabled ?? true)
            timeout: modelData.timeout
            respectInhibitors: modelData.respectInhibitors ?? true
            onIsIdleChanged: root.handleIdleAction(isIdle ? modelData.idleAction : modelData.returnAction)
        }
    }
}
