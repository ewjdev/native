// Compiled-core fixture for markup reload: a small model whose view is
// replaced from markup edits while the app runs.
import { Cmd, asciiBytes } from "@native-sdk/core";
import type { TextInputEvent } from "@native-sdk/core/text";

export interface Model {
  readonly count: number;
  readonly title: Uint8Array;
}

export type Msg =
  | { readonly kind: "increment" }
  | { readonly kind: "rename"; readonly event: TextInputEvent };

export function initialModel(): [Model, Cmd<Msg>] {
  return [{ count: 0, title: asciiBytes("Draft") }, Cmd.none];
}

export function update(model: Model, msg: Msg): [Model, Cmd<Msg>] {
  switch (msg.kind) {
    case "increment": return [{ ...model, count: model.count < 9007199254740991 ? model.count + 1 : model.count }, Cmd.none];
    case "rename": return [msg.event.kind === "insert_text" ? { ...model, title: msg.event.text } : model, Cmd.none];
  }
}
