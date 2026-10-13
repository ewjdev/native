/** Byte grammar and admission for automation commands. Numeric conversion is
 * requested explicitly from the native parser; returned strings borrow the
 * original input. No token is decoded as Unicode or coerced through JS numbers.
 */
type NscAutomationSpan = { start: number; end: number };
type NscAutomationField = { start: number; end: number; kind: number; rule: number; initial: number };
class NscAutomationGrammar {
  bytes: Uint8Array;
  at: number = 0;
  fields: NscAutomationField[] = [];
  action: number = 0;
  modifiers: number = 0;
  valid: boolean = true;
  constructor(bytes: Uint8Array) { this.bytes = bytes; }
  whitespace(at: number): boolean {
    const byte = this.bytes[at]; return byte === 32 || byte === 9 || byte === 10 || byte === 13;
  }
  remaining(): NscAutomationSpan {
    while (this.at < this.bytes.length && this.whitespace(this.at)) this.at++;
    let end = this.bytes.length;
    while (end > this.at && this.whitespace(end - 1)) end--;
    return { start: this.at, end };
  }
  token(): NscAutomationSpan {
    const rest = this.remaining(); let end = rest.start;
    while (end < rest.end && !this.whitespace(end)) end++;
    this.at = end;
    return { start: rest.start, end };
  }
  required(): NscAutomationSpan {
    const span = this.token(); if (span.start === span.end) this.valid = false; return span;
  }
  finish(): void { const rest = this.remaining(); if (rest.start !== rest.end) this.valid = false; }
  field(span: NscAutomationSpan, kind: number, rule: number): void {
    this.fields.push({ start: span.start, end: span.end, kind, rule, initial: 0 });
  }
  string(span: NscAutomationSpan): void { this.field(span, 0, 0); }
  number(kind: number, rule: number): void { this.field(this.required(), kind, rule); }
  defaultNumber(value: number): void {
    this.fields.push({ start: 0, end: 0, kind: 6, rule: 0, initial: value });
  }
  defaultInteger(value: number): void {
    this.fields.push({ start: 0, end: 0, kind: 7, rule: 0, initial: value });
  }
  equals(span: NscAutomationSpan, text: string, insensitive: boolean): boolean {
    if (span.end - span.start !== text.length) return false;
    for (let i = 0; i < text.length; i++) {
      let byte = this.bytes[span.start + i]!;
      if (insensitive && byte >= 65 && byte <= 90) byte += 32;
      if (byte !== text.charCodeAt(i)) return false;
    }
    return true;
  }
  chord(span: NscAutomationSpan): void {
    let start = span.start; let modifiers = 0;
    while (start < span.end) {
      let end = start;
      while (end < span.end && this.bytes[end] !== 43) end++;
      if (end === span.end || end === start || end + 1 === span.end) break;
      const part = { start, end };
      if (this.equals(part, "cmd", true) || this.equals(part, "meta", true) || this.equals(part, "super", true)) modifiers |= 24;
      else if (this.equals(part, "ctrl", true) || this.equals(part, "control", true)) modifiers |= 2;
      else if (this.equals(part, "alt", true) || this.equals(part, "option", true)) modifiers |= 4;
      else if (this.equals(part, "shift", true)) modifiers |= 1;
      else { this.string(span); return; }
      start = end + 1;
    }
    this.modifiers = modifiers; this.string({ start, end: span.end });
  }
}
const NSC_AUTOMATION_ACTIONS: readonly string[] = ["focus", "press", "toggle", "increment", "decrement", "set_text", "set_selection", "set_composition", "commit_composition", "cancel_composition", "select", "drag", "drop_files", "dismiss"];
function nscAutomationAction(grammar: NscAutomationGrammar, span: NscAutomationSpan): number {
  for (let i = 0; i < NSC_AUTOMATION_ACTIONS.length; i++) {
    const name = NSC_AUTOMATION_ACTIONS[i]!;
    if (span.end - span.start !== name.length) continue;
    let match = true;
    for (let j = 0; j < name.length; j++) {
      let byte = grammar.bytes[span.start + j]!;
      if (byte >= 65 && byte <= 90) byte += 32;
      if (byte === 45) byte = 95;
      if (byte !== name.charCodeAt(j)) match = false;
    }
    if (match) return i;
  }
  return -1;
}
function nscAutomationGrammar(mode: number, bytes: Uint8Array, capacity: number): NscAutomationGrammar {
  const g = new NscAutomationGrammar(bytes);
  // Numeric kinds: parseInt u64/u32/usize, parseUnsigned u32, parseFloat f32.
  // Rules: any integer, nonzero integer, finite f32, positive finite f32.
  switch (mode) {
    case 0: g.string(g.required()); break;
    case 1: g.number(2, 1); g.finish(); break;
    case 2: {
      const first = g.required(); const second = g.token(); g.finish();
      if (second.start === second.end) { g.defaultInteger(1); g.field(first, 2, 1); }
      else { g.field(first, 4, 1); g.field(second, 4, 1); }
      break;
    }
    case 3: { const rest = g.remaining(); if (rest.start === rest.end) g.valid = false; g.string(rest); break; }
    case 4: g.string(g.required()); g.string(g.remaining()); break;
    case 5: {
      g.string(g.required()); g.number(1, 1); g.action = nscAutomationAction(g, g.required());
      const rest = g.remaining(); g.string(rest);
      if (g.action < 0 || ((g.action === 6 || g.action === 12) && rest.start === rest.end)) g.valid = false;
      if (g.action !== 5 && g.action !== 6 && g.action !== 7 && g.action !== 11 && g.action !== 12 && rest.start !== rest.end) g.valid = false;
      break;
    }
    case 6: g.string(g.required()); g.number(1, 1); g.finish(); break;
    case 7: {
      g.string(g.required()); const first = g.required();
      if (g.equals(first, "at", false)) { g.action = 1; g.number(5, 2); g.number(5, 2); }
      else g.field(first, 1, 1);
      g.finish(); break;
    }
    case 8: {
      g.string(g.required()); g.number(1, 1); g.number(5, 2);
      const optional = g.token(); if (optional.start === optional.end) g.defaultNumber(0); else g.field(optional, 5, 2);
      g.finish(); break;
    }
    case 9: g.string(g.required()); g.number(1, 1); g.number(3, 0); g.finish(); break;
    case 10: g.string(g.required()); g.chord(g.required()); g.string(g.remaining()); break;
    case 11: {
      g.string(g.required()); g.number(5, 3); const x = g.token();
      if (x.start !== x.end) { g.action = 1; g.field(x, 5, 2); g.number(5, 2); }
      g.finish(); break;
    }
    case 12: {
      g.string(g.required()); g.number(1, 1); g.number(5, 2); g.number(5, 2);
      const y = g.token();
      if (y.start === y.end) { g.defaultNumber(0.5); g.defaultNumber(0.5); }
      else { g.field(y, 5, 2); g.number(5, 2); }
      g.finish(); break;
    }
    case 13: {
      g.string(g.required()); const scale = g.token();
      if (scale.start !== scale.end) { g.action = 1; g.field(scale, 5, 3); }
      g.finish(); break;
    }
    case 14: {
      while (g.valid) {
        const path = g.token(); if (path.start === path.end) break;
        if (g.fields.length >= capacity) { g.valid = false; break; }
        g.string(path);
      }
      if (g.fields.length === 0) g.valid = false;
      break;
    }
    case 15: g.number(3, 0); g.number(3, 0); g.finish(); break;
    case 16: {
      const first = g.token();
      if (first.start === first.end) { g.defaultNumber(16); g.defaultNumber(0); }
      else { g.field(first, 5, 2); g.number(5, 2); g.finish(); }
      break;
    }
    case 17: {
      g.number(5, 3); g.number(5, 3); const scale = g.token();
      if (scale.start === scale.end) g.defaultNumber(1); else g.field(scale, 5, 3);
      g.finish(); break;
    }
    default: throw new Error("invalid automation mode");
  }
  return g;
}
export function nscvAutomationCommands(request: Uint8Array): Uint8Array {
  if (request.length < 16 || request[0] !== 90 || request[1] !== 1 || request[2]! > 17 || request[3]! > 1)
    throw new Error("invalid automation header");
  const data = new DataView(request.buffer, request.byteOffset, request.byteLength);
  if (data.getUint32(12, true) !== 0) throw new Error("invalid automation reserve");
  const length = data.getUint32(4, true); const capacity = data.getUint32(8, true);
  if (length > request.length - 16) throw new Error("invalid automation extent");
  const grammar = nscAutomationGrammar(request[2]!, request.subarray(16, 16 + length), capacity);
  const count = grammar.valid || request[2] === 14 ? grammar.fields.length : 0;
  const phase = request[3]!; const facts = 16 + length;
  if (request.length !== facts + (phase === 1 ? count * 12 : 0)) throw new Error("invalid automation facts");
  const out = new Uint8Array(24 + count * 24); const result = new DataView(out.buffer);
  result.setUint32(0, 1, true); result.setUint32(4, request[2]!, true);
  result.setUint32(8, grammar.valid ? (phase === 0 ? 1 : 2) : 0, true);
  result.setUint32(12, grammar.valid ? grammar.action : 0, true);
  result.setUint32(16, grammar.modifiers, true); result.setUint32(20, count, true);
  for (let i = 0; i < count; i++) {
    const field = grammar.fields[i]!; const at = 24 + i * 24;
    result.setUint32(at, field.kind, true); result.setUint32(at + 4, field.start, true);
    result.setUint32(at + 8, field.end - field.start, true); result.setUint32(at + 12, field.rule, true);
    if (field.kind === 6) result.setFloat32(at + 16, field.initial, true);
    if (field.kind === 7) result.setUint32(at + 16, field.initial, true);
    if (phase === 1 && field.kind > 0 && field.kind < 6) {
      const fact = facts + i * 12; const ok = data.getUint32(fact, true);
      if (ok > 1) throw new Error("invalid automation conversion flag");
      for (let j = 0; j < 8; j++) out[at + 16 + j] = request[fact + 4 + j]!;
      let admitted = ok === 1;
      if (field.rule === 1) admitted = admitted && (data.getUint32(fact + 4, true) !== 0 || data.getUint32(fact + 8, true) !== 0);
      if (field.rule >= 2) {
        const number = data.getFloat32(fact + 4, true);
        admitted = admitted && Number.isFinite(number) && (field.rule !== 3 || number > 0);
      }
      if (!admitted) result.setUint32(8, 0, true);
    }
  }
  return out;
}
