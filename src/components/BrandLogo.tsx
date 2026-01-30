import React, { useMemo } from 'react';
import { Image, ImageStyle, StyleProp } from 'react-native';

const BRAND_LOGO_SOURCE = require('../../nine4_logo.png');

export function BrandLogo({
  size = 72,
  rounded = true,
  style,
  accessibilityLabel = 'App logo',
}: {
  size?: number;
  rounded?: boolean;
  style?: StyleProp<ImageStyle>;
  accessibilityLabel?: string;
}) {
  const borderRadius = rounded ? Math.round(size * 0.24) : 0;
  const sizeStyle = useMemo(() => ({ width: size, height: size, borderRadius }), [borderRadius, size]);

  return (
    <Image
      source={BRAND_LOGO_SOURCE}
      accessibilityRole="image"
      accessibilityLabel={accessibilityLabel}
      resizeMode="contain"
      style={[sizeStyle, style]}
    />
  );
}

