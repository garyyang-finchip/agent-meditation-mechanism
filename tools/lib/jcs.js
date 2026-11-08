"use strict";

/**
 * JSON Canonicalization Scheme (RFC 8785) serializer.
 *
 * ECMAScript's JSON.stringify already produces the number and string serialization that
 * RFC 8785 requires; what remains is recursive sorting of object keys by UTF-16 code units
 * and the rejection of values that have no canonical form.
 */
function canonicalize(value) {
  return serialize(value);
}

function serialize(value) {
  if (value === null) return "null";
  const t = typeof value;
  if (t === "boolean") return value ? "true" : "false";
  if (t === "number") {
    if (!Number.isFinite(value)) throw new TypeError("non-finite numbers have no canonical form");
    return JSON.stringify(value);
  }
  if (t === "string") return JSON.stringify(value);
  if (t === "bigint") throw new TypeError("bigint values must be encoded as strings before canonicalization");
  if (t === "undefined" || t === "function" || t === "symbol") {
    throw new TypeError("undefined, functions and symbols have no canonical form");
  }
  if (Array.isArray(value)) {
    return "[" + value.map((v) => serialize(v === undefined ? null : v)).join(",") + "]";
  }
  if (typeof value.toJSON === "function") return serialize(value.toJSON());
  const keys = Object.keys(value).sort(compareUtf16);
  const parts = [];
  for (const k of keys) {
    const v = value[k];
    if (v === undefined) continue; // JSON.stringify drops undefined members; mirror that
    parts.push(JSON.stringify(k) + ":" + serialize(v));
  }
  return "{" + parts.join(",") + "}";
}

function compareUtf16(a, b) {
  // String comparison in ECMAScript compares UTF-16 code units, as RFC 8785 requires.
  if (a < b) return -1;
  if (a > b) return 1;
  return 0;
}

module.exports = {canonicalize};
