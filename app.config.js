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

  // Enable native Firebase config per-platform (iOS only is OK).
  const hasIosGoogleServices = fileExists(iosGoogleServicesFile);
  const hasAndroidGoogleServices = fileExists(androidGoogleServicesFile);
  const enableNativeFirebase = hasIosGoogleServices || hasAndroidGoogleServices;

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
  const googleIosReversedClientId = process.env.EXPO_PUBLIC_GOOGLE_IOS_REVERSED_CLIENT_ID;

  if (enableNativeFirebase) {
    if (hasIosGoogleServices) {
      ios.googleServicesFile = iosGoogleServicesFile;
    } else {
      delete ios.googleServicesFile;
    }
    if (hasAndroidGoogleServices) {
      android.googleServicesFile = androidGoogleServicesFile;
    } else {
      delete android.googleServicesFile;
    }
  } else {
    delete ios.googleServicesFile;
    delete android.googleServicesFile;
  }

  if (googleIosReversedClientId) {
    const infoPlist = { ...(ios.infoPlist ?? {}) };
    const existingUrlTypes = Array.isArray(infoPlist.CFBundleURLTypes)
      ? infoPlist.CFBundleURLTypes
      : [];

    infoPlist.CFBundleURLTypes = [
      ...existingUrlTypes,
      {
        CFBundleURLSchemes: [googleIosReversedClientId],
      },
    ];

    ios.infoPlist = infoPlist;
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

