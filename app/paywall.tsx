import { useState, useEffect } from 'react';
import { View, StyleSheet, Alert, ScrollView } from 'react-native';
import { useRouter } from 'expo-router';
import { Screen } from '../src/components/Screen';
import { AppText } from '../src/components/AppText';
import { AppButton } from '../src/components/AppButton';
import { useBillingStore } from '../src/billing/billingStore';
import { useTheme } from '../src/theme/ThemeProvider';

export default function PaywallScreen() {
  const router = useRouter();
  const { offerings, purchasePackage, isPro } = useBillingStore();
  const [loading, setLoading] = useState(false);
  const theme = useTheme();
  const styles = StyleSheet.create({
    container: {
      flexGrow: 1,
      paddingTop: theme.spacing.xl,
    },
    title: {
      marginBottom: theme.spacing.xl,
      textAlign: 'center',
    },
    features: {
      marginBottom: theme.spacing.xl,
    },
    feature: {
      marginBottom: theme.spacing.sm,
    },
    packageInfo: {
      backgroundColor: theme.card.backgroundColor,
      padding: theme.spacing.lg,
      borderRadius: 8,
      marginBottom: theme.spacing.xl,
      alignItems: 'center',
    },
    packageTitle: {
      marginBottom: theme.spacing.sm,
    },
    packagePrice: {
      fontSize: 24,
      fontWeight: 'bold',
      color: theme.colors.primary,
      marginBottom: theme.spacing.xs,
    },
    packageDescription: {
      textAlign: 'center',
      marginTop: theme.spacing.xs,
    },
    noPackages: {
      textAlign: 'center',
      marginBottom: theme.spacing.xl,
      color: theme.colors.textSecondary,
    },
    button: {
      marginTop: theme.spacing.md,
    },
  });

  useEffect(() => {
    if (isPro) {
      router.back();
    }
  }, [isPro]);

  const handlePurchase = async (packageToPurchase: any) => {
    if (!packageToPurchase) {
      Alert.alert('Error', 'No package available');
      return;
    }

    setLoading(true);
    try {
      await purchasePackage(packageToPurchase);
      Alert.alert('Success', 'Purchase completed!', [
        { text: 'OK', onPress: () => router.back() },
      ]);
    } catch (error: any) {
      if (error.userCancelled) {
        // User cancelled, don't show error
        return;
      }
      Alert.alert('Purchase Failed', error.message || 'An error occurred');
    } finally {
      setLoading(false);
    }
  };

  const availablePackage = offerings?.availablePackages?.[0];

  return (
    <Screen>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={styles.container}>
        <AppText variant="h1" style={styles.title}>
          Upgrade to Pro
        </AppText>

        <View style={styles.features}>
          <AppText variant="body" style={styles.feature}>
            • Unlimited quota
          </AppText>
          <AppText variant="body" style={styles.feature}>
            • All premium features
          </AppText>
          <AppText variant="body" style={styles.feature}>
            • Priority support
          </AppText>
        </View>

        {availablePackage ? (
          <View style={styles.packageInfo}>
            <AppText variant="h2" style={styles.packageTitle}>
              {availablePackage.product.title}
            </AppText>
            <AppText variant="body" style={styles.packagePrice}>
              {availablePackage.product.priceString}
            </AppText>
            <AppText variant="caption" style={styles.packageDescription}>
              {availablePackage.product.description}
            </AppText>
          </View>
        ) : (
          <AppText variant="caption" style={styles.noPackages}>
            No packages available. Make sure RevenueCat is configured correctly.
          </AppText>
        )}

        <AppButton
          title={availablePackage ? 'Purchase' : 'No Packages Available'}
          onPress={() => availablePackage && handlePurchase(availablePackage)}
          loading={loading}
          disabled={!availablePackage}
          style={styles.button}
        />

        <AppButton
          title="Restore Purchases"
          variant="secondary"
          onPress={async () => {
            try {
              await useBillingStore.getState().restorePurchases();
              Alert.alert('Success', 'Purchases restored');
            } catch (error: any) {
              Alert.alert('Error', error.message || 'Failed to restore purchases');
            }
          }}
          style={styles.button}
        />

        <AppButton
          title="Cancel"
          variant="secondary"
          onPress={() => router.back()}
          style={styles.button}
        />
      </ScrollView>
    </Screen>
  );
}
