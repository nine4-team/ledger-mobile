import { useCallback, useMemo, useState } from 'react';
import {
  View,
  StyleSheet,
  TextInput,
  Alert,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  useWindowDimensions,
} from 'react-native';
import { useRouter } from 'expo-router';
import Svg, { Circle, Path } from 'react-native-svg';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Screen } from '../../src/components/Screen';
import { AppText } from '../../src/components/AppText';
import { AppButton } from '../../src/components/AppButton';
import { BrandLogo } from '../../src/components/BrandLogo';
import { GoogleMark } from '../../src/components/GoogleMark';
import { useAuthStore } from '../../src/auth/authStore';
import { isAuthBypassEnabled } from '../../src/auth/authConfig';
import { useTheme, useUIKitTheme } from '../../src/theme/ThemeProvider';
import { getCardStyle, getTextInputStyle } from '../../src/ui';

function EyeIcon({ size = 20, color, crossed }: { size?: number; color: string; crossed?: boolean }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24">
      <Path
        d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"
        fill="none"
        stroke={color}
        strokeWidth={2}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <Circle
        cx={12}
        cy={12}
        r={3}
        fill="none"
        stroke={color}
        strokeWidth={2}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      {crossed ? (
        <Path
          d="M2 2l20 20"
          fill="none"
          stroke={color}
          strokeWidth={2}
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      ) : null}
    </Svg>
  );
}

