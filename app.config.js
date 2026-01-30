const fs = require("fs");
const path = require("path");

const appJson = require("./app.json");

function fileExists(p) {
  if (!p) return false;
  const abs = path.isAbsolute(p) ? p : path.join(__dirname, p);
  return fs.existsSync(abs);
}

module.exports = () => {
  const baseExpoConfig = appJson.expo ?? {};

  // Provide these via env vars in CI / local secrets, or place the files at
  // the default repo root locations.
  const iosGoogleServicesFile =
    process.env.EXPO_IOS_GOOGLE_SERVICES_FILE ?? "./GoogleService-Info.plist";
  const androidGoogleServicesFile =
    process.env.EXPO_ANDROID_GOOGLE_SERVICES_FILE ?? "./google-services.json";

  // `@react-native-firebase/app` config plugin fails prebuild if iOS plist isn't set.
  // Only enable native Firebase config when both platform files exist.
  const enableNativeFirebase =
    fileExists(iosGoogleServicesFile) && fileExists(androidGoogleServicesFile);

  const plugins = Array.isArray(baseExpoConfig.plugins)
    ? baseExpoConfig.plugins.filter((p) => p !== "@react-native-firebase/app")
    : [];
  plugins.push("./plugins/withCocoaPodsModularHeaders");
  plugins.push([
    "expo-build-properties",
    {
      ios: {
        useFrameworks: "static",
      },
    },
  ]);
  if (enableNativeFirebase) plugins.push("@react-native-firebase/app");

  const ios = { ...(baseExpoConfig.ios ?? {}) };
  const android = { ...(baseExpoConfig.android ?? {}) };

  if (enableNativeFirebase) {
    ios.googleServicesFile = iosGoogleServicesFile;
    android.googleServicesFile = androidGoogleServicesFile;
  } else {
    delete ios.googleServicesFile;
    delete android.googleServicesFile;
  }

  return {
    expo: {
      ...baseExpoConfig,
      ios,
      android,
      plugins,
    },
  };
};

