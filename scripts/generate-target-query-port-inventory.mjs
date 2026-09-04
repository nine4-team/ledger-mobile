#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const CORE_RELATIVE = "LedgeriOS/LedgerTargetCore";
const MANIFEST_RELATIVE =
  "docs/plans/ledger-accounting-redesign/conversion/conversion-manifest.json";
const JSON_RELATIVE =
  "docs/plans/ledger-accounting-redesign/conversion/target-query-port-inventory.generated.json";
const MARKDOWN_RELATIVE =
  "docs/plans/ledger-accounting-redesign/conversion/target-query-port-inventory.generated.md";
const GENERATOR_RELATIVE = "scripts/generate-target-query-port-inventory.mjs";

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function fail(message) {
  throw new Error(`target-query-port-inventory: ${message}`);
}

function isIdentifierStart(character) {
  return /[A-Za-z_]/.test(character);
}

function isIdentifierContinuation(character) {
  return /[A-Za-z0-9_]/.test(character);
}

function blankRange(output, source, start, end) {
  for (let index = start; index < end; index += 1) {
    if (source[index] !== "\n") output[index] = " ";
  }
}

function isEscaped(source, quoteIndex) {
  let slashes = 0;
  for (let index = quoteIndex - 1; index >= 0 && source[index] === "\\"; index -= 1) {
    slashes += 1;
  }
  return slashes % 2 === 1;
}

function stringStartAt(source, index) {
  let hashCount = 0;
  while (source[index + hashCount] === "#") hashCount += 1;
  const quoteIndex = index + hashCount;
  if (source[quoteIndex] !== '"') return null;
  return { hashCount, quoteIndex };
}

function scanBlockComment(source, start) {
  let index = start + 2;
  let depth = 1;
  while (index < source.length && depth > 0) {
    if (source.startsWith("/*", index)) {
      depth += 1;
      index += 2;
    } else if (source.startsWith("*/", index)) {
      depth -= 1;
      index += 2;
    } else {
      index += 1;
    }
  }
  if (depth !== 0) fail("unterminated block comment");
  return index;
}

function scanLineComment(source, start) {
  let index = start + 2;
  while (index < source.length && source[index] !== "\n") index += 1;
  return index;
}

function previousCodeWord(source, index) {
  let cursor = index - 1;
  while (cursor >= 0 && /\s/.test(source[cursor])) cursor -= 1;
  const end = cursor + 1;
  while (cursor >= 0 && /[A-Za-z0-9_]/.test(source[cursor])) cursor -= 1;
  const word = source.slice(cursor + 1, end);
  return {
    character: source[end - 1] ?? "",
    word: Array.isArray(word) ? word.join("") : word,
  };
}

function regexStartAt(source, index, lexicalContext = source) {
  let hashCount = 0;
  while (source[index + hashCount] === "#") hashCount += 1;
  const slashIndex = index + hashCount;
  if (source[slashIndex] !== "/" || source.startsWith("//", slashIndex) || source.startsWith("/*", slashIndex)) {
    return null;
  }
  if (hashCount > 0) return { hashCount, slashIndex, multiline: true };
  const previous = previousCodeWord(lexicalContext, index);
  const expressionKeywords = new Set(["await", "case", "else", "in", "return", "throw", "try", "yield"]);
  const expressionPunctuation = new Set(["", "=", "(", "[", "{", ",", ":", ";", "!", "?", "&", "|"]);
  if (!expressionKeywords.has(previous.word) && !expressionPunctuation.has(previous.character)) return null;
  return { hashCount, slashIndex, multiline: false };
}

function scanInterpolation(source, start) {
  const lexicalContext = [...source];
  blankRange(lexicalContext, source, 0, start);
  let index = start;
  let depth = 1;
  while (index < source.length) {
    if (source.startsWith("//", index)) {
      const commentStart = index;
      index = scanLineComment(source, index);
      blankRange(lexicalContext, source, commentStart, index);
      continue;
    }
    if (source.startsWith("/*", index)) {
      const commentStart = index;
      index = scanBlockComment(source, index);
      blankRange(lexicalContext, source, commentStart, index);
      continue;
    }
    const nestedString = stringStartAt(source, index);
    if (nestedString) {
      const stringStart = index;
      index = scanString(source, nestedString);
      blankRange(lexicalContext, source, stringStart, index);
      continue;
    }
    const nestedRegex = regexStartAt(source, index, lexicalContext);
    if (nestedRegex) {
      const regexStart = index;
      index = scanRegex(source, nestedRegex);
      blankRange(lexicalContext, source, regexStart, index);
      continue;
    }
    if (source[index] === "(") depth += 1;
    else if (source[index] === ")") {
      depth -= 1;
      if (depth === 0) return index + 1;
    }
    index += 1;
  }
  fail("unterminated string interpolation");
}

function scanRegex(source, { hashCount, slashIndex, multiline }) {
  const closing = `/${"#".repeat(hashCount)}`;
  const interpolation = `\\${"#".repeat(hashCount)}(`;
  let index = slashIndex + 1;
  while (index < source.length) {
    if (
      source.startsWith(interpolation, index) &&
      (hashCount > 0 || !isEscaped(source, index))
    ) {
      index = scanInterpolation(source, index + interpolation.length);
      continue;
    }
    if (
      source.startsWith(closing, index) &&
      (hashCount > 0 || !isEscaped(source, index))
    ) {
      return index + closing.length;
    }
    if (!multiline && source[index] === "\n") fail("unterminated regex literal");
    index += 1;
  }
  fail("unterminated regex literal");
}