export default function SignInScreen() {
  const [loginMethod, setLoginMethod] = useState<'google' | 'email'>('email');
  const [error, setError] = useState<string>('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const router = useRouter();
  const { signIn } = useAuthStore();
  const insets = useSafeAreaInsets();
  const { height: windowHeight } = useWindowDimensions();
  const [emailAnchorHeight, setEmailAnchorHeight] = useState<number | null>(null);
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  const styles = useMemo(
    () =>
      StyleSheet.create({
        container: {
          flex: 1,
          justifyContent: 'flex-start',
        },
        content: {
          width: '100%',
          maxWidth: 520,
          alignSelf: 'center',
        },
        brandHeader: {
          alignItems: 'center',
          marginBottom: theme.spacing.lg,
        },
        brandLogoTile: {
          backgroundColor: '#fff',
          borderRadius: 26,
          padding: 7,
          borderWidth: 1,
          borderColor: 'rgba(0,0,0,0.06)',
          ...Platform.select({
            ios: {
              shadowColor: '#000',
              shadowOpacity: 0.14,
              shadowRadius: 28,
              shadowOffset: { width: 0, height: 12 },
            },
            android: {
              elevation: 10,
            },
            default: {},
          }),
        },
        card: {
          width: '100%',
          alignSelf: 'center',
          ...getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.lg }),
        },
        tabs: {
          flexDirection: 'row',
          borderBottomWidth: 1,
          borderBottomColor: theme.colors.border,
          marginBottom: theme.spacing.lg,
        },
        tab: {
          flex: 1,
          paddingVertical: theme.spacing.sm,
          borderBottomWidth: 2,
          borderBottomColor: 'transparent',
          alignItems: 'center',
        },
        tabActive: {
          borderBottomColor: theme.colors.primary,
        },
        tabText: {
          color: theme.colors.textSecondary,
          fontWeight: '600',
        },
        tabTextActive: {
          color: theme.colors.primary,
        },
        errorBanner: {
          borderWidth: 1,
          borderColor: theme.colors.error,
          borderRadius: 12,
          padding: theme.spacing.md,
          marginBottom: theme.spacing.md,
        },
        errorText: {
          color: theme.colors.error,
        },
        section: {
          gap: theme.spacing.sm,
        },
        input: {
          ...getTextInputStyle(uiKitTheme, {
            radius: 8,
            paddingVertical: 10,
            paddingHorizontal: 12,
            fontSize: 16,
          }),
        },
        passwordRow: {
          flexDirection: 'row',
          alignItems: 'center',
        },
        passwordInput: {
          flex: 1,
          paddingRight: 56,
        },
        showHideButton: {
          position: 'absolute',
          right: 12,
          height: '100%',
          justifyContent: 'center',
        },
        googleIcon: {
          marginTop: 1,
        },
        googleSignUpLink: {
          marginTop: theme.spacing.sm,
          alignItems: 'center',
        },
        googleSignUpText: {
          color: theme.colors.primary,
          fontWeight: '600',
        },
        primaryButton: {
          marginTop: theme.spacing.md,
        },
        signUpLink: {
          marginTop: theme.spacing.md,
          alignItems: 'center',
        },
        signUpText: {
          color: theme.colors.primary,
          fontWeight: '600',
        },
      }),
    [theme, uiKitTheme]
  );

  // Keep the logo + card "anchored" to the email layout's vertical position to avoid
  // the whole stack re-centering when the tab content height changes.
  const anchorSpacerHeight = useMemo(() => {
    const min = theme.spacing.xxxl;
    if (!emailAnchorHeight) return min;

    const usableHeight = windowHeight - insets.top - insets.bottom;
    const centeredTop = Math.max(0, (usableHeight - emailAnchorHeight) / 2);
    return Math.max(min, centeredTop);
  }, [emailAnchorHeight, insets.bottom, insets.top, theme, windowHeight]);

  const dynamicStyles = useMemo(
    () =>
      StyleSheet.create({
        insetsPadding: {
          paddingTop: insets.top,
          paddingBottom: insets.bottom,
        },
        anchorSpacer: {
          height: anchorSpacerHeight,
        },
      }),
    [anchorSpacerHeight, insets.bottom, insets.top]
  );

  const trimmedEmail = useMemo(() => email.trim(), [email]);

  const handleContentLayout = useCallback(
    (e: any) => {
      // Only "learn" the anchor position from the email layout (your desired baseline).
      if (loginMethod !== 'email') return;
      const nextHeight = e?.nativeEvent?.layout?.height;
      if (typeof nextHeight !== 'number') return;

      setEmailAnchorHeight((prev) => (prev != null && Math.abs(prev - nextHeight) < 1 ? prev : nextHeight));
    },
    [loginMethod]
  );

  const handleGoogleSignIn = () => {
    Alert.alert('Not set up yet', 'This skeleton currently supports email/password sign-in only.');
  };

  const handleSignIn = async () => {
    if (!trimmedEmail) {
      setError('Email is required');
      return;
    }
    if (!password) {
      setError('Password is required');
      return;
    }

    setLoading(true);
    try {
      setError('');
      await signIn(trimmedEmail, password);
      router.replace('/(tabs)');
    } catch (error: any) {
      setError(error?.message || 'Failed to sign in. Please check your email and password.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Screen>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={[styles.container, dynamicStyles.insetsPadding]}
      >
        <View style={dynamicStyles.anchorSpacer} />
        <View style={styles.content} onLayout={handleContentLayout}>
          <View style={styles.brandHeader}>
            <View style={styles.brandLogoTile}>
              <BrandLogo size={84} accessibilityLabel="App logo" />
            </View>
          </View>

          <View style={styles.card}>
            <View style={styles.tabs}>
              <Pressable
                onPress={() => {
                  setLoginMethod('google');
                  setError('');
                }}
                style={[styles.tab, loginMethod === 'google' && styles.tabActive]}
              >
                <AppText
                  variant="body"
                  style={[styles.tabText, loginMethod === 'google' && styles.tabTextActive]}
                >
                  Google
                </AppText>
              </Pressable>

              <Pressable
                onPress={() => {
                  setLoginMethod('email');
                  setError('');
                }}
                style={[styles.tab, loginMethod === 'email' && styles.tabActive]}
              >
                <AppText
                  variant="body"
                  style={[styles.tabText, loginMethod === 'email' && styles.tabTextActive]}
                >
                  Email
                </AppText>
              </Pressable>
            </View>

            {!!error && (
              <View style={styles.errorBanner}>
                <AppText variant="body" style={styles.errorText}>
                  {error}
                </AppText>
              </View>
            )}

            {loginMethod === 'google' ? (
              <View style={styles.section}>
                <AppButton
                  title="Sign In with Google"
                  onPress={handleGoogleSignIn}
                  leftIcon={<GoogleMark size={18} color={theme.colors.background} />}
                />

                <Pressable onPress={handleGoogleSignIn} style={styles.googleSignUpLink}>
                  <AppText variant="body" style={styles.googleSignUpText}>
                    Sign up with Google
                  </AppText>
                </Pressable>
              </View>
            ) : (
              <View style={styles.section}>
                <TextInput
                  style={styles.input}
                  placeholder="Email"
                  placeholderTextColor={uiKitTheme.input.placeholder}
                  value={email}
                  onChangeText={setEmail}
                  autoCapitalize="none"
                  keyboardType="email-address"
                  autoComplete="email"
                  returnKeyType="next"
                  onFocus={() => setError('')}
                />

                <View style={styles.passwordRow}>
                  <TextInput
                    style={[styles.input, styles.passwordInput]}
                    placeholder="Password"
                    placeholderTextColor={uiKitTheme.input.placeholder}
                    value={password}
                    onChangeText={setPassword}
                    secureTextEntry={!showPassword}
                    autoCapitalize="none"
                    autoComplete="password"
                    returnKeyType="done"
                    onSubmitEditing={handleSignIn}
                    onFocus={() => setError('')}
                  />
                  <Pressable
                    onPress={() => setShowPassword((v) => !v)}
                    style={styles.showHideButton}
                    hitSlop={8}
                    accessibilityRole="button"
                    accessibilityLabel={showPassword ? 'Hide password' : 'Show password'}
                  >
                    <EyeIcon color={theme.colors.textSecondary} crossed={showPassword} />
                  </Pressable>
                </View>

                <AppButton
                  title="Sign In"
                  onPress={handleSignIn}
                  loading={loading}
                  style={styles.primaryButton}
                />

                {isAuthBypassEnabled ? (
                  <AppButton
                    title="Continue as Guest"
                    variant="secondary"
                    onPress={() => router.replace('/(tabs)')}
                  />
                ) : null}

                <Pressable onPress={() => router.push('/(auth)/sign-up')} style={styles.signUpLink}>
                  <AppText variant="body" style={styles.signUpText}>
                    Create an account
                  </AppText>
                </Pressable>
              </View>
            )}
          </View>
        </View>
      </KeyboardAvoidingView>
    </Screen>
  );
}

