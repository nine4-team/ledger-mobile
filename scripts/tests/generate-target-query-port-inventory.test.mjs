import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  artifactPaths,
  buildRepositoryInventory,
  checkArtifacts,
  execute,
  inventoryFromSources,
  maskSwiftSource,
  renderArtifacts,
  writeArtifacts,
} from "../generate-target-query-port-inventory.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const FIXTURE_PATH = "LedgeriOS/LedgerTargetCore/Fixture.swift";
const FIXTURE_OWNER = "SWIFT-FIXTURE000001";

function surface(overrides = {}) {
  return {
    id: FIXTURE_OWNER,
    discovery: "automatic",
    kind: "swift_logic",
    name: FIXTURE_PATH,
    sourcePresence: "present",
    sourceRefs: [{ path: FIXTURE_PATH }],
    status: "verified",
    ...overrides,
  };
}

function manifest(surfaces = [surface()]) {
  return { surfaces };
}

function scan(text, ownerManifest = manifest(), sourcePath = FIXTURE_PATH) {
  return inventoryFromSources([{ path: sourcePath, text }], ownerManifest);
}

function fixtureProtocol(signature, options = {}) {
  const name = options.name ?? "FixtureQuerying";
  return `${options.access ?? "public"} protocol ${name}: Sendable {\n${signature}\n}\n`;
}

function oneMethod(inventory) {
  assert.equal(inventory.methods.length, 1);
  return inventory.methods[0];
}

function tempArtifacts() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "target-query-ports-"));
  return {
    directory,
    paths: {
      json: path.join(directory, "inventory.json"),
      markdown: path.join(directory, "inventory.md"),
    },
  };
}

test("repository baseline is exactly the reviewed 17-owner, 17-protocol, 19-method inventory", () => {
  const inventory = buildRepositoryInventory(ROOT);
  assert.deepEqual(inventory.totals, {
    ownerSurfaces: 17,
    protocols: 17,
    methods: 19,
    observationMethods: 19,
    requestResponseMethods: 0,
  });
  assert.ok(inventory.methods.every((method) => method.selector.startsWith("watch")));
  assert.ok(inventory.methods.every((method) => method.category === "observation"));
  assert.equal(new Set(inventory.methods.map((method) => method.id)).size, 19);
  assert.ok(inventory.methods.every((method) => /^TQUERY-[A-F0-9]{12}$/.test(method.id)));
  assert.ok(inventory.methods.every((method) => /^[a-f0-9]{64}$/.test(method.signatureHash)));

  const multiMethod = Object.fromEntries(
    inventory.protocols
      .filter((protocol) => protocol.methodCount > 1)
      .map((protocol) => [
        protocol.name,
        inventory.methods
          .filter((method) => method.protocol === protocol.name)
          .map((method) => method.selector)
          .sort(),
      ]),
  );
  assert.deepEqual(multiMethod, {
    ClientProjectDirectoryQuerying: ["watchClients", "watchProjects"],
    OperationQuerying: ["watchOperation", "watchUnresolvedOperations"],
  });
});

test("inventory and rendered bytes are deterministic across source order, CRLF, tabs, whitespace, comments, and strings", () => {
  const sourceA = `
    // protocol FakeQuerying { func watchFake() }
    let decoy = "protocol StringQuerying { func watchString() }"
    public protocol AlphaQuerying {
      /* outer /* nested */ comment */
      @available(*, message: "first")
      func watchAlpha( value: [String: Int] ) -> AsyncStream<Int>
    }
  `;
  const normalizedA = sourceA
    .replace("message: \"first\"", "message:\t\"different ignored content\"")
    .replace("func watchAlpha( value", "func\twatchAlpha(value")
    .replaceAll("\n", "\r\n");
  const pathA = "LedgeriOS/LedgerTargetCore/Alpha.swift";
  const pathB = "LedgeriOS/LedgerTargetCore/Beta.swift";
  const surfaces = [
    surface({ id: "SWIFT-ALPHA0000001", name: pathA, sourceRefs: [{ path: pathA }] }),
    surface({ id: "SWIFT-BETA00000001", name: pathB, sourceRefs: [{ path: pathB }] }),
  ];
  const sourceB = "public protocol BetaQuerying { func watchBeta() -> Int }\n";
  const first = inventoryFromSources(
    [{ path: pathB, text: sourceB }, { path: pathA, text: sourceA }],
    manifest(surfaces),
  );
  const second = inventoryFromSources(
    [{ path: pathA, text: normalizedA }, { path: pathB, text: sourceB }],
    manifest([...surfaces].reverse()),
  );
  assert.deepEqual(second, first);
  assert.deepEqual(renderArtifacts(second), renderArtifacts(first));
});