function scanString(source, { hashCount, quoteIndex }) {
  const multiline = source.startsWith('"""', quoteIndex);
  const quoteWidth = multiline ? 3 : 1;
  const closing = `${'"'.repeat(quoteWidth)}${"#".repeat(hashCount)}`;
  const interpolation = `\\${"#".repeat(hashCount)}(`;
  let index = quoteIndex + quoteWidth;
  while (index < source.length) {
    if (
      source.startsWith(interpolation, index) &&
      (hashCount > 0 || !isEscaped(source, index))
    ) {
      index = scanInterpolation(source, index + interpolation.length);
      continue;
    }
    if (
      source.startsWith(closing, index) &&
      (hashCount > 0 || !isEscaped(source, index))
    ) {
      return index + closing.length;
    }
    if (!multiline && source[index] === "\n") fail("unterminated string literal");
    index += 1;
  }
  fail("unterminated string literal");
}

export function maskSwiftSource(input) {
  const source = input.replaceAll("\r\n", "\n").replaceAll("\r", "\n");
  const output = [...source];
  let index = 0;

  while (index < source.length) {
    if (source.startsWith("//", index)) {
      const start = index;
      index = scanLineComment(source, index);
      blankRange(output, source, start, index);
      continue;
    }

    if (source.startsWith("/*", index)) {
      const start = index;
      index = scanBlockComment(source, index);
      blankRange(output, source, start, index);
      continue;
    }

    const stringDescriptor = stringStartAt(source, index);
    if (stringDescriptor) {
      const start = index;
      index = scanString(source, stringDescriptor);
      blankRange(output, source, start, index);
      continue;
    }

    const regexDescriptor = regexStartAt(source, index, output);
    if (regexDescriptor) {
      const start = index;
      index = scanRegex(source, regexDescriptor);
      blankRange(output, source, start, index);
      continue;
    }

    index += 1;
  }

  return output.join("");
}

export function tokenizeSwift(maskedSource) {
  if (/[^\x00-\x7F]/u.test(maskedSource)) {
    fail("unsupported non-ASCII code token");
  }
  const tokens = [];
  let index = 0;
  let line = 1;
  while (index < maskedSource.length) {
    const character = maskedSource[index];
    if (character === "\n") {
      line += 1;
      index += 1;
      continue;
    }
    if (/\s/.test(character)) {
      index += 1;
      continue;
    }
    if (isIdentifierStart(character)) {
      const start = index;
      index += 1;
      while (
        index < maskedSource.length &&
        isIdentifierContinuation(maskedSource[index])
      ) {
        index += 1;
      }
      tokens.push({ value: maskedSource.slice(start, index), start, end: index, line });
      continue;
    }
    if (/[0-9]/.test(character)) {
      const start = index;
      index += 1;
      while (index < maskedSource.length && /[A-Za-z0-9_.]/.test(maskedSource[index])) {
        index += 1;
      }
      tokens.push({ value: maskedSource.slice(start, index), start, end: index, line });
      continue;
    }
    if (maskedSource.startsWith("->", index)) {
      tokens.push({ value: "->", start: index, end: index + 2, line });
      index += 2;
      continue;
    }
    tokens.push({ value: character, start: index, end: index + 1, line });
    index += 1;
  }
  return tokens;
}

function matchingToken(tokens, openingIndex, opening, closing, upperBound = tokens.length) {
  if (tokens[openingIndex]?.value !== opening) return -1;
  let depth = 0;
  for (let index = openingIndex; index < upperBound; index += 1) {
    if (tokens[index].value === opening) depth += 1;
    if (tokens[index].value === closing) {
      depth -= 1;
      if (depth === 0) return index;
    }
  }
  return -1;
}

function topLevelTokenIndex(tokens, start, end, value) {
  const stack = [];
  const pairs = { "(": ")", "[": "]", "<": ">" };
  for (let index = start; index < end; index += 1) {
    const token = tokens[index].value;
    if (pairs[token]) stack.push(pairs[token]);
    else if (new Set(Object.values(pairs)).has(token)) {
      if (stack.pop() !== token) fail("malformed declaration delimiters");
    } else if (stack.length === 0 && token === value) {
      return index;
    }
  }
  if (stack.length) fail("malformed declaration delimiters");
  return -1;
}

function splitTopLevel(tokens, start, end, separator, label) {
  const ranges = [];
  let cursor = start;
  while (cursor <= end) {
    const boundary = topLevelTokenIndex(tokens, cursor, end, separator);
    const rangeEnd = boundary < 0 ? end : boundary;
    if (cursor === rangeEnd) fail(`empty component in ${label}`);
    ranges.push([cursor, rangeEnd]);
    if (boundary < 0) return ranges;
    cursor = boundary + 1;
  }
  fail(`malformed ${label}`);
}

