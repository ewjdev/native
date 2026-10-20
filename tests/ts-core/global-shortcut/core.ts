import { asciiBytes, Sub } from "@native-sdk/core";
import type { GlobalShortcutState } from "@native-sdk/core/events";

export interface Model { readonly alternate: boolean; readonly last: GlobalShortcutState }
export type Msg = { readonly kind: "rebind" } | { readonly kind: "talk"; readonly id: Uint8Array; readonly state: GlobalShortcutState };
export function initialModel(): Model { return { alternate: false, last: "released" }; }
export function update(model: Model, msg: Msg): Model {
  return msg.kind === "rebind" ? { ...model, alternate: !model.alternate } : { ...model, last: msg.state };
}
export function subscriptions(model: Model): Sub<Msg> {
  return Sub.globalShortcut("talk", model.alternate ? { key: asciiBytes("f6") } : { key: asciiBytes("space"), option: true }, "talk");
}
