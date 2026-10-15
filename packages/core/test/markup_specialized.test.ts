import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";
const source = ["markup_elements", "markup_specialized"].map(name => readFileSync(new URL(`../src/${name}.ts`, import.meta.url), "utf8")).join("\n");
const { nscvMarkupSpecialized: run } = await import(`data:text/javascript;base64,${Buffer.from(stripTypeScriptTypes(source) + "\nexport { nscvMarkupSpecialized };").toString("base64")}`);
interface Attr { name: string; raw?: string; cached?: number }
interface Child { kind?: number; name?: string; text?: string }
class Packet {
  parts: Uint8Array[];
  constructor(mode: number) { this.parts = [Uint8Array.of(112, 1, mode, 1)]; }
  word(...values: number[]): this { for (const n of values) { const b = new Uint8Array(8); new DataView(b.buffer).setFloat64(0, n, true); this.parts.push(b); } return this; }
  blob(value: string | Uint8Array): this { const b = typeof value === "string" ? new TextEncoder().encode(value) : value; this.word(b.length); this.parts.push(b); return this; }
  names(values: string[]): this { this.word(values.length); for (const value of values) this.blob(value); return this; }
  node(name: string, attrs: Attr[] = [], children: Child[] = []): this {
    this.blob(name).word(attrs.length);
    for (const attr of attrs) this.blob(attr.name).blob(attr.raw ?? "").word(attr.cached ?? 0);
    this.word(children.length); for (const child of children) this.word(child.kind ?? 0).blob(child.name ?? "column").blob(child.text ?? ""); return this;
  }
  bytes(): Uint8Array { return Uint8Array.from(Buffer.concat(this.parts)); }
  actions() {
    const b: Uint8Array = run(this.bytes()), v = new DataView(b.buffer), count = v.getFloat64(8, true);
    assert.equal(b.length, 16 + count * 48);
    return Array.from({ length: count }, (_, i) => ({ action: b[16 + i * 48]!, code: b[17 + i * 48]!, fields: Array.from({ length: 5 }, (_, j) => v.getFloat64(24 + i * 48 + j * 8, true)) }));
  }
}
const attrs = (...names: string[]): Attr[] => names.map(name => ({ name }));
const actions = (packet: Packet) => packet.actions().map(step => step.action);
test("specialized policy preserves leaf admission before evaluation and missing fields after attributes", () => {
  for (const [mode, name, required] of [[2, "markdown", "source"], [3, "code", "source"], [8, "timeline-item", "title"]] as const) {
    assert.deepEqual(actions(new Packet(mode).node(name, attrs(required), [{ kind: 1, text: "bad" }])), [255]);
    assert.equal(new Packet(mode).node(name, attrs(required)).actions().at(-1)!.action, 200);
  }
  assert.deepEqual(actions(new Packet(3).node("code", attrs("width", "height"))), [9, 10, 255]);
  assert.deepEqual(actions(new Packet(3).node("code", attrs("source", "width", "width", "bad"))), [1, 9, 9, 255]);
  assert.deepEqual(actions(new Packet(4).node("stepper", attrs("label"))), [4, 255]);
});
test("specialized child plans retain partial input groups allocation before chart admission and span ordering", () => {
  const late = new Packet(5).node("input-group", [], [{ name: "textarea" }, { name: "column" }]).actions();
  assert.deepEqual(late.map(step => step.action), [100, 255]); assert.equal(late[1]!.fields[0], 2);
  assert.deepEqual(actions(new Packet(5).node("input-group", [], [{ name: "input-group-actions" }])), [255]);
  assert.deepEqual(actions(new Packet(9).node("chart", [], [{ name: "series" }, { name: "text" }])), [100, 101, 255]);
  assert.deepEqual(actions(new Packet(6).node("input-group-actions", [], [{ name: "button" }, { kind: 1 }])), [255]);
  assert.deepEqual(actions(new Packet(12).node("text", [], [{ kind: 1 }, { name: "span" }, { name: "button" }])), [100, 101, 102, 255]);
  assert.deepEqual(actions(new Packet(13).node("span", attrs("scale", "weight", "scale"))), [100, 2, 1, 2, 101, 200]);
  assert.deepEqual(actions(new Packet(14).node("step", attrs("bad")).word(0)), [255]);
});
test("virtual plans preserve consumed publication before shape checks query counts rows and proxy filtering", () => {
  assert.deepEqual(actions(new Packet(1).node("virtual-list", attrs("window")).word(0)), [100, 255]);
  assert.deepEqual(actions(new Packet(15).word(2, 2)), [1, 1, 100, 200]);
  assert.deepEqual(actions(new Packet(15).word(2, 3)), [255]);
  assert.deepEqual(actions(new Packet(16).node("virtual-list", attrs("window", "label", "each", "label", "as"))), [1, 1, 100, 200]);
  const window = () => new Packet(0).node("virtual-window", attrs("id", "as", "extent-estimate"), [{ name: "column" }]);
  assert.deepEqual(actions(window().word(0, 0, 0, 0)), [1, 2, 3, 4, 5, 6, 100, 7, 101, 102, 103, 200]);
  assert.deepEqual(actions(window().word(1, 0, 0, 0)), [255]);
  for (const mode of [17, 18, 19]) {
    const packet = new Packet(mode).word(...(mode === 19 ? [1] : mode === 18 ? [1, 0] : [0, 1]));
    assert.deepEqual(actions(packet), [0]);
  }
});
test("specialized transport validates truncation reserved modes numeric facts and sizing", () => {
  const packet = new Packet(0).node("virtual-window", attrs("id", "as"), [{ name: "column" }]).word(0, 0, 0, 0);
  const bytes = packet.bytes();
  for (let i = 0; i < bytes.length; i++) assert.throws(() => run(bytes.subarray(0, i)));
  for (const at of [0, 1, 2, 3]) { const bad = bytes.slice(); bad[at] = 255; assert.throws(() => run(bad)); }
  for (const value of [-1, .25, NaN, Infinity, 2 ** 53]) { const bad = bytes.slice(); new DataView(bad.buffer).setFloat64(4, value, true); assert.throws(() => run(bad)); }
  const sizing = bytes.slice(); sizing[3] = 0; assert.equal(new DataView(run(sizing).buffer).getFloat64(8, true), packet.actions().length);
  assert.throws(() => run(Uint8Array.of(...bytes, 0)));
});
