import { create } from 'zustand';
import Purchases, { CustomerInfo, PurchasesOffering } from 'react-native-purchases';
import { Platform } from 'react-native';
import { appConfig } from '../config/appConfig';

interface BillingState {
  isPro: boolean;
  customerInfo: CustomerInfo | null;
  offerings: PurchasesOffering | null;
  isInitialized: boolean;
  setCustomerInfo: (info: CustomerInfo | null) => void;
  setOfferings: (offerings: PurchasesOffering | null) => void;
  setInitialized: (initialized: boolean) => void;
  initialize: () => Promise<void>;
  restorePurchases: () => Promise<void>;
  purchasePackage: (packageToPurchase: any) => Promise<void>;
}

export const useBillingStore = create<BillingState>((set, get) => ({
  isPro: false,
  customerInfo: null,
  offerings: null,
  isInitialized: false,
  setCustomerInfo: (info) => {
    const isPro = info?.entitlements.active[appConfig.revenueCatEntitlementId] !== undefined;
    set({ customerInfo: info, isPro });
  },
  setOfferings: (offerings) => set({ offerings }),
  setInitialized: (initialized) => set({ isInitialized: initialized }),
  initialize: async () => {
    const apiKey = process.env.EXPO_PUBLIC_REVENUECAT_API_KEY;
    if (!apiKey) {
      console.warn('RevenueCat API key not configured');
      set({ isInitialized: true });
      return;
    }

    try {
      if (Platform.OS === 'web') {
        console.warn('RevenueCat is not supported on web');
        set({ isInitialized: true });
        return;
      }

      if (Platform.OS === 'ios') {
        await Purchases.configure({ apiKey });
      } else if (Platform.OS === 'android') {
        await Purchases.configure({ apiKey });
      }

      const customerInfo = await Purchases.getCustomerInfo();
      get().setCustomerInfo(customerInfo);

      const offerings = await Purchases.getOfferings();
      set({ offerings: offerings.current });

      set({ isInitialized: true });
    } catch (error) {
      console.error('Failed to initialize RevenueCat:', error);
      set({ isInitialized: true });
    }
  },
  restorePurchases: async () => {
    try {
      const customerInfo = await Purchases.restorePurchases();
      get().setCustomerInfo(customerInfo);
    } catch (error) {
      console.error('Failed to restore purchases:', error);
      throw error;
    }
  },
  purchasePackage: async (packageToPurchase) => {
    try {
      const { customerInfo } = await Purchases.purchasePackage(packageToPurchase);
      get().setCustomerInfo(customerInfo);
    } catch (error) {
      console.error('Failed to purchase package:', error);
      throw error;
    }
  },
}));

// Hook for convenience
export const usePro = () => {
  const isPro = useBillingStore((state) => state.isPro);
  return isPro;
};
