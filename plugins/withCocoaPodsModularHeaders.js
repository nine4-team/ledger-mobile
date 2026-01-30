const fs = require("fs");
const path = require("path");
const { withDangerousMod } = require("@expo/config-plugins");

function ensureUseModularHeaders(podfileContents) {
  if (podfileContents.includes("use_modular_headers!")) return podfileContents;

  const lines = podfileContents.split("\n");
  const insertAfterIdx = lines.findIndex((l) =>
    l.includes(":deterministic_uuids => false"),
  );

  const insertion = [
    "",
    "# Needed for Firebase Swift pods when CocoaPods is building pods as static libraries.",
    "# See: \"Swift pods cannot yet be integrated as static libraries\" error.",
    "use_modular_headers!",
    "",
  ];

  if (insertAfterIdx !== -1) {
    lines.splice(insertAfterIdx + 1, 0, ...insertion);
    return lines.join("\n");
  }

  const fallbackAfterIdx = lines.findIndex((l) =>
    l.includes("prepare_react_native_project!"),
  );
  if (fallbackAfterIdx !== -1) {
    lines.splice(fallbackAfterIdx, 0, ...insertion);
    return lines.join("\n");
  }

  return `${podfileContents}\n${insertion.join("\n")}\n`;
}

module.exports = function withCocoaPodsModularHeaders(config) {
  return withDangerousMod(config, [
    "ios",
    async (config) => {
      const iosProjectRoot = config.modRequest.platformProjectRoot;
      const podfilePath = path.join(iosProjectRoot, "Podfile");

      if (!fs.existsSync(podfilePath)) return config;

      const current = fs.readFileSync(podfilePath, "utf8");
      const next = ensureUseModularHeaders(current);
      if (next !== current) fs.writeFileSync(podfilePath, next);

      return config;
    },
  ]);
};

