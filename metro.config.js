// Learn more https://docs.expo.io/guides/customizing-metro
const { getDefaultConfig } = require('expo/metro-config');

/** @type {import('expo/metro-config').MetroConfig} */
const config = getDefaultConfig(__dirname);

// Allow .html files to be loaded as assets via require()
// This is needed for the PDF extraction WebView bridge.
config.resolver.assetExts.push('html');

module.exports = config;