function validateTypeComponentBounds(tokens, start, end, label) {
  if (start >= end) fail(`empty ${label}`);
  let cursor = start;
  while (tokens[cursor]?.value === "@") {
    cursor += 1;
    if (!isIdentifierStart(tokens[cursor]?.value?.[0] ?? "")) {
      fail(`malformed type attribute in ${label}`);
    }
    cursor += 1;
    while (tokens[cursor]?.value === ".") {
      cursor += 1;
      if (!isIdentifierStart(tokens[cursor]?.value?.[0] ?? "")) {
        fail(`malformed qualified type attribute in ${label}`);
      }
      cursor += 1;
    }
  }
  if (cursor >= end) fail(`type attribute has no type in ${label}`);
  const first = tokens[cursor].value;
  if (first === "~") {
    if (!isIdentifierStart(tokens[cursor + 1]?.value?.[0] ?? "")) {
      fail(`incomplete suppression type in ${label}`);
    }
  } else if (!isIdentifierStart(first?.[0] ?? "") && !new Set(["(", "["]).has(first)) {
    fail(`invalid starting token ${first} in ${label}`);
  }
  const last = tokens[end - 1].value;
  if (new Set([".", ",", ":", "&", "@", "->", "~", "(", "[", "<", "="]).has(last)) {
    fail(`invalid terminal token ${last} in ${label}`);
  }
}

function validateNestedTypeGroups(tokens, start, end, label) {
  validateTypeComponentBounds(tokens, start, end, label);
  for (let index = start; index < end; index += 1) {
    const opening = tokens[index].value;
    if (!new Set(["(", "[", "<"]).has(opening)) continue;
    const closing = { "(": ")", "[": "]", "<": ">" }[opening];
    const close = matchingToken(tokens, index, opening, closing, end);
    if (close < 0) fail(`malformed nested delimiters in ${label}`);
    const contentStart = index + 1;

    if (opening === "<") {
      for (const [componentStart, componentEnd] of splitTopLevel(
        tokens,
        contentStart,
        close,
        ",",
        `${label} generic arguments`,
      )) {
        if (
          topLevelTokenIndex(tokens, componentStart, componentEnd, ":") >= 0 ||
          topLevelTokenIndex(tokens, componentStart, componentEnd, "=") >= 0
        ) {
          fail(`unsupported relation in ${label} generic arguments`);
        }
        validateNestedTypeGroups(tokens, componentStart, componentEnd, label);
      }
    } else if (opening === "[") {
      if (contentStart === close) fail(`empty bracket type in ${label}`);
      const colon = topLevelTokenIndex(tokens, contentStart, close, ":");
      const comma = topLevelTokenIndex(tokens, contentStart, close, ",");
      if (comma >= 0) fail(`unsupported comma in bracket type in ${label}`);
      if (colon >= 0) {
        if (topLevelTokenIndex(tokens, colon + 1, close, ":") >= 0) {
          fail(`multiple separators in dictionary type in ${label}`);
        }
        if (contentStart === colon || colon + 1 === close) {
          fail(`empty dictionary component in ${label}`);
        }
        validateNestedTypeGroups(tokens, contentStart, colon, label);
        validateNestedTypeGroups(tokens, colon + 1, close, label);
      } else {
        validateNestedTypeGroups(tokens, contentStart, close, label);
      }
    } else if (contentStart !== close) {
      for (const [componentStart, componentEnd] of splitTopLevel(
        tokens,
        contentStart,
        close,
        ",",
        `${label} tuple components`,
      )) {
        const colon = topLevelTokenIndex(tokens, componentStart, componentEnd, ":");
        let typeStart = componentStart;
        if (colon >= 0) {
          if (topLevelTokenIndex(tokens, colon + 1, componentEnd, ":") >= 0) {
            fail(`multiple separators in tuple component in ${label}`);
          }
          const labels = tokens.slice(componentStart, colon);
          if (
            labels.length !== 1 ||
            !isIdentifierStart(labels[0]?.value?.[0] ?? "") ||
            colon + 1 === componentEnd
          ) {
            fail(`malformed tuple component in ${label}`);
          }
          typeStart = colon + 1;
        }
        validateNestedTypeGroups(tokens, typeStart, componentEnd, label);
      }
    }
    index = close;
  }
}

function validateTypeLike(tokens, start, end, label) {
  if (start >= end) fail(`empty ${label}`);
  const forbidden = new Set([
    "associatedtype", "class", "deinit", "extension", "func", "init", "let",
    "protocol", "static", "struct", "subscript", "typealias", "var", "{", "}", ";",
  ]);
  const identifierPrefixes = new Set([
    "any", "async", "borrowing", "consuming", "each", "inout", "isolated", "repeat",
    "sending", "some", "throws",
  ]);
  const punctuation = new Set([
    "@", ".", ",", ":", "&", "?", "!", "<", ">", "(", ")", "[", "]", "->", "~",
  ]);
  const stack = [];
  const pairs = { "(": ")", "[": "]", "<": ">" };
  let identifiers = 0;
  let previousToken = null;
  for (let index = start; index < end; index += 1) {
    const token = tokens[index].value;
    if (forbidden.has(token)) fail(`unsupported token ${token} in ${label}`);
    if (
      !isIdentifierStart(token[0] ?? "") &&
      !punctuation.has(token)
    ) {
      fail(`unsupported token ${token} in ${label}`);
    }
    const atTopLevel = stack.length === 0;
    if (atTopLevel && new Set([",", ":", "="]).has(token)) {
      fail(`unsupported top-level token ${token} in ${label}`);
    }
    if (isIdentifierStart(token[0] ?? "")) identifiers += 1;
    if (isIdentifierStart(token[0] ?? "")) {
      if (
        previousToken &&
        isIdentifierStart(previousToken[0] ?? "") &&
        !identifierPrefixes.has(previousToken)
      ) {
        fail(`ambiguous adjacent identifiers in ${label}`);
      }
    }
    if (pairs[token]) stack.push(pairs[token]);
    else if (new Set(Object.values(pairs)).has(token)) {
      if (stack.pop() !== token) fail(`malformed delimiters in ${label}`);
    }
    previousToken = token;
  }
  if (stack.length) fail(`malformed delimiters in ${label}`);
  validateNestedTypeGroups(tokens, start, end, label);
  if (identifiers === 0) fail(`missing type identifier in ${label}`);
  if (!isIdentifierStart(tokens[end - 1]?.value?.[0] ?? "") && !new Set([
    ")", "]", ">", "?", "!",
  ]).has(tokens[end - 1]?.value)) {
    fail(`incomplete ${label}`);
  }
}

