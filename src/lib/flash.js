// Camera flash helpers.
// In the browser the back-camera torch works through the camera track (on
// phones that allow it). Inside the iPhone / iPad app, WebKit doesn't expose
// the torch, so the native Torch plugin switches it on; for the front camera
// the screen turns white and goes to full brightness.
import { Capacitor } from "@capacitor/core";

const native = () => Capacitor.isNativePlatform();

export async function nativeTorchAvailable() {
  if (!native()) return false;
  try {
    const { Torch } = await import("@capawesome/capacitor-torch");
    return !!(await Torch.isAvailable()).available;
  } catch { return false; }
}

export async function setNativeTorch(on) {
  if (!native()) return false;
  try {
    const { Torch } = await import("@capawesome/capacitor-torch");
    if (on) await Torch.enable(); else await Torch.disable();
    return true;
  } catch { return false; }
}

// Full screen brightness while the screen is the flash; restored after.
let saved = null;
export async function screenFlashBrightness(on) {
  if (!native()) return;
  try {
    const { ScreenBrightness } = await import("@capacitor-community/screen-brightness");
    if (on) {
      if (saved === null) saved = (await ScreenBrightness.getBrightness()).brightness;
      await ScreenBrightness.setBrightness({ brightness: 1 });
    } else if (saved !== null) {
      await ScreenBrightness.setBrightness({ brightness: saved });
      saved = null;
    }
  } catch { /* not available */ }
}
