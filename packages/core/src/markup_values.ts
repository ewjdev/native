/** Runtime value, typed-message and binding programs (113). Native capabilities
 * expose reflected types and exact numeric/storage facts; no pointer or i64 is
 * transported through the numeric program fields. All names remain raw bytes.
 */
function nscmDot(path: Uint8Array): number {
  for (let i = 0; i < path.length; i++) if (path[i] === 46) return i;
  return -1;
}
function nscmValues(r: NscElementReader, out: number[], mode: number): void {
  if (mode === 0) {
    const channel = r.word(), name = r.blob(), binding = r.flag();
    if (channel > 2) throw new Error("invalid resource channel");
    const element = channel === 0 ? nsceOne(name, ["avatar", "image"]) : nsceNamed(name, channel === 1 ? "media-surface" : "terminal");
    if (!element) nsceFail(out, channel * 2 + 1);
    else if (!binding) nsceFail(out, channel * 2 + 2);
    else nsceEmit(out, 1);
  } else if (mode === 1) {
    const channel = r.word(), kind = r.word(), nonnegative = r.flag();
    if (channel > 2 || kind > 3) throw new Error("invalid resource value");
    if (kind === 0 && nonnegative) nsceEmit(out, 2);
    else if (channel === 2 && kind === 3) nsceEmit(out, 3);
    else nsceFail(out, channel * 2 + 2);
  } else if (mode === 2) {
    const family = r.word(), name = r.blob(), eligible = r.names();
    if (family > 2) throw new Error("invalid element family");
    if (nsceIn(name, eligible)) nsceEmit(out, 1);
    else nsceFail(out, family === 0 ? 7 : family === 1 ? 8 : 9);
  } else if (mode === 3) {
    const kind = r.word(), phase = r.word(), anchor = r.flag(), valid = r.flag();
    if (kind > 2 || phase > 1) throw new Error("invalid anchor phase");
    if (phase === 0 && kind !== 0 && !anchor) nsceFail(out, 10);
    else if (phase === 1 && !valid) nsceFail(out, 11 + kind);
    else nsceEmit(out, 1);
  } else if (mode === 4 || mode === 5) {
    const type = r.word(), kind = r.word(), withinRange = r.flag();
    if (type > 5 || kind > 3) throw new Error("invalid typed value fact");
    const admitted = type === 1 ? kind === 0 || kind === 1 : type === 2 ? true : type === 3 || type === 5 ? kind === 3 : type === 4 ? kind === 0 && withinRange : false;
    if (admitted) nsceEmit(out, type);
    else if (mode === 5) nsceFail(out, 27);
    else nsceFail(out, type === 1 ? 20 : type === 3 ? 21 : type === 4 ? kind === 0 ? 23 : 24 : type === 5 ? 26 : 25);
  } else if (mode === 6) {
    const drag = r.flag(), tag = r.blob(), payload = r.flag(), names = r.names(), classes: number[] = [];
    for (let i = 0; i < names.length; i++) { const kind = r.word(); if (kind > 2) throw new Error("invalid message type"); classes.push(kind); }
    if (drag && !payload) { nsceFail(out, 31); return; }
    for (let i = 0; i < names.length; i++) if (nsceEqual(tag, names[i]!)) {
      const kind = classes[i]!;
      if (drag) { if (kind !== 2) nsceFail(out, 31); else nsceEmit(out, 42, 0, i); }
      else if (kind === 0) { if (payload) nsceFail(out, 28); else nsceEmit(out, 40, 0, i); }
      else if (!payload) nsceFail(out, 29);
      else nsceEmit(out, 41, 0, i);
      return;
    }
    nsceFail(out, drag ? 31 : 30);
  } else if (mode === 7) {
    const tag = r.blob(), names = r.names(), classes: number[] = [];
    for (let i = 0; i < names.length; i++) { const kind = r.word(); if (kind > 2) throw new Error("invalid callback class"); classes.push(kind); }
    for (let i = 0; i < names.length; i++) if (classes[i] !== 0 && nsceEqual(tag, names[i]!)) { nsceEmit(out, 43, 0, i, classes[i]!); return; }
    nsceEmit(out, 0);
  } else if (mode === 8) {
    const kind = r.word(), aware = r.flag();
    if (kind > 5) throw new Error("invalid attribute kind");
    if (kind === 0) nsceEmit(out, aware ? 50 : 51);
    else if (kind === 1) nsceEmit(out, 52);
    else if (kind === 2) { nsceEmit(out, 53); nsceEmit(out, 54); nsceEmit(out, 55); }
    else if (kind === 3) nsceEmit(out, 56);
    else nsceFail(out, 32);
  } else if (mode === 9) {
    nsceEmit(out, r.flag() ? 57 : 58);
  } else if (mode === 10) {
    const count = r.word();
    for (let i = 0; i < count; i++) {
      const binding = r.flag(), comparison = r.flag();
      if (binding) nsceEmit(out, 59, 0, i, comparison ? 0 : 1);
    }
    nsceEmit(out, 60);
  } else if (mode === 11) {
    const path = r.blob(), floor = r.word(), names = r.names(), classes: number[] = [];
    if (floor > names.length) throw new Error("invalid binding floor");
    for (let i = 0; i < names.length; i++) { const kind = r.word(); if (kind > 4) throw new Error("invalid scope payload"); classes.push(kind); }
    const dot = nscmDot(path), head = path.subarray(0, dot < 0 ? path.length : dot), tail = dot + 1;
    for (let i = names.length - 1; i >= floor; i--) if (nsceEqual(head, names[i]!)) {
      const kind = classes[i]!;
      if (kind === 0) nsceEmit(out, dot < 0 ? 62 : 61, 0, i, tail);
      else if (kind === 1) nsceFail(out, 36);
      else if (kind === 2) { if (dot >= 0) nsceFail(out, 37); else nsceEmit(out, 63, 0, i); }
      else if (kind === 3) { if (dot < 0) nsceFail(out, 41); else nsceEmit(out, 64, 0, i, tail); }
      else throw new Error("named slot capture is unreachable");
      return;
    }
    nsceEmit(out, 65, 0, head.length);
  } else if (mode === 12) {
    const domain = r.word(), phase = r.word(), present = r.flag(), allowArena = r.flag();
    if (domain > 3 || phase > 2) throw new Error("invalid binding resolution phase");
    if (phase === 2) { nsceFail(out, present ? 38 : 39); return; }
    if (phase === 1 && present) { nsceFail(out, 33); return; }
    if (present) { nsceEmit(out, 66); return; }
    if (phase === 0 && domain < 2 && !allowArena) nsceEmit(out, 67);
    else if (domain === 1) nsceEmit(out, 75);
    else nsceFail(out, domain === 0 ? 34 : domain === 2 ? 40 : 35);
  } else if (mode === 13) {
    const type = r.word(), path = r.blob(), arena = r.flag(), fields = r.names(), declarations = r.names(), classes: number[] = [];
    if (type > 2) throw new Error("invalid reflected binding type");
    for (let i = 0; i < declarations.length; i++) { const kind = r.word(); if (kind > 2) throw new Error("invalid declaration class"); classes.push(kind); }
    if (type === 2) { nsceEmit(out, 70); return; }
    if (type === 0) { nsceEmit(out, 0); return; }
    const dot = nscmDot(path), head = path.subarray(0, dot < 0 ? path.length : dot);
    for (let i = 0; i < fields.length; i++) if (nsceEqual(head, fields[i]!)) { nsceEmit(out, 68, 0, i, dot + 1); return; }
    if (dot < 0) for (let i = 0; i < declarations.length; i++) if (classes[i] !== 0 && nsceEqual(head, declarations[i]!)) {
      if (classes[i] === 2 && !arena) nsceEmit(out, 0);
      else nsceEmit(out, 69, 0, i, classes[i]!);
      return;
    }
    nsceEmit(out, 0);
  } else if (mode === 14) {
    const kind = r.word();
    if (kind > 3) throw new Error("invalid icon classification");
    if (kind < 2) nsceEmit(out, 72);
    else if (kind === 2) nsceEmit(out, 73);
    else nsceFail(out, 42);
  } else if (mode === 15) {
    const text = r.blob(), names = r.names();
    for (let i = 0; i < names.length; i++) if (nsceEqual(text, names[i]!)) { nsceEmit(out, 74, 0, i); return; }
    nsceEmit(out, 0);
  } else throw new Error("invalid markup value mode");
}
function nscvMarkupValues(input: Uint8Array): Uint8Array {
  if (input.length < 4 || input[0] !== 113 || input[1] !== 1 || input[2]! > 15 || input[3]! > 1) throw new Error("invalid markup value header");
  const r = new NscElementReader(input), out: number[] = [];
  nscmValues(r, out, input[2]!);
  if (r.at !== input.length) throw new Error("trailing markup value facts");
  const count = out.length / 7, bytes = new Uint8Array(input[3] === 0 ? 16 : 16 + count * 48), wire = new DataView(bytes.buffer);
  bytes[0] = 113; bytes[1] = 1; bytes[2] = input[3]!; wire.setFloat64(8, count, true);
  if (input[3] === 1) for (let i = 0; i < count; i++) {
    const at = 16 + i * 48, from = i * 7; bytes[at] = out[from]!; bytes[at + 1] = out[from + 1]!;
    for (let j = 0; j < 5; j++) wire.setFloat64(at + 8 + j * 8, out[from + j + 2]!, true);
  }
  return bytes;
}