function validateWhereClause(tokens, start, end, label) {
  for (const [constraintStart, constraintEnd] of splitTopLevel(tokens, start, end, ",", label)) {
    const colon = topLevelTokenIndex(tokens, constraintStart, constraintEnd, ":");
    const firstEquals = topLevelTokenIndex(tokens, constraintStart, constraintEnd, "=");
    let relationStart;
    let relationEnd;
    if (colon >= 0 && firstEquals >= 0) fail(`ambiguous relation in ${label}`);
    if (colon >= 0) {
      relationStart = colon;
      relationEnd = colon + 1;
    } else if (firstEquals >= 0) {
      if (tokens[firstEquals + 1]?.value !== "=") fail(`unsupported equality in ${label}`);
      if (topLevelTokenIndex(tokens, firstEquals + 2, constraintEnd, "=") >= 0) {
        fail(`ambiguous equality in ${label}`);
      }
      relationStart = firstEquals;
      relationEnd = firstEquals + 2;
    } else {
      fail(`missing relation in ${label}`);
    }
    validateTypeLike(tokens, constraintStart, relationStart, `${label} left side`);
    validateTypeLike(tokens, relationEnd, constraintEnd, `${label} right side`);
  }
}

function validateGenericParameterClause(tokens, start, end, selector) {
  const label = `${selector} generic parameter clause`;
  for (const [componentStart, componentEnd] of splitTopLevel(tokens, start, end, ",", label)) {
    const colon = topLevelTokenIndex(tokens, componentStart, componentEnd, ":");
    if (colon >= 0 && topLevelTokenIndex(tokens, colon + 1, componentEnd, ":") >= 0) {
      fail(`multiple constraints in ${label}`);
    }
    const nameEnd = colon < 0 ? componentEnd : colon;
    const nameTokens = tokens.slice(componentStart, nameEnd).map((token) => token.value);
    const validName =
      (nameTokens.length === 1 && nameTokens[0] !== "each" &&
        isIdentifierStart(nameTokens[0]?.[0] ?? "")) ||
      (nameTokens.length === 2 && nameTokens[0] === "each" &&
        isIdentifierStart(nameTokens[1]?.[0] ?? ""));
    if (!validName) fail(`unsupported component in ${label}`);
    if (colon >= 0) {
      validateTypeLike(tokens, colon + 1, componentEnd, `${selector} generic constraint`);
    }
  }
}

function validateParameterClause(tokens, start, end, selector) {
  if (start === end) return;
  const label = `${selector} parameter clause`;
  for (const [componentStart, componentEnd] of splitTopLevel(tokens, start, end, ",", label)) {
    const colon = topLevelTokenIndex(tokens, componentStart, componentEnd, ":");
    if (colon < 0) fail(`missing type separator in ${label}`);
    if (topLevelTokenIndex(tokens, colon + 1, componentEnd, ":") >= 0) {
      fail(`multiple type separators in ${label}`);
    }
    const labels = tokens.slice(componentStart, colon).map((token) => token.value);
    if (
      labels.length < 1 ||
      labels.length > 2 ||
      labels.some((value) => !isIdentifierStart(value?.[0] ?? ""))
    ) {
      fail(`unsupported labels in ${label}`);
    }
    validateTypeLike(tokens, colon + 1, componentEnd, `${selector} parameter type`);
  }
}

function validateProtocolHeader(tokens, start, end, name) {
  let cursor = start;
  if (tokens[cursor]?.value === "<") {
    const close = matchingToken(tokens, cursor, "<", ">", end);
    if (close < 0) fail(`malformed primary associated-type clause on ${name}`);
    for (const [componentStart, componentEnd] of splitTopLevel(
      tokens,
      cursor + 1,
      close,
      ",",
      `${name} primary associated-type clause`,
    )) {
      if (
        componentEnd - componentStart !== 1 ||
        !isIdentifierStart(tokens[componentStart]?.value?.[0] ?? "")
      ) {
        fail(`unsupported primary associated-type component on ${name}`);
      }
    }
    cursor = close + 1;
  }
  if (tokens[cursor]?.value === ":") {
    const whereIndex = topLevelTokenIndex(tokens, cursor + 1, end, "where");
    const inheritanceEnd = whereIndex < 0 ? end : whereIndex;
    for (const [componentStart, componentEnd] of splitTopLevel(
      tokens,
      cursor + 1,
      inheritanceEnd,
      ",",
      `${name} inheritance clause`,
    )) {
      validateTypeLike(tokens, componentStart, componentEnd, `${name} inherited type`);
    }
    cursor = inheritanceEnd;
  }
  if (tokens[cursor]?.value === "where") {
    validateWhereClause(tokens, cursor + 1, end, `${name} where clause`);
    cursor = end;
  }
  if (cursor !== end) fail(`unsupported protocol header for ${name}`);
}

