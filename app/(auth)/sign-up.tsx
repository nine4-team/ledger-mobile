import { useState } from 'react';
import { View, StyleSheet, TextInput, Alert, KeyboardAvoidingView, Platform } from 'react-native';
import { useRouter } from 'expo-router';
import { Screen } from '../../src/components/Screen';
import { AppText } from '../../src/components/AppText';
import { AppButton } from '../../src/components/AppButton';
import { useAuthStore } from '../../src/auth/authStore';
import { useTheme, useUIKitTheme } from '../../src/theme/ThemeProvider';
import { getCardStyle, getTextInputStyle } from '../../src/ui';

export default function SignUpScreen() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const router = useRouter();
  const { signUp } = useAuthStore();
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  const styles = StyleSheet.create({
    container: {
      flex: 1,
      justifyContent: 'center',
    },
    card: {
      width: '100%',
      maxWidth: 400,
      alignSelf: 'center',
      ...getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.lg }),
    },
    title: {
      marginBottom: theme.spacing.xl,
      textAlign: 'center',
    },
    input: {
      ...getTextInputStyle(uiKitTheme, { radius: 8, padding: theme.spacing.md, fontSize: 16 }),
      marginBottom: theme.spacing.md,
    },
    button: {
      marginTop: theme.spacing.sm,
    },
  });

  const handleSignUp = async () => {
    if (!email || !password) {
      Alert.alert('Error', 'Please enter email and password');
      return;
    }

    if (password !== confirmPassword) {
      Alert.alert('Error', 'Passwords do not match');
      return;
    }

    if (password.length < 6) {
      Alert.alert('Error', 'Password must be at least 6 characters');
      return;
    }

    setLoading(true);
    try {
      await signUp(email, password);
      router.replace('/(tabs)');
    } catch (error: any) {
      Alert.alert('Sign Up Failed', error.message || 'An error occurred');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Screen>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={styles.container}
      >
        <View style={styles.card}>
          <AppText variant="h1" style={styles.title}>
            Sign Up
          </AppText>

          <TextInput
            style={styles.input}
            placeholder="Email"
            placeholderTextColor={uiKitTheme.input.placeholder}
            value={email}
            onChangeText={setEmail}
            autoCapitalize="none"
            keyboardType="email-address"
            autoComplete="email"
          />

          <TextInput
            style={styles.input}
            placeholder="Password"
            placeholderTextColor={uiKitTheme.input.placeholder}
            value={password}
            onChangeText={setPassword}
            secureTextEntry
            autoCapitalize="none"
            autoComplete="password"
          />

          <TextInput
            style={styles.input}
            placeholder="Confirm Password"
            placeholderTextColor={uiKitTheme.input.placeholder}
            value={confirmPassword}
            onChangeText={setConfirmPassword}
            secureTextEntry
            autoCapitalize="none"
            autoComplete="password"
          />

          <AppButton title="Sign Up" onPress={handleSignUp} loading={loading} style={styles.button} />

          <AppButton
            title="Back to Sign In"
            variant="secondary"
            onPress={() => router.back()}
            style={styles.button}
          />
        </View>
      </KeyboardAvoidingView>
    </Screen>
  );
}
