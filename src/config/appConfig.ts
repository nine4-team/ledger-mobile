/**
 * App configuration - customize per app
 */
export interface QuotaConfig {
  freeLimit: number;
  collectionPath: string; // e.g., "users/{uid}/objects"
  displayName: string; // e.g., "memories", "projects"
}

export interface AppConfig {
  appName: string;
  quotas: Record<string, QuotaConfig>;
  revenueCatEntitlementId: string; // e.g., "pro"
  dataModeDefault: 'online' | 'offline';
  offlineReady: boolean;
  listenerScope: 'project' | 'account';
}

export const appConfig: AppConfig = {
  appName: 'ExpoFirebaseSkeleton',
  quotas: {
    // Example quota: users can create up to 10 "objects" for free
    object: {
      freeLimit: 10,
      collectionPath: 'users/{uid}/objects',
      displayName: 'objects',
    },
  },
  revenueCatEntitlementId: 'pro',
  dataModeDefault: 'online',
  offlineReady: true,
  listenerScope: 'project',
};