function validateFunctionTail(tokens, start, end, selector) {
  let cursor = start;
  if (tokens[cursor]?.value === "async") cursor += 1;
  if (new Set(["throws", "rethrows"]).has(tokens[cursor]?.value)) {
    const effect = tokens[cursor].value;
    cursor += 1;
    if (tokens[cursor]?.value === "(") {
      if (effect !== "throws") fail(`typed rethrows is unsupported on ${selector}`);
      const close = matchingToken(tokens, cursor, "(", ")", end);
      if (close < 0) fail(`malformed typed throws clause on ${selector}`);
      validateTypeLike(tokens, cursor + 1, close, `${selector} thrown-error type`);
      cursor = close + 1;
    }
  }
  if (tokens[cursor]?.value === "->") {
    const whereIndex = topLevelTokenIndex(tokens, cursor + 1, end, "where");
    const returnEnd = whereIndex < 0 ? end : whereIndex;
    validateTypeLike(tokens, cursor + 1, returnEnd, `${selector} return type`);
    cursor = returnEnd;
  }
  if (tokens[cursor]?.value === "where") {
    validateWhereClause(tokens, cursor + 1, end, `${selector} where clause`);
    cursor = end;
  }
  if (cursor !== end) fail(`unsupported function tail on ${selector}`);
}

function parseAttributeSequence(tokens, start, end) {
  let index = start;
  while (index < end) {
    if (tokens[index]?.value !== "@" || !isIdentifierStart(tokens[index + 1]?.value?.[0] ?? "")) {
      return false;
    }
    index += 2;
    while (tokens[index]?.value === "." && index + 1 < end) index += 2;
    if (tokens[index]?.value === "(") {
      const close = matchingToken(tokens, index, "(", ")", end);
      if (close < 0) return false;
      index = close + 1;
    }
  }
  return index === end;
}

function attributeStart(tokens, funcIndex, lowerBound) {
  for (let index = lowerBound; index < funcIndex; index += 1) {
    if (tokens[index].value === "@" && parseAttributeSequence(tokens, index, funcIndex)) {
      return index;
    }
  }
  return funcIndex;
}

function signatureEnd(maskedSource, start, limit) {
  let parentheses = 0;
  let brackets = 0;
  let angles = 0;
  let sawParameters = false;
  let closedParameters = false;
  let index = start;

  for (; index < limit; index += 1) {
    const character = maskedSource[index];
    if (character === "(") {
      parentheses += 1;
      sawParameters = true;
    } else if (character === ")") {
      parentheses -= 1;
      if (parentheses < 0) fail("unbalanced function parentheses");
      if (sawParameters && parentheses === 0) closedParameters = true;
    } else if (character === "[") {
      brackets += 1;
    } else if (character === "]") {
      brackets -= 1;
      if (brackets < 0) fail("unbalanced function brackets");
    } else if (character === "<") {
      angles += 1;
    } else if (character === ">" && maskedSource[index - 1] !== "-") {
      angles -= 1;
      if (angles < 0) fail("unbalanced function generic delimiters");
    } else if (character === "{" && parentheses === 0 && brackets === 0 && angles === 0) {
      fail("direct Querying protocol function body is unsupported");
    } else if (character === ";" && parentheses === 0 && brackets === 0 && angles === 0) {
      return index;
    }
  }

  if (!sawParameters || !closedParameters || parentheses || brackets || angles) {
    fail("malformed or unterminated direct Querying function requirement");
  }
  return index;
}

function directMemberTokenIndexes(tokens, openIndex, closeIndex) {
  const indexes = [];
  const introducers = new Set([
    "associatedtype",
    "deinit",
    "func",
    "init",
    "let",
    "subscript",
    "typealias",
    "var",
  ]);
  let braces = 0;
  let parentheses = 0;
  let brackets = 0;
  for (let index = openIndex + 1; index < closeIndex; index += 1) {
    const value = tokens[index].value;
    if (value === "{") braces += 1;
    else if (value === "}") braces -= 1;
    else if (value === "(") parentheses += 1;
    else if (value === ")") parentheses -= 1;
    else if (value === "[") brackets += 1;
    else if (value === "]") brackets -= 1;
    else if (introducers.has(value) && braces === 0 && parentheses === 0 && brackets === 0) {
      indexes.push(index);
    }
    if (braces < 0 || parentheses < 0 || brackets < 0) {
      fail("malformed delimiters inside Querying protocol");
    }
  }
  if (braces || parentheses || brackets) fail("malformed delimiters inside Querying protocol");
  return indexes;
}

