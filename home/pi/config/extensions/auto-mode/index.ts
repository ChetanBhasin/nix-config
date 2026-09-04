import { registerAutoMode, type ExtensionApi } from "./auto-mode-controller.js";

export default function autoModeExtension(pi: ExtensionApi): void {
  registerAutoMode(pi);
}
