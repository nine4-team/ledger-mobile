import { useCallback, useEffect, useMemo, useState } from 'react';
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
import { useRootNavigationState, useRouter } from 'expo-router';
import Svg, { Circle, Path } from 'react-native-svg';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Screen } from '../../src/components/Screen';
import { AppText } from '../../src/components/AppText';
import { AppButton } from '../../src/components/AppButton';
import { BrandLogo } from '../../src/components/BrandLogo';
import { GoogleMark } from '../../src/components/GoogleMark';
import { useAuthStore } from '../../src/auth/authStore';
import { isAuthBypassEnabled } from '../../src/auth/authConfig';
import { useAppearance, useTheme, useUIKitTheme } from '../../src/theme/ThemeProvider';
import { getCardStyle, getTextInputStyle } from '../../src/ui';
import { useNetworkStatus } from '../../src/hooks/useNetworkStatus';
import { useInviteTokenStore } from '../../src/auth/inviteTokenStore';

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
  const [googleLoading, setGoogleLoading] = useState(false);
  const router = useRouter();
  const rootNavigationState = useRootNavigationState();
  const { signIn, signInWithGoogle, user, timedOutWithoutAuth, retryInitialize } = useAuthStore();
  const insets = useSafeAreaInsets();
  const { height: windowHeight } = useWindowDimensions();
  const [emailAnchorHeight, setEmailAnchorHeight] = useState<number | null>(null);
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const { resolvedColorScheme } = useAppearance();
  const { isOnline } = useNetworkStatus();
  const { pendingToken, hydrate: hydrateToken } = useInviteTokenStore();

  // Hydrate token store on mount
  useEffect(() => {
    hydrateToken();
  }, [hydrateToken]);

  // Redirect to invite acceptance if there's a pending token after sign-in
  useEffect(() => {
    if (!rootNavigationState?.key) {
      return;
    }
    if (user && pendingToken) {
      router.replace(`/(auth)/invite/${pendingToken}`);
    } else if (user && !pendingToken) {
      // Normal sign-in flow - go to tabs
      router.replace('/(tabs)');
    }
  }, [pendingToken, rootNavigationState?.key, router, user]);

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
        brandLogoBorder: {
          borderWidth: 2,
          borderColor: theme.colors.primary,
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
        retryButton: {
          marginTop: theme.spacing.sm,
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
        googleSignUpLinkDisabled: {
          opacity: 0.5,
        },
        googleSignUpText: {
          color: theme.colors.primary,
          fontWeight: '400',
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
    [resolvedColorScheme, theme, uiKitTheme]
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

  const handleGoogleSignIn = async () => {
    if (!isOnline) return;
    setGoogleLoading(true);
    try {
      setError('');
      await signInWithGoogle();
      // Don't navigate here - let useEffect handle redirect based on pending token
    } catch (error: any) {
      const message = error?.message || 'Google sign-in failed. Please try again.';
      setError(message);
      Alert.alert('Google Sign-In Failed', message);
    } finally {
      setGoogleLoading(false);
    }
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
      // Don't navigate here - let useEffect handle redirect based on pending token
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
            <BrandLogo size={84} accessibilityLabel="App logo" style={styles.brandLogoBorder} />
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

            {timedOutWithoutAuth && (
              <View style={styles.errorBanner}>
                <AppText variant="body" style={styles.errorText}>
                  Auth is taking longer than expected. You can retry.
                </AppText>
                <AppButton
                  title="Retry auth"
                  variant="secondary"
                  onPress={retryInitialize}
                  style={styles.retryButton}
                />
              </View>
            )}

            {!isOnline && !user && (
              <View style={styles.errorBanner}>
                <AppText variant="body" style={styles.errorText}>
                  Requires connection. Please check your internet connection and try again.
                </AppText>
              </View>
            )}

            {loginMethod === 'google' ? (
              <View style={styles.section}>
                <AppButton
                  title="Sign In with Google"
                  onPress={handleGoogleSignIn}
                  leftIcon={
                    <GoogleMark
                      size={18}
                      color={resolvedColorScheme === 'dark' ? '#fff' : theme.colors.background}
                    />
                  }
                  loading={googleLoading}
                  disabled={!isOnline || googleLoading}
                />

                <Pressable
                  onPress={handleGoogleSignIn}
                  disabled={!isOnline || googleLoading}
                  style={[
                    styles.googleSignUpLink,
                    !isOnline && styles.googleSignUpLinkDisabled,
                  ]}
                >
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
                  disabled={!isOnline}
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