function boundaryAfterNonFunctionMember(tokens, memberIndex, nextFunctionIndex) {
  let parentheses = 0;
  let brackets = 0;
  for (let index = memberIndex + 1; index < nextFunctionIndex; index += 1) {
    const value = tokens[index].value;
    if (value === "(") parentheses += 1;
    else if (value === ")") parentheses -= 1;
    else if (value === "[") brackets += 1;
    else if (value === "]") brackets -= 1;
    else if (value === "{" && parentheses === 0 && brackets === 0) {
      const close = matchingToken(tokens, index, "{", "}", nextFunctionIndex);
      if (close < 0) fail("malformed non-function member before direct Querying function");
      return close + 1;
    } else if (value === ";" && parentheses === 0 && brackets === 0) {
      return index + 1;
    }
  }
  fail("unsupported non-function member before direct Querying function");
}

function canonicalSignature(
  maskedSource,
  tokens,
  funcIndex,
  lowerBound,
  protocolClose,
  nextMemberIndex,
) {
  while (tokens[lowerBound]?.value === ";") lowerBound += 1;
  const startIndex = attributeStart(tokens, funcIndex, lowerBound);
  if (startIndex > lowerBound) fail("unsupported tokens before direct Querying function");
  if (startIndex === funcIndex) {
    const lineStart = maskedSource.lastIndexOf("\n", tokens[funcIndex].start - 1) + 1;
    const declarationBoundary = Math.max(
      lineStart,
      maskedSource.lastIndexOf("{", tokens[funcIndex].start - 1) + 1,
      maskedSource.lastIndexOf("}", tokens[funcIndex].start - 1) + 1,
      maskedSource.lastIndexOf(";", tokens[funcIndex].start - 1) + 1,
    );
    if (maskedSource.slice(declarationBoundary, tokens[funcIndex].start).trim()) {
      fail("unsupported modifier or ambiguous tokens before direct Querying function");
    }
    const previous = tokens[funcIndex - 1]?.value;
    if (new Set([
      "borrowing", "class", "consuming", "distributed", "mutating", "nonisolated",
      "nonmutating", "optional", "static",
    ]).has(previous)) {
      fail(`unsupported ${previous} direct Querying function`);
    }
  }

  const selectorToken = tokens[funcIndex + 1];
  if (!selectorToken || !isIdentifierStart(selectorToken.value[0])) {
    fail("unsupported or missing direct Querying function selector");
  }
  let cursor = funcIndex + 2;
  if (tokens[cursor]?.value === "<") {
    const genericClose = matchingToken(tokens, cursor, "<", ">", protocolClose);
    if (genericClose < 0) fail(`malformed generic clause on ${selectorToken.value}`);
    validateGenericParameterClause(tokens, cursor + 1, genericClose, selectorToken.value);
    cursor = genericClose + 1;
  }
  if (tokens[cursor]?.value !== "(") fail(`missing parameter clause on ${selectorToken.value}`);
  const parameterClose = matchingToken(tokens, cursor, "(", ")", protocolClose);
  if (parameterClose < 0) fail(`malformed parameter clause on ${selectorToken.value}`);
  validateParameterClause(tokens, cursor + 1, parameterClose, selectorToken.value);

  const nextMemberStart = nextMemberIndex == null
    ? null
    : attributeStart(tokens, nextMemberIndex, funcIndex + 1);
  const limit = nextMemberStart == null
    ? tokens[protocolClose].start
    : tokens[nextMemberStart].start;
  const end = signatureEnd(maskedSource, tokens[funcIndex].start, limit);
  const signatureTokens = tokenizeSwift(maskedSource.slice(tokens[startIndex].start, end));
  if (signatureTokens.filter((token) => token.value === "func").length !== 1) {
    fail(`ambiguous function boundary for ${selectorToken.value}`);
  }
  if (nextMemberStart != null && end === limit) {
    const previousToken = tokens[nextMemberStart - 1];
    if (previousToken?.line === tokens[nextMemberStart].line) {
      fail(`ambiguous same-line member boundary after ${selectorToken.value}`);
    }
  }
  let tailEnd = parameterClose + 1;
  while (tailEnd < protocolClose && tokens[tailEnd].start < end) tailEnd += 1;
  validateFunctionTail(tokens, parameterClose + 1, tailEnd, selectorToken.value);
  return {
    selector: selectorToken.value,
    signature: signatureTokens.map((token) => token.value).join(" "),
    end,
  };
}

function resolveOwner(manifest, sourcePath) {
  const matches = (manifest.surfaces ?? []).filter(
    (surface) =>
      surface.discovery === "automatic" &&
      surface.kind?.startsWith("swift_") &&
      surface.name === sourcePath &&
      surface.sourcePresence === "present" &&
      (surface.sourceRefs ?? []).some((reference) => reference.path === sourcePath),
  );
  if (matches.length === 0) fail(`missing manifest owner for ${sourcePath}`);
  if (matches.length !== 1) fail(`ambiguous manifest owner for ${sourcePath}`);
  const owner = matches[0];
  if (owner.status !== "verified") {
    fail(`invalid manifest owner status for ${sourcePath}: ${owner.status}`);
  }
  return owner;
}