test("masking preserves source length, line separators, and token separation", () => {
  const source = "public/* nested /* body */ end */protocol FixtureQuerying {\n  let text = #\"} ) ]\"#\n}\n";
  const masked = maskSwiftSource(source);
  assert.equal(masked.length, source.length);
  assert.deepEqual(
    [...masked.matchAll(/\n/g)].map((match) => match.index),
    [...source.matchAll(/\n/g)].map((match) => match.index),
  );
  assert.match(masked, /^public\s+protocol/);
  assert.doesNotMatch(masked, /body|text = #|[)\]]/);
});

test("ordinary, multiline, and raw interpolation masks nested strings and fake declarations", () => {
  const source = String.raw`
    let ordinary = "prefix \(render("public protocol FakeQuerying { func watchFake( } ]")) suffix"
    let multiline = """
      prefix \(render(#"public protocol MultilineFakeQuerying { func watchMultilineFake() -> Int } ]"#))
      suffix
      """
    let rawMultiline = ##"""
      prefix \##(render("public protocol RawFakeQuerying { func watchRawFake() -> Int } )"))
      suffix
      """##
    public protocol FixtureQuerying {
      func watchReal() -> Int
    }
  `;
  assert.deepEqual(scan(source).methods.map((method) => method.selector), ["watchReal"]);

  const unterminated = [
    String.raw`let value = "prefix \(render("inner")`,
    String.raw`let value = """prefix \(render(#"inner"#)`,
    String.raw`let value = ##"prefix \##(render("inner")`,
  ];
  for (const candidate of unterminated) {
    const messages = [];
    for (let attempt = 0; attempt < 2; attempt += 1) {
      assert.throws(() => maskSwiftSource(candidate), (error) => {
        messages.push(error.message);
        return /unterminated string (?:interpolation|literal)/.test(error.message);
      });
    }
    assert.equal(messages[1], messages[0]);
  }
});

test("regex literals mask bare, extended, nested, and interpolated declaration decoys without treating division as regex", () => {
  const source = String.raw`
    let bare = /public protocol BareFakeQuerying { func watchBareFake() -> Int }/
    let extended = #/public protocol ExtendedFakeQuerying {
      func watchExtendedFake() -> Int
      \#(render("public protocol NestedFakeQuerying { func watchNestedFake() -> Int } } ]"))
    }/#
    let nested = /prefix \(render(#/public protocol RegexFakeQuerying { func watchRegexFake() }/#)) suffix/
    let divided = Double(value) / 1_000
    let afterComment = /* masked context */ /public protocol CommentFakeQuerying { func watchCommentFake() -> Int }/
    let dividedAfterComment = Double(value) /* masked context */ / 1_000
    func makeRegex() {
      return /* masked context */ /public protocol ReturnFakeQuerying { func watchReturnFake() -> Int }/
    }
    public protocol FixtureQuerying {
      func watchReal() -> Int
    }
  `;
  assert.deepEqual(scan(source).methods.map((method) => method.selector), ["watchReal"]);
  assert.match(maskSwiftSource(source), /Double\(value\) \/ 1_000/);
  assert.match(maskSwiftSource(source), /Double\(value\)\s+\/ 1_000/);

  const unterminated = [
    "let value = /unterminated\n",
    "let value = #/unterminated",
    String.raw`let value = #/prefix \#(render("inner")/#`,
  ];
  for (const candidate of unterminated) {
    const messages = [];
    for (let attempt = 0; attempt < 2; attempt += 1) {
      assert.throws(() => maskSwiftSource(candidate), (error) => {
        messages.push(error.message);
        return /unterminated (?:regex literal|string interpolation)/.test(error.message);
      });
    }
    assert.equal(messages[1], messages[0]);
  }
});

test("multiline attributes, nested generics, tuple/function types, async throws, returns, and where clauses parse exactly", () => {
  const inventory = scan(`
    @MainActor
    public protocol FixtureQuerying: Sendable {
      var readiness: Bool { get }
      @available(
        *,
        deprecated,
        message: "masked"
      )
      func fetch<Value, Failure>(
        _ input: [String: Result<(Value, (Int) -> Value), Failure>],
        transform: @escaping (Value) async throws -> [Value]
      ) async throws
        -> AsyncThrowingStream<[Value], Error>
      where Value: Sendable,
            Failure: Error
    }
  `);
  const method = oneMethod(inventory);
  assert.equal(method.selector, "fetch");
  assert.equal(method.category, "request_response");
  assert.match(method.signature, /^@ available \(/);
  assert.match(method.signature, /func fetch < Value , Failure > \(/);
  assert.match(method.signature, /async throws -> AsyncThrowingStream/);
  assert.match(method.signature, /where Value : Sendable , Failure : Error$/);
});

test("split opaque and attributed function returns remain complete before the next direct method", () => {
  const inventory = scan(`
    public protocol FixtureQuerying {
      func fetchOpaque() -> some
        Sendable
      func fetchAttributed() -> @Sendable
        () async -> Int
      func watchTail() -> Int
    }
  `);
  assert.deepEqual(
    inventory.methods.map((method) => [method.selector, method.signature]),
    [
      ["fetchAttributed", "func fetchAttributed ( ) -> @ Sendable ( ) async -> Int"],
      ["fetchOpaque", "func fetchOpaque ( ) -> some Sendable"],
      ["watchTail", "func watchTail ( ) -> Int"],
    ],
  );
});

test("protocol headers and complete effect, return, and where tails are validated", () => {
  const method = oneMethod(scan(`
    public protocol FixtureQuerying<Element>: Sendable, AnyObject
    where Element: Sendable {
      func fetch<Failure>() async throws(Failure)
        -> some Sendable
      where Failure: Error
    }
  `));
  assert.equal(method.selector, "fetch");
  assert.match(method.signature, /async throws \( Failure \) -> some Sendable where Failure : Error$/);

  const invalidHeaders = [
    "public protocol FixtureQuerying nonsense { func fetch() -> Int }",
    "public protocol FixtureQuerying: { func fetch() -> Int }",
    "public protocol FixtureQuerying where { func fetch() -> Int }",
    "public protocol FixtureQuerying<Element: Sendable { func fetch() -> Int }",
    "public protocol FixtureQuerying: Sendable nonsense { func fetch() -> Int }",
    "public protocol FixtureQuerying: Sendable + Other { func fetch() -> Int }",
    "public protocol 123Querying { func fetch() -> Int }",
    "public protocol `FixtureQuerying` { func fetch() -> Int }",
    "public protocol FixtureQuerying where Element { func fetch() -> Int }",
    "public protocol FixtureQuerying where Element = Sendable { func fetch() -> Int }",
    "public protocol FixtureQuerying where Element: Sendable, { func fetch() -> Int }",
  ];
  for (const source of invalidHeaders) {
    assert.throws(
      () => scan(source),
      /protocol|inheritance|where|primary|delimiter|adjacent|inherited type/,
    );
  }

  const invalidTails = [
    "func fetch() garbage",
    "func fetch() ->",
    "func fetch() where",
    "func fetch() throws async -> Int",
    "func fetch() async async -> Int",
    "func fetch() rethrows(Error) -> Int",
    "func fetch() -> Int + Other",
    "func fetch() -> Int, Other",
    "func fetch() -> Int: Other",
    "func fetch() -> (Int Garbage)",
    "func fetch() -> Result<Int Garbage, Error>",
    "func fetch() -> Array<>",
    "func fetch() -> Result<Int,, Error>",
    "func fetch() -> Array<Int.>",
    "func fetch() -> Array<Int &>",
    "func fetch() -> Array<@>",
    "func fetch() -> Array<Int ->>",
    "func fetch() -> Array<~>",
    "func fetch() -> [String:]",
    "func fetch() -> (, Int)",
    "func fetch() -> . Int",
    "func fetch() -> & Int",
    "func fetch() -> ? Int",
    "func fetch() -> -> Int",
    "func fetch() -> @ Int",
    "func fetch() -> Int where",
    "func fetch<T>() -> Int where T = Sendable",
  ];
  for (const signature of invalidTails) {
    assert.throws(() => scan(fixtureProtocol(signature)), /tail|empty|unsupported|rethrows|where|return/);
  }

  const validEndpointTypes = [
    "func fetch() -> Outer.Inner",
    "func fetch() -> any Readable & Sendable",
    "func fetch() -> @Sendable () async -> Outer.Inner",
    "func fetch<Value: ~Copyable>(value: borrowing Value) -> Value",
  ];
  for (const signature of validEndpointTypes) oneMethod(scan(fixtureProtocol(signature)));
});

test("generic parameters and parameter clauses require complete typed components", () => {
  const method = oneMethod(scan(fixtureProtocol(`
    func fetch<Value: Sendable, Failure: Error, each Element>(
      _ input: [String: Result<(Value, (Int) -> Value), Failure>],
      label local: @escaping @Sendable (Value) async throws -> [Value],
      values: repeat each Element
    ) async throws(Failure) -> (Value, [String: Value])
  `)));
  assert.equal(method.selector, "fetch");
  assert.match(method.signature, /Value : Sendable , Failure : Error , each Element/);
  assert.match(method.signature, /label local : @ escaping @ Sendable/);
  assert.match(method.signature, /values : repeat each Element/);

  const invalidGenerics = [
    "func watch<>() -> Int",
    "func watch<, Value>() -> Int",
    "func watch<Value,>() -> Int",
    "func watch<Value,, Failure>() -> Int",
    "func watch<Value:>() -> Int",
    "func watch<: Sendable>() -> Int",
    "func watch<Value:: Sendable>() -> Int",
    "func watch<Value: Sendable: Other>() -> Int",
    "func watch<Value nonsense>() -> Int",
    "func watch<Value == Other>() -> Int",
    "func watch<each>() -> Int",
  ];
  for (const signature of invalidGenerics) {
    assert.throws(() => scan(fixtureProtocol(signature)), /generic|constraint|component|empty/);
  }

  const invalidParameters = [
    "func watch(nonsense) -> Int",
    "func watch(: Int) -> Int",
    "func watch(value:) -> Int",
    "func watch(first second third: Int) -> Int",
    "func watch(value:: Int) -> Int",
    "func watch(value: Int: String) -> Int",
    "func watch(first: Int,, second: String) -> Int",
    "func watch(value: Int,) -> Int",
    "func watch(value = defaultValue: Int) -> Int",
    "func watch(value: Int = defaultValue) -> Int",
    "func watch(value: (Int Garbage)) -> Int",
    "func watch(value: Array<Int Garbage>) -> Int",
    "func watch(value: Array<>) -> Int",
    "func watch(value: Result<Int,, Error>) -> Int",
    "func watch(value: Array<Int.>) -> Int",
    "func watch(value: Array<Int &>) -> Int",
    "func watch(value: Array<. Int>) -> Int",
    "func watch(value: [String:]) -> Int",
    "func watch(value: (, Int)) -> Int",
  ];
  for (const signature of invalidParameters) {
    assert.throws(() => scan(fixtureProtocol(signature)), /parameter|separator|labels|empty|unsupported/);
  }
});

test("direct declaration prefixes never disappear into or detach from first and later methods", () => {
  const unsupported = [
    fixtureProtocol("nonisolated func first() -> Int"),
    fixtureProtocol("nonisolated\nfunc first() -> Int"),
    fixtureProtocol("borrowing func first() -> Int"),
    fixtureProtocol("borrowing\nfunc first() -> Int"),
    fixtureProtocol("frobnicate func first() -> Int"),
    fixtureProtocol("frobnicate\nfunc first() -> Int"),
    fixtureProtocol("func first() -> Int; nonisolated func second() -> Int"),
    fixtureProtocol("func first() -> Int\nnonisolated\nfunc second() -> Int"),
    fixtureProtocol("func first() -> Int; borrowing func second() -> Int"),
    fixtureProtocol("func first() -> Int\nborrowing\nfunc second() -> Int"),
    fixtureProtocol("func first() -> Int; frobnicate func second() -> Int"),
    fixtureProtocol("func first() -> Int\nfrobnicate\nfunc second() -> Int"),
    fixtureProtocol("var state: Int { get }\nfrobnicate\nfunc first() -> Int"),
  ];
  for (const source of unsupported) {
    assert.throws(() => scan(source), /unsupported|ambiguous/);
  }

  const attributed = scan(fixtureProtocol(`
    func first() -> Int
    @MainActor
    func second() -> Int
  `));
  assert.deepEqual(
    attributed.methods.map((method) => [method.selector, method.signature]),
    [
      ["first", "func first ( ) -> Int"],
      ["second", "@ MainActor func second ( ) -> Int"],
    ],
  );
});

test("non-ASCII code identifiers fail closed while Unicode in masked forms is harmless", () => {
  assert.throws(
    () => scan("public protocol CaféQuerying { func watchValue() -> Int }"),
    /unsupported non-ASCII code token/,
  );
  assert.throws(
    () => scan("public protocol FixtureQuerying { func wätchValue() -> Int }"),
    /unsupported non-ASCII code token/,
  );
  const inventory = scan(String.raw`
    // CaféQuerying and wätchComment are masked.
    let text = "é public protocol FakeQuerying { func wätchFake() }"
    let regex = #/é public protocol RegexFakeQuerying { func wätchRegexFake() }/#
    public protocol FixtureQuerying { func watchReal() -> Int }
  `);
  assert.deepEqual(inventory.methods.map((method) => method.selector), ["watchReal"]);
});

test("only public exact-suffix Querying protocol requirements are inventoried", () => {
  const inventory = scan(`
    // public protocol CommentQuerying { func watchComment() }
    let normal = "public protocol StringQuerying { func watchString( } and an escaped quote: \\""
    let multiline = """
      public protocol MultilineStringQuerying { func watchMultiline() }
      } ) ]
      """
    let raw = #"public protocol RawStringQuerying { func watchRaw() }"#
    let rawMultiline = ##"""
      public protocol RawMultilineQuerying { func watchRawMultiline() }
      } ) ]
      """##
    let escapedMultiline = """
      an escaped delimiter does not end this string: \\""" still masked
      public protocol EscapedStringQuerying { func watchEscaped() }
      """
    protocol InternalQuerying { func watchInternal() }
    private protocol PrivateQuerying { func watchPrivate() }
    public protocol QueryingExtra { func watchWrongSuffix() }
    public protocol FixtureQuerying {
      var state: Int { get }
      func watchIncluded() -> Int
    }
    extension FixtureQuerying { func watchExtension() -> Int { 1 } }
    struct Implementation { func watchImplementation() -> Int { 1 } }
  `);
  assert.deepEqual(inventory.methods.map((method) => method.selector), ["watchIncluded"]);
});

test("stable IDs use identity only while every signature-axis change changes its signature hash", () => {
  const signatures = [
    "func fetch(label value: Int) -> String",
    "func fetch(other value: Int) -> String",
    "func fetch(label value: UInt) -> String",
    "func fetch(label value: Int) -> [String]",
    "func fetch<T>(label value: T) -> String",
    "@MainActor func fetch(label value: Int) -> String",
    "func fetch(label value: Int) async -> String",
    "func fetch(label value: Int) throws -> String",
    "func fetch<T>(label value: T) -> String where T: Sendable",
  ];
  const methods = signatures.map((signature) => oneMethod(scan(fixtureProtocol(signature))));
  assert.equal(new Set(methods.map((method) => method.id)).size, 1);
  assert.equal(new Set(methods.map((method) => method.signatureHash)).size, signatures.length);
  const changedIdentities = [
    methods[0],
    oneMethod(scan(fixtureProtocol("func renamed(label value: Int) -> String"))),
    oneMethod(scan(fixtureProtocol(signatures[0], { name: "RenamedQuerying" }))),
    oneMethod(scan(
      fixtureProtocol(signatures[0]),
      manifest([surface({ id: "SWIFT-DIFFERENT0001" })]),
    )),
  ];
  assert.equal(new Set(changedIdentities.map((method) => method.id)).size, 4);

  const temporary = tempArtifacts();
  try {
    writeArtifacts(renderArtifacts(scan(fixtureProtocol(signatures[0]))), temporary.paths);
    for (const signature of signatures.slice(1)) {
      assert.throws(
        () => checkArtifacts(renderArtifacts(scan(fixtureProtocol(signature))), temporary.paths),
        /stale generated/,
      );
    }
  } finally {
    fs.rmSync(temporary.directory, { recursive: true, force: true });
  }
});

test("added, removed, and renamed protocols or methods make checked artifacts stale without writing", () => {
  const baseline = scan(fixtureProtocol("func watchFixture() -> Int"));
  const changedInventories = [
    scan(fixtureProtocol("func watchFixture() -> Int\nfunc watchAdded() -> Int")),
    inventoryFromSources([], manifest([])),
    scan(fixtureProtocol("func watchFixture() -> Int", { name: "RenamedQuerying" })),
    scan(fixtureProtocol("func watchRenamed() -> Int")),
    scan(fixtureProtocol("func watchFixture() -> Int\nfunc watchSecond() -> Int")),
  ];
  const temporary = tempArtifacts();
  try {
    writeArtifacts(renderArtifacts(baseline), temporary.paths);
    const oldDate = new Date("2001-01-01T00:00:00Z");
    fs.utimesSync(temporary.paths.json, oldDate, oldDate);
    fs.utimesSync(temporary.paths.markdown, oldDate, oldDate);
    const before = Object.fromEntries(
      Object.entries(temporary.paths).map(([kind, filePath]) => [kind, {
        bytes: fs.readFileSync(filePath),
        mtimeMs: fs.statSync(filePath).mtimeMs,
      }]),
    );
    for (const changed of changedInventories) {
      assert.throws(() => checkArtifacts(renderArtifacts(changed), temporary.paths), /stale generated/);
      for (const [kind, filePath] of Object.entries(temporary.paths)) {
        assert.deepEqual(fs.readFileSync(filePath), before[kind].bytes);
        assert.equal(fs.statSync(filePath).mtimeMs, before[kind].mtimeMs);
      }
    }
    const twoMethods = scan(fixtureProtocol("func watchFixture() -> Int\nfunc watchSecond() -> Int"));
    writeArtifacts(renderArtifacts(twoMethods), temporary.paths);
    assert.throws(() => checkArtifacts(renderArtifacts(baseline), temporary.paths), /stale generated/);
  } finally {
    fs.rmSync(temporary.directory, { recursive: true, force: true });
  }
});

test("malformed, ambiguous, unsupported, duplicate, empty, and unowned inputs fail closed", () => {
  const invalidSources = [
    ["static method", fixtureProtocol("static func watchFixture() -> Int"), manifest()],
    ["class method", fixtureProtocol("class func watchFixture() -> Int"), manifest()],
    ["method body", fixtureProtocol("func watchFixture() -> Int { 1 }"), manifest()],
    ["operator selector", fixtureProtocol("func ==(lhs: Int, rhs: Int) -> Bool"), manifest()],
    ["missing parameters", fixtureProtocol("func watchFixture -> Int"), manifest()],
    ["missing protocol body", "public protocol FixtureQuerying", manifest()],
    ["ambiguous adjacent functions", fixtureProtocol("func first() -> Int func second() -> Int"), manifest()],
    ["unbalanced parameters", fixtureProtocol("func watchFixture(value: Int -> Int"), manifest()],
    ["unbalanced brackets", fixtureProtocol("func watchFixture(value: [Int) -> Int"), manifest()],
    ["unbalanced generics", fixtureProtocol("func watchFixture<T(value: T) -> Int"), manifest()],
    ["overload", fixtureProtocol("func watchFixture() -> Int\nfunc watchFixture(value: Int) -> Int"), manifest()],
    ["empty", fixtureProtocol("var value: Int { get }"), manifest()],
    ["unterminated block comment", "/* nested /* still open */", manifest()],
    ["unterminated string", "let value = \"never closed", manifest()],
    ["unterminated multiline string", "let value = \"\"\"never closed", manifest()],
    ["unterminated raw string", "let value = ##\"never closed", manifest()],
    ["missing owner", fixtureProtocol("func watchFixture() -> Int"), manifest([])],
    [
      "ambiguous owner",
      fixtureProtocol("func watchFixture() -> Int"),
      manifest([surface(), surface({ id: "SWIFT-FIXTURE000002" })]),
    ],
  ];
  for (const [label, source, ownerManifest] of invalidSources) {
    assert.throws(() => scan(source, ownerManifest), undefined, label);
  }
  for (const status of [
    "unverified",
    "discovered",
    "characterized",
    "target_mapped",
    "blocked",
    "promoted",
    "retired",
  ]) {
    assert.throws(
      () => scan(fixtureProtocol("func watchFixture() -> Int"), manifest([surface({ status })])),
      /invalid manifest owner status/,
      status,
    );
  }
});

test("implemented and later target owners are inventoried before and after verification", () => {
  for (const status of ["implemented", "verified", "rehearsed", "cutover_ready"]) {
    const method = oneMethod(
      scan(fixtureProtocol("func watchFixture() -> Int"), manifest([surface({ status })])),
    );
    assert.equal(method.ownerStatus, status);
  }
});

test("owner lifecycle transitions preserve query identity, signature, and inventory digest while changing review bytes", () => {
  const implemented = scan(
    fixtureProtocol("func watchFixture() -> Int"),
    manifest([surface({ status: "implemented" })]),
  );
  const verified = scan(
    fixtureProtocol("func watchFixture() -> Int"),
    manifest([surface({ status: "verified" })]),
  );
  assert.equal(implemented.methods[0].id, verified.methods[0].id);
  assert.equal(implemented.methods[0].signatureHash, verified.methods[0].signatureHash);
  assert.equal(implemented.inventoryDigest, verified.inventoryDigest);
  assert.notEqual(renderArtifacts(implemented).json, renderArtifacts(verified).json);
  assert.notEqual(renderArtifacts(implemented).markdown, renderArtifacts(verified).markdown);
});

test("a fail-closed scan completes before generate overwrites either artifact", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "target-query-ports-generate-"));
  const core = path.join(directory, "LedgeriOS/LedgerTargetCore");
  const conversion = path.join(directory, "docs/plans/ledger-accounting-redesign/conversion");
  fs.mkdirSync(core, { recursive: true });
  fs.mkdirSync(conversion, { recursive: true });
  fs.writeFileSync(
    path.join(core, "Fixture.swift"),
    fixtureProtocol("static func watchFixture() -> Int"),
  );
  fs.writeFileSync(
    path.join(conversion, "conversion-manifest.json"),
    JSON.stringify(manifest([surface()])),
  );
  const paths = artifactPaths(directory);
  fs.writeFileSync(paths.json, "json sentinel\n");
  fs.writeFileSync(paths.markdown, "markdown sentinel\n");
  try {
    assert.throws(() => execute("generate", directory), /unsupported|ambiguous/);
    assert.equal(fs.readFileSync(paths.json, "utf8"), "json sentinel\n");
    assert.equal(fs.readFileSync(paths.markdown, "utf8"), "markdown sentinel\n");
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test("duplicate protocols reject, duplicate references on one exact owner do not", () => {
  const pathA = "LedgeriOS/LedgerTargetCore/A.swift";
  const pathB = "LedgeriOS/LedgerTargetCore/B.swift";
  const protocol = "public protocol DuplicateQuerying { func watchValue() -> Int }";
  assert.throws(
    () => inventoryFromSources(
      [{ path: pathA, text: protocol }, { path: pathB, text: protocol }],
      manifest([
        surface({ id: "SWIFT-A00000000001", name: pathA, sourceRefs: [{ path: pathA }] }),
        surface({ id: "SWIFT-B00000000001", name: pathB, sourceRefs: [{ path: pathB }] }),
      ]),
    ),
    /duplicate Querying protocol/,
  );
  const duplicateRefs = surface({ sourceRefs: [{ path: FIXTURE_PATH }, { path: FIXTURE_PATH }] });
  assert.equal(
    scan(fixtureProtocol("func watchFixture() -> Int"), manifest([duplicateRefs])).methods.length,
    1,
  );
});

test("missing artifacts fail, write then check is byte-identical, and check is read-only", () => {
  const artifacts = renderArtifacts(scan(fixtureProtocol("func watchFixture() -> Int")));
  const temporary = tempArtifacts();
  try {
    assert.throws(() => checkArtifacts(artifacts, temporary.paths), /missing generated json/);
    fs.writeFileSync(temporary.paths.json, artifacts.json);
    assert.throws(() => checkArtifacts(artifacts, temporary.paths), /missing generated markdown/);
    writeArtifacts(artifacts, temporary.paths);
    const before = Object.fromEntries(
      Object.entries(temporary.paths).map(([kind, filePath]) => [kind, {
        bytes: fs.readFileSync(filePath),
        mtimeMs: fs.statSync(filePath).mtimeMs,
      }]),
    );
    checkArtifacts(artifacts, temporary.paths);
    for (const [kind, filePath] of Object.entries(temporary.paths)) {
      assert.deepEqual(fs.readFileSync(filePath), before[kind].bytes);
      assert.equal(fs.statSync(filePath).mtimeMs, before[kind].mtimeMs);
    }
  } finally {
    fs.rmSync(temporary.directory, { recursive: true, force: true });
  }
});

test("repository generated JSON and Markdown match and contain no timestamp", () => {
  const inventory = buildRepositoryInventory(ROOT);
  const artifacts = renderArtifacts(inventory);
  checkArtifacts(artifacts, artifactPaths(ROOT));
  assert.deepEqual(JSON.parse(artifacts.json), inventory);
  assert.doesNotMatch(artifacts.json, /generatedAt|timestamp/i);
  assert.match(artifacts.markdown, /generated diffs still require human review/i);
  assert.match(artifacts.markdown, /\| TQUERY \| Owner \| Status \|/);
  assert.match(artifacts.markdown, /\| `TQUERY-038289DD7D2C` \| `SWIFT-0DCDAFBB4350` \| `verified` \|/);
  assert.match(artifacts.markdown, /does not define product semantics/i);
});

test("repository package and CI hooks are the exact dependency-free control topology", () => {
  const packageDocument = JSON.parse(fs.readFileSync(path.join(ROOT, "package.json"), "utf8"));
  assert.equal(
    packageDocument.scripts["target:query-ports:generate"],
    "node scripts/generate-target-query-port-inventory.mjs generate",
  );
  assert.equal(
    packageDocument.scripts["target:query-ports:check"],
    "node scripts/generate-target-query-port-inventory.mjs check",
  );
  assert.equal(
    packageDocument.scripts["target:query-ports:test"],
    "node --test scripts/tests/generate-target-query-port-inventory.test.mjs",
  );
  const generatorSource = fs.readFileSync(
    path.join(ROOT, "scripts/generate-target-query-port-inventory.mjs"),
    "utf8",
  );
  for (const match of generatorSource.matchAll(/from\s+"([^"]+)"/g)) {
    assert.match(match[1], /^node:/);
  }

  const workflow = fs.readFileSync(
    path.join(ROOT, ".github/workflows/supabase-conversion-control.yml"),
    "utf8",
  );
  const conversionJob = workflow.slice(
    workflow.indexOf("  conversion-control:"),
    workflow.indexOf("  target-environment:"),
  );
  assert.match(conversionJob, /npm run target:query-ports:test/);
  assert.match(conversionJob, /npm run target:query-ports:check/);
  const targetJob = workflow.slice(workflow.indexOf("  target-environment:"));
  assert.match(targetJob, /^  target-environment:\n(?:.*\n){0,4}    needs: conversion-control$/m);
});
