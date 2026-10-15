import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";
const source = ["markup_elements", "markup_values"].map(name => readFileSync(new URL(`../src/${name}.ts`, import.meta.url), "utf8")).join("\n");
const { nscvMarkupValues: run } = await import(`data:text/javascript;base64,${Buffer.from(stripTypeScriptTypes(source) + "\nexport { nscvMarkupValues };").toString("base64")}`);
interface Attr { name: string; raw?: string; cached?: number }
interface Child { kind?: number; name?: string; text?: string }
class Packet {
  parts: Uint8Array[];
  constructor(mode: number) { this.parts = [Uint8Array.of(113, 1, mode, 1)]; }
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
test("value programs retain resource and dependent anchor failure order", () => {
  assert.equal(new Packet(0).word(0).blob("image").word(0).actions()[0]!.code, 2);
  assert.equal(new Packet(0).word(1).blob("image").word(0).actions()[0]!.code, 3);
  assert.deepEqual(actions(new Packet(1).word(2, 3, 0)), [3]);
  assert.equal(new Packet(1).word(0, 0, 0).actions()[0]!.code, 2);
  assert.equal(new Packet(3).word(2, 0, 0, 0).actions()[0]!.code, 10);
  assert.equal(new Packet(3).word(2, 1, 1, 0).actions()[0]!.code, 13);
  assert.deepEqual(actions(new Packet(2).word(1).blob("tooltip").names(["tooltip"])), [1]);
  for (let type = 0; type <= 5; type++) for (let kind = 0; kind < 4; kind++) for (const within of [0, 1]) {
    const allowed = type === 1 ? kind < 2 : type === 2 ? true : type === 3 || type === 5 ? kind === 3 : type === 4 ? kind === 0 && within === 1 : false;
    assert.equal(new Packet(4).word(type, kind, within).actions()[0]!.action !== 255, allowed);
    assert.equal(new Packet(5).word(type, kind, within).actions()[0]!.action !== 255, allowed);
  }
});
test("message and callback selection keep tag payload and native class distinctions", () => {
  const message = (drag: number, tag: string, payload: number) => new Packet(6).word(drag).blob(tag).word(payload).names(["tick", "number", "drag"]).word(0, 1, 2).actions()[0]!;
  assert.equal(message(0, "missing", 0).code, 30);
  assert.equal(message(0, "tick", 1).code, 28);
  assert.equal(message(0, "number", 0).code, 29);
  assert.equal(message(1, "missing", 0).code, 31);
  assert.equal(message(1, "number", 1).code, 31);
  assert.equal(message(1, "drag", 1).action, 42);
  assert.equal(message(0, "number", 1).action, 41);
  assert.equal(new Packet(7).blob("wide").names(["integer", "wide"]).word(0, 2).actions()[0]!.fields[1], 2);
  assert.deepEqual(actions(new Packet(7).blob("integer").names(["integer", "wide"]).word(0, 2)), [0]);
});
test("binding programs preserve raw byte paths lexical floors and retry effects", () => {
  const scope = (path: Uint8Array | string, floor: number, names: string[], classes: number[]) => new Packet(11).blob(path).word(floor).names(names).word(...classes).actions()[0]!;
  assert.equal(scope("a", 0, ["a", "a"], [2, 0]).action, 62);
  assert.equal(scope("a.b", 1, ["a"], [2]).action, 65);
  assert.equal(scope("a.b", 0, ["a"], [2]).code, 37);
  assert.equal(scope("a", 0, ["a"], [1]).code, 36);
  assert.equal(scope("a", 0, ["a"], [3]).code, 41);
  assert.equal(scope(Uint8Array.of(255, 46, 0), 0, [], []).fields[0], 1);
  assert.deepEqual(actions(new Packet(12).word(0, 0, 0, 0)), [67]);
  assert.equal(new Packet(12).word(0, 1, 1, 0).actions()[0]!.code, 33);
  assert.deepEqual(actions(new Packet(12).word(1, 1, 0, 0)), [75]);
  assert.equal(new Packet(12).word(1, 2, 1, 0).actions()[0]!.code, 38);
  const resolve = (path: string, arena: number, fields: string[], decls: string[], classes: number[]) => new Packet(13).word(1).blob(path).word(arena).names(fields).names(decls).word(...classes).actions()[0]!;
  assert.equal(resolve("same", 1, ["same"], ["same"], [1]).action, 68);
  assert.equal(resolve("same.", 1, ["same"], ["same"], [1]).fields[1], 5);
  assert.equal(resolve("derived", 0, [], ["derived"], [2]).action, 0);
  assert.equal(resolve("derived", 1, [], ["derived"], [2]).action, 69);
  assert.equal(resolve("derived.x", 1, [], ["derived"], [1]).action, 0);
});
test("expression programs keep eager binding order typed literals cached trees and exact enum bytes", () => {
  assert.deepEqual(actions(new Packet(8).word(2, 1)), [53, 54, 55]);
  assert.deepEqual(actions(new Packet(8).word(0, 1)), [50]);
  assert.deepEqual(actions(new Packet(8).word(0, 0)), [51]);
  for (const cached of [0, 1]) assert.deepEqual(actions(new Packet(9).word(cached)), [cached ? 57 : 58]);
  const tree = new Packet(10).word(4, 1, 0, 0, 0, 1, 1, 1, 0).actions();
  assert.deepEqual(tree.map(x => x.action), [59, 59, 59, 60]);
  assert.deepEqual(tree.slice(0, 3).map(x => x.fields.slice(0, 2)), [[0, 1], [2, 0], [3, 1]]);
  for (let kind = 0; kind < 4; kind++) assert.equal(new Packet(14).word(kind).actions()[0]!.action, kind < 2 ? 72 : kind === 2 ? 73 : 255);
  assert.equal(new Packet(15).blob("end").names(["start", "end"]).actions()[0]!.fields[0], 1);
  assert.deepEqual(actions(new Packet(15).blob(Uint8Array.of(255)).names(["�"])), [0]);
});
test("value transport rejects every truncation invalid flag range and trailing bytes", () => {
  const bytes = new Packet(13).word(1).blob("a.b").word(1).names(["a"]).names(["x"]).word(2).bytes();
  for (let i = 0; i < bytes.length; i++) assert.throws(() => run(bytes.subarray(0, i)));
  for (const at of [0, 1, 2, 3]) { const bad = bytes.slice(); bad[at] = 255; assert.throws(() => run(bad)); }
  for (const value of [-1, .25, NaN, Infinity, 2 ** 53]) { const bad = bytes.slice(); new DataView(bad.buffer).setFloat64(4, value, true); assert.throws(() => run(bad)); }
  const sizing = bytes.slice(); sizing[3] = 0; assert.equal(new DataView(run(sizing).buffer).getFloat64(8, true), 1);
  assert.throws(() => run(Uint8Array.of(...bytes, 0)));
  assert.throws(() => new Packet(0).word(0).blob("image").word(2).actions());
  assert.throws(() => new Packet(11).blob("a").word(1).names([]).actions());
});