function parseProtocols(sourcePath, sourceText, manifest) {
  const masked = maskSwiftSource(sourceText);
  const tokens = tokenizeSwift(masked);
  const protocols = [];
  for (let index = 0; index < tokens.length; index += 1) {
    if (tokens[index].value !== "protocol") continue;
    const name = tokens[index + 1]?.value;
    if (tokens[index - 1]?.value === "public" && !isIdentifierStart(name?.[0] ?? "")) {
      fail("malformed public protocol name");
    }
    if (!name?.endsWith("Querying")) continue;
    if (tokens[index - 1]?.value !== "public") continue;

    let openIndex = index + 2;
    while (openIndex < tokens.length && tokens[openIndex].value !== "{") {
      if (tokens[openIndex].value === ";" || tokens[openIndex].value === "}") {
        fail(`malformed protocol declaration ${name}`);
      }
      openIndex += 1;
    }
    if (openIndex >= tokens.length) fail(`missing body for ${name}`);
    validateProtocolHeader(tokens, index + 2, openIndex, name);
    const closeIndex = matchingToken(tokens, openIndex, "{", "}");
    if (closeIndex < 0) fail(`unterminated body for ${name}`);

    const owner = resolveOwner(manifest, sourcePath);
    const memberIndexes = directMemberTokenIndexes(tokens, openIndex, closeIndex);
    const functionIndexes = memberIndexes.filter((memberIndex) => tokens[memberIndex].value === "func");
    if (functionIndexes.length === 0) fail(`empty Querying protocol ${name}`);
    const selectors = new Set();
    const methods = [];
    let lowerBound = openIndex + 1;
    for (const funcIndex of functionIndexes) {
      const memberPosition = memberIndexes.indexOf(funcIndex);
      const nextMemberIndex = memberIndexes[memberPosition + 1] ?? null;
      const previousMemberIndex = memberIndexes[memberPosition - 1] ?? null;
      const declarationLowerBound = previousMemberIndex == null
        ? openIndex + 1
        : tokens[previousMemberIndex].value === "func"
          ? lowerBound
          : boundaryAfterNonFunctionMember(tokens, previousMemberIndex, funcIndex);
      const parsed = canonicalSignature(
        masked,
        tokens,
        funcIndex,
        declarationLowerBound,
        closeIndex,
        nextMemberIndex,
      );
      if (selectors.has(parsed.selector)) {
        fail(`duplicate selector or overload ${name}.${parsed.selector}`);
      }
      selectors.add(parsed.selector);
      const identityInput = `${owner.id}\u0000${name}\u0000${parsed.selector}`;
      methods.push({
        id: `TQUERY-${sha256(identityInput).slice(0, 12).toUpperCase()}`,
        ownerSurfaceId: owner.id,
        ownerPath: sourcePath,
        ownerStatus: owner.status,
        protocol: name,
        selector: parsed.selector,
        category: parsed.selector.startsWith("watch")
          ? "observation"
          : "request_response",
        signature: parsed.signature,
        signatureHash: sha256(parsed.signature),
      });
      while (lowerBound < tokens.length && tokens[lowerBound].start < parsed.end) {
        lowerBound += 1;
      }
    }
    protocols.push({ name, ownerSurfaceId: owner.id, ownerPath: sourcePath, methods });
    index = closeIndex;
  }
  return protocols;
}

export function inventoryFromSources(sources, manifest) {
  const protocolNames = new Set();
  const methods = [];
  const protocolRows = [];
  for (const source of [...sources].sort((left, right) => left.path.localeCompare(right.path))) {
    for (const protocol of parseProtocols(source.path, source.text, manifest)) {
      if (protocolNames.has(protocol.name)) fail(`duplicate Querying protocol ${protocol.name}`);
      protocolNames.add(protocol.name);
      protocolRows.push({
        name: protocol.name,
        ownerSurfaceId: protocol.ownerSurfaceId,
        ownerPath: protocol.ownerPath,
        methodCount: protocol.methods.length,
      });
      methods.push(...protocol.methods);
    }
  }
  methods.sort((left, right) =>
    [left.ownerSurfaceId, left.protocol, left.selector].join("\u0000").localeCompare(
      [right.ownerSurfaceId, right.protocol, right.selector].join("\u0000"),
    ),
  );
  const identitiesById = new Map();
  for (const method of methods) {
    const identity = [method.ownerSurfaceId, method.protocol, method.selector].join("\u0000");
    const previous = identitiesById.get(method.id);
    if (previous && previous !== identity) fail(`TQUERY identity collision ${method.id}`);
    identitiesById.set(method.id, identity);
  }
  protocolRows.sort((left, right) =>
    [left.ownerSurfaceId, left.name].join("\u0000").localeCompare(
      [right.ownerSurfaceId, right.name].join("\u0000"),
    ),
  );
  const ownerCount = new Set(protocolRows.map((protocol) => protocol.ownerSurfaceId)).size;
  const inventoryDigest = sha256(
    methods
      .map((method) =>
        [method.id, method.ownerSurfaceId, method.protocol, method.selector, method.signatureHash].join(
          "\u0000",
        ),
      )
      .join("\n"),
  );
  return {
    schemaVersion: 1,
    generator: GENERATOR_RELATIVE,
    sourceRoot: CORE_RELATIVE,
    inventoryDigest,
    totals: {
      ownerSurfaces: ownerCount,
      protocols: protocolRows.length,
      methods: methods.length,
      observationMethods: methods.filter((method) => method.category === "observation").length,
      requestResponseMethods: methods.filter(
        (method) => method.category === "request_response",
      ).length,
    },
    protocols: protocolRows,
    methods,
  };
}

function walkSwift(directory) {
  const paths = [];
  const visit = (current) => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const absolute = path.join(current, entry.name);
      if (entry.isDirectory()) visit(absolute);
      else if (entry.isFile() && entry.name.endsWith(".swift")) paths.push(absolute);
    }
  };
  visit(directory);
  return paths.sort();
}

export function buildRepositoryInventory(root = ROOT) {
  const core = path.join(root, CORE_RELATIVE);
  const manifestPath = path.join(root, MANIFEST_RELATIVE);
  if (!fs.existsSync(core)) fail(`missing source root ${CORE_RELATIVE}`);
  if (!fs.existsSync(manifestPath)) fail(`missing manifest ${MANIFEST_RELATIVE}`);
  let manifest;
  try {
    manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  } catch (error) {
    fail(`invalid manifest JSON: ${error.message}`);
  }
  const sources = walkSwift(core).map((absolute) => ({
    path: path.relative(root, absolute).split(path.sep).join("/"),
    text: fs.readFileSync(absolute, "utf8"),
  }));
  return inventoryFromSources(sources, manifest);
}

function escapeMarkdown(value) {
  return String(value).replaceAll("|", "\\|").replaceAll("\n", " ");
}

export function renderArtifacts(inventory) {
  const json = `${JSON.stringify(inventory, null, 2)}\n`;
  const markdown = [
    "# Target Query-Port Inventory",
    "",
    "> Generated by `npm run target:query-ports:generate`.",
    "> Do not edit manually. CI checks byte-for-byte freshness; generated diffs still require human review.",
    "",
    "## Result",
    "",
    `- Inventory digest: \`${inventory.inventoryDigest}\``,
    `- Verified owner surfaces: ${inventory.totals.ownerSurfaces}`,
    `- Public exact-suffix \`Querying\` protocols: ${inventory.totals.protocols}`,
    `- Direct instance methods: ${inventory.totals.methods}`,
    `- Observation methods: ${inventory.totals.observationMethods}`,
    `- Request/response methods: ${inventory.totals.requestResponseMethods}`,
    "",
    "## Protocols",
    "",
    "| Owner surface | Protocol | Methods | Source |",
    "| --- | --- | ---: | --- |",
    ...inventory.protocols.map(
      (protocol) =>
        `| \`${protocol.ownerSurfaceId}\` | \`${protocol.name}\` | ${protocol.methodCount} | \`${escapeMarkdown(protocol.ownerPath)}\` |`,
    ),
    "",
    "## Methods",
    "",
    "| TQUERY | Owner | Protocol | Selector | Category | Signature hash | Canonical signature |",
    "| --- | --- | --- | --- | --- | --- | --- |",
    ...inventory.methods.map(
      (method) =>
        `| \`${method.id}\` | \`${method.ownerSurfaceId}\` | \`${method.protocol}\` | \`${method.selector}\` | ${method.category} | \`${method.signatureHash}\` | \`${escapeMarkdown(method.signature)}\` |`,
    ),
    "",
    "## Limits",
    "",
    "This inventory proves declaration coverage and freshness only. It does not define product semantics, predicates, ordering, pagination, readiness, results, source-query parity, logical or physical indexes, SQL, RLS, Sync Streams, provider behavior, migration, production, or cutover authority.",
    "",
  ].join("\n");
  return { json, markdown };
}

export function artifactPaths(root = ROOT) {
  return {
    json: path.join(root, JSON_RELATIVE),
    markdown: path.join(root, MARKDOWN_RELATIVE),
  };
}

export function writeArtifacts(artifacts, paths = artifactPaths()) {
  fs.writeFileSync(paths.json, artifacts.json);
  fs.writeFileSync(paths.markdown, artifacts.markdown);
}

export function checkArtifacts(artifacts, paths = artifactPaths()) {
  const errors = [];
  for (const [kind, filePath] of Object.entries(paths)) {
    if (!fs.existsSync(filePath)) {
      errors.push(`missing generated ${kind} artifact: ${filePath}`);
    } else if (fs.readFileSync(filePath, "utf8") !== artifacts[kind]) {
      errors.push(`stale generated ${kind} artifact: ${filePath}`);
    }
  }
  if (errors.length) fail(errors.join("\n"));
}

export function execute(mode, root = ROOT) {
  if (!new Set(["generate", "check"]).has(mode)) {
    fail("usage: node scripts/generate-target-query-port-inventory.mjs <generate|check>");
  }
  const inventory = buildRepositoryInventory(root);
  const artifacts = renderArtifacts(inventory);
  if (mode === "generate") writeArtifacts(artifacts, artifactPaths(root));
  else checkArtifacts(artifacts, artifactPaths(root));
  return inventory;
}

async function main() {
  const mode = process.argv[2];
  const inventory = execute(mode);
  process.stdout.write(
    `target-query-port-inventory: ${mode} passed for ${inventory.totals.ownerSurfaces} owners, ${inventory.totals.protocols} protocols, and ${inventory.totals.methods} methods (${inventory.inventoryDigest})\n`,
  );
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
