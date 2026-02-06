import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { View, StyleSheet, Alert, RefreshControl, TextInput, Pressable, Image } from 'react-native';
import { useRouter } from 'expo-router';
import * as Linking from 'expo-linking';
import * as Clipboard from 'expo-clipboard';
import * as ImagePicker from 'expo-image-picker';
import * as FileSystem from 'expo-file-system';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { Screen, useScreenRefresh } from '../../src/components/Screen';
import { AppText } from '../../src/components/AppText';
import { AppButton } from '../../src/components/AppButton';
import { InfoCard } from '../../src/components/InfoCard';
import { AppScrollView } from '../../src/components/AppScrollView';
import { SegmentedControl } from '../../src/components/SegmentedControl';
import { MultiSelectPicker } from '../../src/components/MultiSelectPicker';
import { ScreenTabItem, ScreenTabs, useScreenTabs } from '../../src/components/ScreenTabs';
import { DraggableCardList } from '../../src/components/DraggableCardList';
import { DraggableCard } from '../../src/components/DraggableCard';
import type { TemplateToggleListItem } from '../../src/components/TemplateToggleListCard';
import { TemplateToggleListCard } from '../../src/components/TemplateToggleListCard';
import { BottomSheet } from '../../src/components/BottomSheet';
import { FormField } from '../../src/components/FormField';
import { FormBottomSheet } from '../../src/components/FormBottomSheet';
import { MultiStepFormBottomSheet } from '../../src/components/MultiStepFormBottomSheet';
import { useAuthStore } from '../../src/auth/authStore';
import { useAccountContextStore } from '../../src/auth/accountContextStore';
import { usePro } from '../../src/billing/billingStore';
import { isAuthBypassEnabled } from '../../src/auth/authConfig';
import { useAppearance, useTheme, useUIKitTheme } from '../../src/theme/ThemeProvider';
import { useNetworkStatus } from '../../src/hooks/useNetworkStatus';
import {
  getCardStyle,
  getTextColorStyle,
  getTextAccentStyle,
  getTextInputStyle,
  getTextSecondaryStyle,
  layout,
  surface,
  textEmphasis,
} from '../../src/ui';
import {
  subscribeToBudgetCategories,
  createBudgetCategory,
  deleteBudgetCategory,
  updateBudgetCategory,
  setBudgetCategoryOrder,
} from '../../src/data/budgetCategoriesService';
import {
  subscribeToSpaceTemplates,
  createSpaceTemplate,
  setSpaceTemplateArchived,
  setSpaceTemplateOrder,
  updateSpaceTemplate,
} from '../../src/data/spaceTemplatesService';
import { replaceVendorSlots, subscribeToVendorDefaults } from '../../src/data/vendorDefaultsService';
import { subscribeToAccountMember, subscribeToAccountMembers } from '../../src/data/accountMembersService';
import { createInvite, fetchPendingInvites, subscribeToInvites } from '../../src/data/invitesService';
import { saveBusinessProfile, subscribeToBusinessProfile, uploadBusinessLogo } from '../../src/data/businessProfileService';
import { createAccountWithOwner } from '../../src/data/accountsService';
import { resolveAttachmentUri } from '../../src/offline/media';
import { subscribeToTrackedRequests, untrackRequestDocPath } from '../../src/sync/requestDocTracker';
import { createRequestDoc, generateRequestOpId, parseRequestDocPath } from '../../src/data/requestDocs';
import { triggerManualSync } from '../../src/sync/syncActions';
import { auth, db, isFirebaseConfigured } from '../../src/firebase/firebase';

const PRIMARY_TABS: ScreenTabItem[] = [
  { key: 'general', label: 'General', accessibilityLabel: 'General tab' },
  { key: 'presets', label: 'Presets', accessibilityLabel: 'Presets tab' },
  { key: 'troubleshooting', label: 'Troubleshooting', accessibilityLabel: 'Troubleshooting tab' },
  { key: 'users', label: 'Users', accessibilityLabel: 'Users tab' },
  { key: 'account', label: 'Account', accessibilityLabel: 'Account tab' },
];

const PRESET_TABS: ScreenTabItem[] = [
  { key: 'spaces', label: 'Spaces', accessibilityLabel: 'Spaces presets tab' },
  { key: 'vendors', label: 'Vendors', accessibilityLabel: 'Vendors presets tab' },
  { key: 'budget', label: 'Budget', accessibilityLabel: 'Budget presets tab' },
];

type SettingsContentProps = {
  selectedPresetTabKey: string;
  memberRole: 'owner' | 'admin' | 'user' | null;
};

function SettingsContent({ selectedPresetTabKey, memberRole }: SettingsContentProps) {
  const router = useRouter();
  const { user } = useAuthStore();
  const { accountId } = useAccountContextStore();
  const isPro = usePro();
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const textPrimaryStyle = useMemo(() => getTextColorStyle(theme.colors.text), [theme]);
  const { appearanceMode, setAppearanceMode } = useAppearance();
  const screenTabs = useScreenTabs();
  const screenRefresh = useScreenRefresh();
  const { isOnline } = useNetworkStatus();
  const primaryTabKey = screenTabs?.selectedKey ?? 'general';
  const refreshControl = screenRefresh ? (
    <RefreshControl refreshing={screenRefresh.refreshing} onRefresh={screenRefresh.onRefresh} />
  ) : undefined;
  const categoryTypeHelper = {
    standard: 'For general expenses and services like fuel, movers, and handyman invoices.',
    general: 'For general expenses and services like fuel, movers, and handyman invoices.',
    itemized: 'For categories where physical items get purchased, enabling itemization and tax tracking.',
    fee: 'For service fee categories, so you can track how much you have received throughout the project.',
  } as const;
  const [profileDraft, setProfileDraft] = useState<string>('');
  const [profileLogo, setProfileLogo] = useState<{ url?: string | null; kind?: 'image'; storagePath?: string | null } | null>(
    null
  );
  const [logoSelection, setLogoSelection] = useState<{
    uri: string;
    fileName?: string | null;
    contentType?: string | null;
    size?: number | null;
  } | null>(null);
  const [logoError, setLogoError] = useState<string>('');
  const [profileStatus, setProfileStatus] = useState<'idle' | 'saving' | 'success' | 'error'>('idle');
  const [profileError, setProfileError] = useState<string>('');

  const [userDisplayNameDraft, setUserDisplayNameDraft] = useState<string>('');
  const [userProfileStatus, setUserProfileStatus] = useState<'idle' | 'saving' | 'success' | 'error'>('idle');
  const [userProfileError, setUserProfileError] = useState<string>('');
  const [userProfileEditorVisible, setUserProfileEditorVisible] = useState(false);

  const [budgetCategories, setBudgetCategories] = useState<
    {
      id: string;
      name: string;
      isArchived?: boolean | null;
      order?: number | null;
      metadata?: {
        categoryType?: 'standard' | 'general' | 'itemized' | 'fee';
        excludeFromOverallBudget?: boolean;
      } | null;
    }[]
  >([]);
  const [editingCategoryId, setEditingCategoryId] = useState<string | null>(null);
  const [editingCategoryName, setEditingCategoryName] = useState('');
  const [editingCategoryType, setEditingCategoryType] = useState<'standard' | 'general' | 'itemized' | 'fee'>('standard');
  const [categoryStep, setCategoryStep] = useState<1 | 2>(1);
  const [categorySaveStatus, setCategorySaveStatus] = useState<'idle' | 'saving'>('idle');
  const [categorySaveError, setCategorySaveError] = useState<string>('');

  const [vendorSlots, setVendorSlots] = useState<{ id: string; value: string }[]>([]);
  const [vendorStatus, setVendorStatus] = useState<'idle' | 'saving' | 'error'>('idle');
  const [vendorError, setVendorError] = useState('');

  const [spaceTemplates, setSpaceTemplates] = useState<
    {
      id: string;
      name: string;
      notes?: string | null;
      checklists?: { id: string; name: string; items: { id: string; text: string; isChecked: boolean }[] }[] | null;
      isArchived?: boolean | null;
      order?: number | null;
    }[]
  >([]);
  const [showArchivedTemplates, setShowArchivedTemplates] = useState(false);
  const [editingTemplateId, setEditingTemplateId] = useState<string | null>(null);
  const [templateDraft, setTemplateDraft] = useState<{
    name: string;
    notes: string;
    checklists: { id: string; name: string; items: { id: string; text: string; isChecked: boolean }[] }[];
  }>({ name: '', notes: '', checklists: [] });

  const [inviteEmail, setInviteEmail] = useState('');
  const [inviteRole, setInviteRole] = useState<'admin' | 'user'>('user');
  const [inviteStatus, setInviteStatus] = useState<'idle' | 'saving' | 'error'>('idle');
  const [inviteError, setInviteError] = useState('');
  const [inviteCopiedToken, setInviteCopiedToken] = useState<string | null>(null);
  const [pendingInvites, setPendingInvites] = useState<
    { id: string; email: string; role: 'admin' | 'user'; token: string }[]
  >([]);
  const [members, setMembers] = useState<{ id: string; role: string; email?: string | null; name?: string | null }[]>(
    []
  );

  const [accountName, setAccountName] = useState('');
  const [accountFirstEmail, setAccountFirstEmail] = useState('');
  const [accountStatus, setAccountStatus] = useState<'idle' | 'saving' | 'error'>('idle');
  const [accountError, setAccountError] = useState('');
  const [createdAccountInvite, setCreatedAccountInvite] = useState<{ link: string; token: string } | null>(null);
  const [accounts, setAccounts] = useState<{ accountId: string; name?: string }[]>([]);
  const [expandedAccounts, setExpandedAccounts] = useState<Record<string, boolean>>({});
  const [accountInvites, setAccountInvites] = useState<
    Record<string, { id: string; email: string; role: 'admin' | 'user'; token: string }[]>
  >({});

  const [exportStatus, setExportStatus] = useState<'idle' | 'saving' | 'error'>('idle');
  const [exportError, setExportError] = useState('');
  const [exportTimestamp, setExportTimestamp] = useState<string | null>(null);

  const [syncIssues, setSyncIssues] = useState<
    { path: string; status?: string; errorMessage?: string; type?: string; payload?: Record<string, unknown> }[]
  >([]);
  const [selectedIssuePaths, setSelectedIssuePaths] = useState<Record<string, boolean>>({});
  const [syncActionStatus, setSyncActionStatus] = useState<'idle' | 'working' | 'error'>('idle');
  const [syncActionError, setSyncActionError] = useState('');
  const [isDragging, setIsDragging] = useState(false);

  const isAdmin = memberRole === 'owner' || memberRole === 'admin';
  const isOwner = memberRole === 'owner';
  const maxUsers = isPro ? Number.POSITIVE_INFINITY : 1;
  const userDisplayNameInitial = user?.displayName ?? '';
  const isUserProfileDirty = userDisplayNameDraft.trim() !== userDisplayNameInitial.trim();

  const openUserProfileEditor = useCallback(() => {
    if (!user) return;
    setUserProfileError('');
    setUserProfileStatus('idle');
    setUserDisplayNameDraft(userDisplayNameInitial);
    setUserProfileEditorVisible(true);
  }, [user, userDisplayNameInitial]);

  const closeUserProfileEditor = useCallback(() => {
    setUserProfileEditorVisible(false);
  }, []);

  const handleSaveUserProfile = useCallback(async () => {
    if (!user) return;
    if (!isOnline) {
      setUserProfileStatus('error');
      setUserProfileError('Profile updates require an internet connection.');
      return;
    }
    const trimmed = userDisplayNameDraft.trim();
    if (!trimmed) {
      setUserProfileStatus('error');
      setUserProfileError('Full name is required.');
      return;
    }
    if (!isUserProfileDirty) {
      closeUserProfileEditor();
      return;
    }

    setUserProfileStatus('saving');
    setUserProfileError('');
    try {
      await user.updateProfile({ displayName: trimmed });
      await auth?.currentUser?.reload();
      // Keep the app state in sync even if auth listeners don’t fire.
      useAuthStore.getState().setUser(auth?.currentUser ?? user);
      setUserProfileStatus('idle');
      closeUserProfileEditor();
    } catch (error: unknown) {
      setUserProfileStatus('error');
      const message = error instanceof Error ? error.message : 'Failed to save user profile.';
      setUserProfileError(message);
    }
  }, [closeUserProfileEditor, isOnline, isUserProfileDirty, user, userDisplayNameDraft]);

  const sortedBudgetCategories = useMemo(() => {
    const byOrder = [...budgetCategories].sort((a, b) => {
      const aOrder = a.order ?? Number.MAX_SAFE_INTEGER;
      const bOrder = b.order ?? Number.MAX_SAFE_INTEGER;
      if (aOrder !== bOrder) return aOrder - bOrder;
      return a.name.localeCompare(b.name);
    });
    return byOrder;
  }, [budgetCategories]);

  const sortedSpaceTemplates = useMemo(() => {
    return [...spaceTemplates].sort((a, b) => {
      const aOrder = a.order ?? Number.MAX_SAFE_INTEGER;
      const bOrder = b.order ?? Number.MAX_SAFE_INTEGER;
      if (aOrder !== bOrder) return aOrder - bOrder;
      return a.name.localeCompare(b.name);
    });
  }, [spaceTemplates]);

  const logoPreviewUri = useMemo(() => {
    if (logoSelection?.uri) return logoSelection.uri;
    if (!profileLogo?.url) return null;
    if (profileLogo.url.startsWith('offline://')) {
      return resolveAttachmentUri({ url: profileLogo.url, kind: 'image' }) ?? profileLogo.url;
    }
    return profileLogo.url;
  }, [logoSelection, profileLogo]);

  useEffect(() => {
    if (!accountId) {
      setProfileDraft('');
      setProfileLogo(null);
      return;
    }
    return subscribeToBusinessProfile(accountId, (profile) => {
      const name = profile?.businessName ?? '';
      setProfileDraft((prev) => (prev ? prev : name));
      if (!logoSelection) {
        setProfileLogo(profile?.logo ?? null);
      }
    });
  }, [accountId, logoSelection]);

  useEffect(() => {
    if (!accountId) {
      setBudgetCategories([]);
      return;
    }
    return subscribeToBudgetCategories(accountId, (categories) => {
      setBudgetCategories(categories);
    });
  }, [accountId]);

  useEffect(() => {
    if (!accountId) {
      setVendorSlots([]);
      return;
    }
    return subscribeToVendorDefaults(accountId, (vendors) => {
      setVendorSlots(vendors.map((value, index) => ({ id: `vendor_${index}`, value })));
    });
  }, [accountId]);

  useEffect(() => {
    if (!accountId) {
      setSpaceTemplates([]);
      return;
    }
    return subscribeToSpaceTemplates(accountId, (templates) => {
      setSpaceTemplates(
        templates.map((template) => ({
          id: template.id,
          name: template.name,
          notes: template.notes ?? null,
          checklists: template.checklists ?? null,
          isArchived: template.isArchived ?? false,
          order: template.order ?? null,
        }))
      );
    });
  }, [accountId]);

  useEffect(() => {
    if (!accountId || !isAdmin) {
      setPendingInvites([]);
      setMembers([]);
      return;
    }
    const unsubInvites = subscribeToInvites(accountId, (invites) => {
      setPendingInvites(
        invites.map((invite) => ({ id: invite.id, email: invite.email, role: invite.role, token: invite.token }))
      );
    });
    const unsubMembers = subscribeToAccountMembers(accountId, (nextMembers) => {
      setMembers(nextMembers);
    });
    return () => {
      unsubInvites();
      unsubMembers();
    };
  }, [accountId, isAdmin]);

  useEffect(() => {
    return subscribeToTrackedRequests((requests) => {
      setSyncIssues(
        requests.map((request) => ({
          path: request.path,
          status: request.status,
          errorMessage: request.errorMessage,
          type: request.doc?.type,
          payload: request.doc?.payload as Record<string, unknown> | undefined,
        }))
      );
    });
  }, []);

  useEffect(() => {
    if (primaryTabKey !== 'account') {
      return;
    }
    let isActive = true;
    const fetchAccounts = async () => {
      try {
        const list = await useAccountContextStore.getState().listAccountsForCurrentUser();
        if (isActive) {
          setAccounts(list);
        }
      } catch {
        if (isActive) {
          setAccounts([]);
        }
      }
    };
    fetchAccounts();
    return () => {
      isActive = false;
    };
  }, [primaryTabKey]);

  const handlePickLogo = async () => {
    setLogoError('');
    const permission = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (!permission.granted) {
      setLogoError('Please allow photo access to pick a logo.');
      return;
    }
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      quality: 0.9,
    });
    if (result.canceled) {
      return;
    }
    const asset = result.assets[0];
    if (!asset) {
      setLogoError('Unable to read that image.');
      return;
    }
    const mimeType = asset.mimeType ?? '';
    const extension = asset.uri.split('.').pop()?.toLowerCase() ?? '';
    const isImage =
      mimeType.startsWith('image/') || ['png', 'jpg', 'jpeg', 'webp', 'heic', 'heif'].includes(extension);
    if (!isImage) {
      setLogoError('Logo must be an image file.');
      return;
    }
    const info = await FileSystem.getInfoAsync(asset.uri, { size: true });
    const size = asset.fileSize ?? (info.exists ? info.size ?? 0 : 0);
    if (size > 10 * 1024 * 1024) {
      setLogoError('Logo must be smaller than 10 MB.');
      return;
    }
    setLogoSelection({
      uri: asset.uri,
      fileName: asset.fileName ?? null,
      contentType: mimeType || null,
      size: size || null,
    });
  };

  const handleSaveProfile = async () => {
    if (!accountId) {
      setProfileStatus('error');
      setProfileError('No account selected.');
      return;
    }
    if (!isOnline) {
      setProfileStatus('error');
      setProfileError('Business profile updates require an internet connection.');
      return;
    }
    const trimmed = profileDraft.trim();
    if (!trimmed) {
      setProfileStatus('error');
      setProfileError('Business name is required.');
      return;
    }
    setProfileStatus('saving');
    setProfileError('');
    setLogoError('');
    try {
      let nextLogo = profileLogo ?? null;
      if (logoSelection) {
        const upload = await uploadBusinessLogo({
          accountId,
          localUri: logoSelection.uri,
          contentType: logoSelection.contentType,
          fileName: logoSelection.fileName,
        });
        nextLogo = { url: upload.url, kind: 'image', storagePath: upload.storagePath };
      }
      await saveBusinessProfile(accountId, { businessName: trimmed, logo: nextLogo }, user?.uid ?? null);
      setProfileLogo(nextLogo);
      setLogoSelection(null);
      setProfileStatus('success');
      setTimeout(() => setProfileStatus('idle'), 3000);
    } catch (error: any) {
      setProfileStatus('error');
      setProfileError(error?.message || 'Failed to save business profile.');
    }
  };

  const handleOpenCategoryEdit = (category: {
    id: string;
    name: string;
    metadata?: { categoryType?: 'standard' | 'general' | 'itemized' | 'fee'; excludeFromOverallBudget?: boolean } | null;
  }) => {
    setEditingCategoryId(category.id);
    setEditingCategoryName(category.name);
    setEditingCategoryType(category.metadata?.categoryType ?? 'standard');
    setCategoryStep(1);
    setCategorySaveError('');
  };

  const handleStartCategoryCreate = useCallback(() => {
    setEditingCategoryId('new');
    setEditingCategoryName('');
    setEditingCategoryType('standard');
    setCategoryStep(1);
    setCategorySaveError('');
  }, []);

  const handleCloseCategoryModal = useCallback(() => {
    setEditingCategoryId(null);
    setEditingCategoryName('');
    setCategoryStep(1);
    setCategorySaveError('');
    setCategorySaveStatus('idle');
  }, []);

  const handleNextStep = useCallback(() => {
    if (categoryStep === 1) {
      const trimmed = editingCategoryName.trim();
      if (!trimmed) {
        setCategorySaveError('Category name is required.');
        return;
      }
      setCategorySaveError('');
      setCategoryStep(2);
    }
  }, [categoryStep, editingCategoryName]);

  const handleBackStep = useCallback(() => {
    if (categoryStep === 2) {
      setCategorySaveError('');
      setCategoryStep(1);
    }
  }, [categoryStep]);

  const handleSaveCategoryDetails = async () => {
    if (!accountId || !editingCategoryId) return;
    if (!isOnline) {
      setCategorySaveError('Category changes require an internet connection.');
      return;
    }
    const existingCategory =
      editingCategoryId === 'new'
        ? null
        : budgetCategories.find((category) => category.id === editingCategoryId);
    const existingExclude = existingCategory?.metadata?.excludeFromOverallBudget;
    const trimmed = editingCategoryName.trim();
    if (!trimmed) {
      setCategorySaveError('Category name is required.');
      return;
    }
    setCategorySaveStatus('saving');
    setCategorySaveError('');
    const selectedCategoryType = editingCategoryType === 'standard' ? undefined : editingCategoryType;

    try {
      if (editingCategoryId === 'new') {
        // Firestore writes can take an unbounded amount of time to resolve (especially on flaky
        // connections) even though the category shows up immediately via local persistence +
        // subscriptions. To avoid a "frozen" UX, we only wait briefly before closing the sheet.
        const QUICK_WAIT_MS = 1200;

        const savePromise = createBudgetCategory(accountId, trimmed, {
          metadata: selectedCategoryType ? { categoryType: selectedCategoryType } : undefined,
        });

        const finishedQuickly = await Promise.race([
          savePromise.then(() => true),
          new Promise<boolean>((resolve) => setTimeout(() => resolve(false), QUICK_WAIT_MS)),
        ]);

        // If it didn't finish quickly, close anyway and let it continue in the background.
        // If it eventually fails, show an alert (the category may or may not have been created).
        if (!finishedQuickly) {
          savePromise.catch((error: any) => {
            Alert.alert('Error', error?.message || 'Failed to save category.');
          });
        }

        handleCloseCategoryModal();
        return;
      }

      await updateBudgetCategory(accountId, editingCategoryId, {
        name: trimmed,
        slug: trimmed.toLowerCase().replace(/\s+/g, '-'),
        metadata: {
          categoryType: editingCategoryType,
          ...(typeof existingExclude === 'boolean' ? { excludeFromOverallBudget: existingExclude } : {}),
        },
      });

      handleCloseCategoryModal();
    } catch (error: any) {
      setCategorySaveError(error?.message || 'Failed to save category.');
      setCategorySaveStatus('idle');
    }
  };

  const handleDeleteCategory = (categoryId: string, categoryName?: string) => {
    if (!accountId) return;
    if (!isOnline) {
      Alert.alert('Offline', 'Category changes require an internet connection.');
      return;
    }
    const name = categoryName?.trim();
    const message = name
      ? `This will permanently delete "${name}".`
      : 'This will permanently delete this category.';
    Alert.alert('Delete category', message, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: async () => {
          try {
            await deleteBudgetCategory(accountId, categoryId);
          } catch (error: any) {
            Alert.alert('Error', error?.message || 'Failed to delete category.');
          }
        },
      },
    ]);
  };

  const handleReorderBudgetCategories = async (nextOrder: typeof budgetCategories) => {
    if (!accountId) return;
    if (!isOnline) {
      Alert.alert('Offline', 'Reordering categories requires an internet connection.');
      return;
    }
    const activeIds = nextOrder.map((category) => category.id);
    try {
      await setBudgetCategoryOrder(accountId, activeIds);
    } catch (error: any) {
      Alert.alert('Error', error?.message || 'Failed to reorder categories.');
    }
  };

  const handleSaveVendorSlot = async (index: number) => {
    if (!accountId) return;
    if (!isOnline) {
      setVendorStatus('error');
      setVendorError('Vendor updates require an internet connection.');
      return;
    }
    setVendorStatus('saving');
    setVendorError('');
    try {
      const next = vendorSlots.map((slot) => slot.value);
      await replaceVendorSlots(accountId, next);
      setVendorStatus('idle');
    } catch (error: any) {
      setVendorStatus('error');
      setVendorError(error?.message || 'Failed to save vendors.');
    }
  };

  const handleClearVendorSlot = async (index: number) => {
    const next = [...vendorSlots];
    if (next[index]) {
      next[index] = { ...next[index], value: '' };
    }
    setVendorSlots(next);
    await handleSaveVendorSlot(index);
  };

  const handleReorderVendors = async (next: { id: string; value: string }[]) => {
    if (!accountId) return;
    if (!isOnline) {
      setVendorStatus('error');
      setVendorError('Reordering vendors requires an internet connection.');
      return;
    }
    setVendorStatus('saving');
    setVendorError('');
    try {
      await replaceVendorSlots(
        accountId,
        next.map((slot) => slot.value)
      );
      setVendorSlots(next);
      setVendorStatus('idle');
    } catch (error: any) {
      setVendorStatus('error');
      setVendorError(error?.message || 'Failed to reorder vendors.');
    }
  };

  const handleStartTemplateCreate = () => {
    setEditingTemplateId('new');
    setTemplateDraft({ name: '', notes: '', checklists: [] });
  };

  const handleStartTemplateEdit = (template: {
    id: string;
    name: string;
    notes?: string | null;
    checklists?: { id: string; name: string; items: { id: string; text: string; isChecked: boolean }[] }[] | null;
  }) => {
    setEditingTemplateId(template.id);
    setTemplateDraft({
      name: template.name,
      notes: template.notes ?? '',
      checklists: template.checklists ? [...template.checklists] : [],
    });
  };

  const handleSaveTemplate = async () => {
    if (!accountId) return;
    if (!isOnline) {
      Alert.alert('Offline', 'Template changes require an internet connection.');
      return;
    }
    const trimmed = templateDraft.name.trim();
    if (!trimmed) {
      Alert.alert('Error', 'Template name is required.');
      return;
    }
    try {
      if (editingTemplateId === 'new') {
        await createSpaceTemplate(accountId, {
          name: trimmed,
          notes: templateDraft.notes.trim() || null,
          checklists: templateDraft.checklists,
        });
      } else if (editingTemplateId) {
        await updateSpaceTemplate(accountId, editingTemplateId, {
          name: trimmed,
          notes: templateDraft.notes.trim() || null,
          checklists: templateDraft.checklists,
        });
      }
      setEditingTemplateId(null);
      setTemplateDraft({ name: '', notes: '', checklists: [] });
    } catch (error: any) {
      Alert.alert('Error', error?.message || 'Failed to save template.');
    }
  };

  const handleArchiveTemplate = async (templateId: string, shouldArchive: boolean) => {
    if (!accountId) return;
    if (!isOnline) {
      Alert.alert('Offline', 'Template changes require an internet connection.');
      return;
    }
    try {
      await setSpaceTemplateArchived(accountId, templateId, shouldArchive);
    } catch (error: any) {
      Alert.alert('Error', error?.message || 'Failed to update template.');
    }
  };

  const handleReorderTemplates = async (nextOrder: typeof spaceTemplates) => {
    if (!accountId) return;
    if (!isOnline) {
      Alert.alert('Offline', 'Reordering templates requires an internet connection.');
      return;
    }
    const activeIds = nextOrder.filter((template) => !template.isArchived).map((template) => template.id);
    try {
      await setSpaceTemplateOrder(accountId, activeIds);
    } catch (error: any) {
      Alert.alert('Error', error?.message || 'Failed to reorder templates.');
    }
  };

  const handleAddChecklist = () => {
    setTemplateDraft((prev) => ({
      ...prev,
      checklists: [
        ...prev.checklists,
        { id: `checklist_${Date.now()}`, name: '', items: [] },
      ],
    }));
  };

  const handleUpdateChecklistName = (index: number, name: string) => {
    setTemplateDraft((prev) => {
      const next = [...prev.checklists];
      next[index] = { ...next[index], name };
      return { ...prev, checklists: next };
    });
  };

  const handleRemoveChecklist = (index: number) => {
    setTemplateDraft((prev) => {
      const next = [...prev.checklists];
      next.splice(index, 1);
      return { ...prev, checklists: next };
    });
  };

  const handleAddChecklistItem = (index: number) => {
    setTemplateDraft((prev) => {
      const next = [...prev.checklists];
      const checklist = next[index];
      if (!checklist) return prev;
      const items = [...checklist.items, { id: `item_${Date.now()}`, text: '', isChecked: false }];
      next[index] = { ...checklist, items };
      return { ...prev, checklists: next };
    });
  };

  const handleUpdateChecklistItem = (checklistIndex: number, itemIndex: number, text: string) => {
    setTemplateDraft((prev) => {
      const next = [...prev.checklists];
      const checklist = next[checklistIndex];
      if (!checklist) return prev;
      const items = [...checklist.items];
      items[itemIndex] = { ...items[itemIndex], text };
      next[checklistIndex] = { ...checklist, items };
      return { ...prev, checklists: next };
    });
  };

  const handleRemoveChecklistItem = (checklistIndex: number, itemIndex: number) => {
    setTemplateDraft((prev) => {
      const next = [...prev.checklists];
      const checklist = next[checklistIndex];
      if (!checklist) return prev;
      const items = [...checklist.items];
      items.splice(itemIndex, 1);
      next[checklistIndex] = { ...checklist, items };
      return { ...prev, checklists: next };
    });
  };

  const handleCreateInvite = async () => {
    if (!accountId) return;
    if (!isOnline) {
      setInviteStatus('error');
      setInviteError('Invites require an internet connection.');
      return;
    }
    if (!inviteEmail.trim()) {
      setInviteStatus('error');
      setInviteError('Email is required.');
      return;
    }
    if (members.length >= maxUsers) {
      setInviteStatus('error');
      setInviteError('This plan has reached its user limit.');
      return;
    }
    setInviteStatus('saving');
    setInviteError('');
    try {
      const invite = await createInvite({
        accountId,
        email: inviteEmail,
        role: inviteRole,
        createdByUid: user?.uid ?? null,
      });
      const inviteLink = Linking.createURL(`/invite/${invite.token}`);
      await Clipboard.setStringAsync(inviteLink);
      setInviteCopiedToken(invite.token);
      setTimeout(() => setInviteCopiedToken(null), 2000);
      setInviteEmail('');
      setInviteStatus('idle');
    } catch (error: any) {
      setInviteStatus('error');
      setInviteError(error?.message || 'Failed to create invite.');
    }
  };

  const handleCopyInviteLink = async (token: string) => {
    const link = Linking.createURL(`/invite/${token}`);
    await Clipboard.setStringAsync(link);
    setInviteCopiedToken(token);
    setTimeout(() => setInviteCopiedToken(null), 2000);
  };

  const handleCreateAccount = async () => {
    if (!user) {
      setAccountStatus('error');
      setAccountError('You must be signed in.');
      return;
    }
    if (!accountName.trim() || !accountFirstEmail.trim()) {
      setAccountStatus('error');
      setAccountError('Account name and first user email are required.');
      return;
    }
    if (!isOnline) {
      setAccountStatus('error');
      setAccountError('Account creation requires an internet connection.');
      return;
    }
    setAccountStatus('saving');
    setAccountError('');
    try {
      const account = await createAccountWithOwner({
        name: accountName.trim(),
        ownerUid: user.uid,
        ownerEmail: user.email ?? null,
        ownerName: user.displayName ?? null,
      });
      const invite = await createInvite({
        accountId: account.id,
        email: accountFirstEmail.trim().toLowerCase(),
        role: 'admin',
        createdByUid: user.uid,
      });
      const link = Linking.createURL(`/invite/${invite.token}`);
      setCreatedAccountInvite({ link, token: invite.token });
      setAccountName('');
      setAccountFirstEmail('');
      setAccountStatus('idle');
      const list = await useAccountContextStore.getState().listAccountsForCurrentUser();
      setAccounts(list);
    } catch (error: any) {
      setAccountStatus('error');
      setAccountError(error?.message || 'Failed to create account.');
    }
  };

  const handleToggleAccountExpand = async (accountIdValue: string) => {
    const next = !expandedAccounts[accountIdValue];
    setExpandedAccounts((prev) => ({ ...prev, [accountIdValue]: next }));
    if (next) {
      try {
        const invites = await fetchPendingInvites(accountIdValue, isOnline ? 'online' : 'offline');
        setAccountInvites((prev) => ({
          ...prev,
          [accountIdValue]: invites.map((invite) => ({
            id: invite.id,
            email: invite.email,
            role: invite.role,
            token: invite.token,
          })),
        }));
      } catch {
        setAccountInvites((prev) => ({ ...prev, [accountIdValue]: [] }));
      }
    }
  };

  const handleCopyAccountInviteLink = async (token: string) => {
    const link = Linking.createURL(`/invite/${token}`);
    await Clipboard.setStringAsync(link);
    setInviteCopiedToken(token);
    setTimeout(() => setInviteCopiedToken(null), 2000);
  };

  const handleExportOfflineData = async () => {
    if (!accountId) {
      setExportStatus('error');
      setExportError('No account selected.');
      return;
    }
    if (!isFirebaseConfigured || !db) {
      setExportStatus('error');
      setExportError('Firebase is not configured.');
      return;
    }
    const firestore = db;
    if (!FileSystem.documentDirectory) {
      setExportStatus('error');
      setExportError('Export location is unavailable.');
      return;
    }
    setExportStatus('saving');
    setExportError('');
    try {
      const getDoc = async (path: string) => {
        for (const source of ['cache', 'server'] as const) {
          try {
            const snap = await (firestore.doc(path) as any).get({ source });
            return snap.exists ? snap.data() : null;
          } catch {
            // try next
          }
        }
        const snap = await firestore.doc(path).get();
        return snap.exists ? snap.data() : null;
      };
      const getCollection = async (path: string) => {
        for (const source of ['cache', 'server'] as const) {
          try {
            const snap = await (firestore.collection(path) as any).get({ source });
            return snap.docs.map((doc: any) => ({ id: doc.id, ...(doc.data() as object) }));
          } catch {
            // try next
          }
        }
        const snap = await firestore.collection(path).get();
        return snap.docs.map((doc: any) => ({ id: doc.id, ...(doc.data() as object) }));
      };

      const exportedAt = new Date().toISOString();
      const payload = {
        accountId,
        exportedAt,
        warning: 'This export is a local cache snapshot and may be incomplete.',
        profile: await getDoc(`accounts/${accountId}/profile/default`),
        budgetCategories: await getCollection(`accounts/${accountId}/presets/default/budgetCategories`),
        vendorDefaults: await getDoc(`accounts/${accountId}/presets/default/vendors/default`),
        spaceTemplates: await getCollection(`accounts/${accountId}/presets/default/spaceTemplates`),
        members: await getCollection(`accounts/${accountId}/users`),
        invites: await getCollection(`accounts/${accountId}/invites`),
        trackedRequests: syncIssues,
      };

      const safeTimestamp = exportedAt.replace(/[:.]/g, '-');
      const fileName = `ledger-cache-${accountId}-${safeTimestamp}.json`;
      const fileUri = `${FileSystem.documentDirectory}${fileName}`;
      await FileSystem.writeAsStringAsync(fileUri, JSON.stringify(payload, null, 2));
      setExportTimestamp(exportedAt);
      setExportStatus('idle');
    } catch (error: any) {
      setExportStatus('error');
      setExportError(error?.message || 'Failed to export offline data.');
    }
  };

  const handleToggleIssueSelect = (path: string) => {
    setSelectedIssuePaths((prev) => ({ ...prev, [path]: !prev[path] }));
  };

  const handleSelectAllIssues = () => {
    if (syncIssues.length === 0) return;
    const next: Record<string, boolean> = {};
    syncIssues.forEach((issue) => {
      next[issue.path] = true;
    });
    setSelectedIssuePaths(next);
  };

  const handleClearSelectedIssues = () => {
    setSelectedIssuePaths({});
  };

  const handleRecreateSelectedIssues = async () => {
    const selected = syncIssues.filter((issue) => selectedIssuePaths[issue.path]);
    if (selected.length === 0) return;
    setSyncActionStatus('working');
    setSyncActionError('');
    try {
      for (const issue of selected) {
        if (!issue.type || !issue.payload) {
          continue;
        }
        const scope = parseRequestDocPath(issue.path);
        if (!scope) {
          continue;
        }
        await createRequestDoc(issue.type, issue.payload, scope, generateRequestOpId());
        untrackRequestDocPath(issue.path);
      }
      setSyncActionStatus('idle');
      setSelectedIssuePaths({});
    } catch (error: any) {
      setSyncActionStatus('error');
      setSyncActionError(error?.message || 'Failed to recreate issues.');
    }
  };

  const handleDiscardSelectedIssues = () => {
    const selected = syncIssues.filter((issue) => selectedIssuePaths[issue.path]);
    if (selected.length === 0) return;
    Alert.alert('Discard issues', 'Remove these issues from your queue?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Discard',
        style: 'destructive',
        onPress: () => {
          selected.forEach((issue) => {
            untrackRequestDocPath(issue.path);
          });
          setSelectedIssuePaths({});
        },
      },
    ]);
  };

  const handleRetrySync = async () => {
    setSyncActionStatus('working');
    setSyncActionError('');
    try {
      await triggerManualSync();
      setSyncActionStatus('idle');
    } catch (error: any) {
      setSyncActionStatus('error');
      setSyncActionError(error?.message || 'Failed to retry sync.');
    }
  };

  if (primaryTabKey === 'presets') {
    if (!isAdmin) {
      return (
        <AppScrollView style={styles.scroll} contentContainerStyle={styles.scrollContent} refreshControl={refreshControl}>
          <AppText variant="body">Presets are only configurable by account administrators.</AppText>
        </AppScrollView>
      );
    }

    if (selectedPresetTabKey === 'spaces') {
      const activeTemplates = sortedSpaceTemplates.filter((template) => !template.isArchived);
      const archivedTemplates = sortedSpaceTemplates.filter((template) => template.isArchived);
      return (
        <AppScrollView
          style={styles.scroll}
          contentContainerStyle={styles.scrollContent}
          refreshControl={refreshControl}
          scrollEnabled={!isDragging}
        >
          <View style={styles.section}>
            <View style={styles.sectionHeader}>
              <AppText
                variant="caption"
                style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
              >
                Templates
              </AppText>
              <AppButton title="Create Template" variant="secondary" onPress={handleStartTemplateCreate} />
            </View>
            <View style={[surface.overflowHidden, getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.md })]}>
              {activeTemplates.length === 0 ? (
                <AppText variant="body" style={getTextSecondaryStyle(uiKitTheme)}>
                  No templates yet.
                </AppText>
              ) : (
                <DraggableCardList
                  items={activeTemplates}
                  getItemId={(item) => item.id}
                  itemHeight={64}
                  onReorder={handleReorderTemplates}
                  onDragActiveChange={setIsDragging}
                  renderItem={({ item, dragHandleProps, isActive }) => (
                    <View style={styles.draggableRow}>
                      <DraggableCard
                        title={item.name}
                        dragHandleProps={dragHandleProps}
                        isActive={isActive}
                        right={
                          <View style={styles.rowActions}>
                            <Pressable
                              onPress={() => handleStartTemplateEdit(item)}
                              style={({ pressed }) => [styles.actionChip, pressed && styles.pressed]}
                            >
                              <AppText variant="caption" style={styles.actionText}>
                                Edit
                              </AppText>
                            </Pressable>
                            <Pressable
                              onPress={() => handleArchiveTemplate(item.id, true)}
                              style={({ pressed }) => [styles.actionChip, pressed && styles.pressed]}
                            >
                              <AppText variant="caption" style={styles.actionText}>
                                Archive
                              </AppText>
                            </Pressable>
                          </View>
                        }
                      />
                    </View>
                  )}
                />
              )}
            </View>
          </View>

          <View style={styles.section}>
            <Pressable
              onPress={() => setShowArchivedTemplates((prev) => !prev)}
              style={({ pressed }) => [styles.inlineToggle, pressed && styles.pressed]}
            >
              <MaterialIcons
                name={showArchivedTemplates ? 'check-box' : 'check-box-outline-blank'}
                size={20}
                color={theme.colors.textSecondary}
              />
              <AppText variant="body" style={styles.inlineToggleText}>
                Show Archived
              </AppText>
            </Pressable>
          </View>

          {showArchivedTemplates ? (
            <View style={styles.section}>
              <AppText
                variant="caption"
                style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
              >
                Archived Templates
              </AppText>
              <View style={[surface.overflowHidden, getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.md })]}>
                {archivedTemplates.length === 0 ? (
                  <AppText variant="body" style={getTextSecondaryStyle(uiKitTheme)}>
                    No archived templates.
                  </AppText>
                ) : (
                  archivedTemplates.map((template) => (
                    <View key={template.id} style={styles.listRow}>
                      <AppText variant="body">{template.name}</AppText>
                      <Pressable
                        onPress={() => handleArchiveTemplate(template.id, false)}
                        style={({ pressed }) => [styles.actionChip, pressed && styles.pressed]}
                      >
                        <AppText variant="caption" style={styles.actionText}>
                          Unarchive
                        </AppText>
                      </Pressable>
                    </View>
                  ))
                )}
              </View>
            </View>
          ) : null}

          {editingTemplateId ? (
            <View style={styles.section}>
              <AppText
                variant="caption"
                style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
              >
                {editingTemplateId === 'new' ? 'New Template' : 'Edit Template'}
              </AppText>
              <View style={[surface.overflowHidden, getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.lg })]}>
                <TextInput
                  placeholder="Template name"
                  value={templateDraft.name}
                  onChangeText={(value) => setTemplateDraft((prev) => ({ ...prev, name: value }))}
                  style={[styles.input, textPrimaryStyle]}
                  placeholderTextColor={theme.colors.textSecondary}
                />
                <TextInput
                  placeholder="Notes (optional)"
                  value={templateDraft.notes}
                  onChangeText={(value) => setTemplateDraft((prev) => ({ ...prev, notes: value }))}
                  style={[styles.input, textPrimaryStyle]}
                  placeholderTextColor={theme.colors.textSecondary}
                />

                {templateDraft.checklists.map((checklist, checklistIndex) => (
                  <View key={checklist.id} style={styles.nestedBlock}>
                    <View style={styles.rowBetween}>
                      <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                        Checklist
                      </AppText>
                      <Pressable
                        onPress={() => handleRemoveChecklist(checklistIndex)}
                        style={({ pressed }) => [styles.actionChip, pressed && styles.pressed]}
                      >
                        <AppText variant="caption" style={styles.actionText}>
                          Remove
                        </AppText>
                      </Pressable>
                    </View>
                    <TextInput
                      placeholder="Checklist name"
                      value={checklist.name}
                      onChangeText={(value) => handleUpdateChecklistName(checklistIndex, value)}
                      style={[styles.input, textPrimaryStyle]}
                      placeholderTextColor={theme.colors.textSecondary}
                    />
                    {checklist.items.map((item, itemIndex) => (
                      <View key={item.id} style={styles.nestedRow}>
                        <TextInput
                          placeholder="Item"
                          value={item.text}
                          onChangeText={(value) => handleUpdateChecklistItem(checklistIndex, itemIndex, value)}
                          style={[styles.input, styles.nestedInput, textPrimaryStyle]}
                          placeholderTextColor={theme.colors.textSecondary}
                        />
                        <Pressable
                          onPress={() => handleRemoveChecklistItem(checklistIndex, itemIndex)}
                          style={({ pressed }) => [styles.iconButton, pressed && styles.pressed]}
                        >
                          <MaterialIcons name="close" size={18} color={theme.colors.textSecondary} />
                        </Pressable>
                      </View>
                    ))}
                    <AppButton
                      title="Add Item"
                      variant="secondary"
                      onPress={() => handleAddChecklistItem(checklistIndex)}
                      style={styles.inlineButton}
                    />
                  </View>
                ))}

                <AppButton title="Add Checklist" variant="secondary" onPress={handleAddChecklist} />
                <View style={styles.inlineActions}>
                  <AppButton
                    title="Cancel"
                    variant="secondary"
                    onPress={() => setEditingTemplateId(null)}
                  />
                  <AppButton title="Save Template" onPress={handleSaveTemplate} />
                </View>
              </View>
            </View>
          ) : null}
        </AppScrollView>
      );
    }

    if (selectedPresetTabKey === 'vendors') {
      const vendorItems = vendorSlots;
      return (
        <AppScrollView
          style={styles.scroll}
          contentContainerStyle={styles.scrollContent}
          refreshControl={refreshControl}
          scrollEnabled={!isDragging}
        >
          {vendorError ? (
            <View style={styles.errorBanner}>
              <AppText variant="body" style={styles.errorText}>
                {vendorError}
              </AppText>
            </View>
          ) : null}
          <View style={[surface.overflowHidden, getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.md })]}>
            <DraggableCardList
              items={vendorItems}
              getItemId={(item) => item.id}
              itemHeight={140}
              onReorder={handleReorderVendors}
              onDragActiveChange={setIsDragging}
              renderItem={({ item, index, dragHandleProps, isActive }) => (
                <View style={styles.vendorCard}>
                  <DraggableCard
                    title={`Slot ${index + 1}`}
                    dragHandleProps={dragHandleProps}
                    isActive={isActive}
                  />
                  <TextInput
                    placeholder="Vendor name"
                    value={item.value}
                    onChangeText={(value) =>
                      setVendorSlots((prev) => {
                        const next = [...prev];
                        if (next[index]) {
                          next[index] = { ...next[index], value };
                        }
                        return next;
                      })
                    }
                    style={[styles.input, styles.vendorInput, textPrimaryStyle]}
                    placeholderTextColor={theme.colors.textSecondary}
                  />
                  <View style={styles.inlineActions}>
                    <AppButton
                      title={vendorStatus === 'saving' ? 'Saving…' : 'Save'}
                      onPress={() => handleSaveVendorSlot(index)}
                      disabled={vendorStatus === 'saving'}
                    />
                    <AppButton
                      title="Clear"
                      variant="secondary"
                      onPress={() => handleClearVendorSlot(index)}
                      disabled={vendorStatus === 'saving'}
                    />
                  </View>
                </View>
              )}
            />
          </View>
        </AppScrollView>
      );
    }

    const activeCategories = sortedBudgetCategories;
    const activeCategoryById: Record<
      string,
      {
        id: string;
        name: string;
        isArchived?: boolean | null;
        order?: number | null;
        metadata?: { categoryType?: 'standard' | 'general' | 'itemized' | 'fee'; excludeFromOverallBudget?: boolean } | null;
      }
    > = {};
    for (const c of activeCategories) activeCategoryById[c.id] = c;

    const categoryToggleItems: TemplateToggleListItem[] = activeCategories.map((category) => {
      const isIncluded = !category.metadata?.excludeFromOverallBudget;
      return {
        id: category.id,
        name: category.name,
        disabled: !isIncluded,
      };
    });

    return (
      <AppScrollView
        style={styles.scroll}
        contentContainerStyle={styles.scrollContent}
        refreshControl={refreshControl}
        scrollEnabled={!isDragging}
      >

        <View style={styles.section}>
          <AppText
            variant="caption"
            style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
          >
            Budget Categories
          </AppText>
          <TemplateToggleListCard
            title="Budget Categories"
            rightHeaderLabel="Include"
            items={categoryToggleItems}
            isItemDraggable={() => true}
            onDragActiveChange={setIsDragging}
            onPressCreate={handleStartCategoryCreate}
            createPlaceholderLabel="Create Category"
            onToggleDisabled={async (id, next) => {
              if (!accountId) return;
              if (!isOnline) {
                Alert.alert('Offline', 'Category changes require an internet connection.');
                return;
              }
              const category = activeCategoryById[id];
              if (!category) return;
              const categoryType = category.metadata?.categoryType ?? 'standard';
              try {
                await updateBudgetCategory(accountId, id, {
                  metadata: {
                    categoryType,
                    excludeFromOverallBudget: next,
                  },
                });
              } catch (error: any) {
                Alert.alert('Error', error?.message || 'Failed to update category.');
              }
            }}
            onReorderItems={async (nextItems) => {
              const nextOrder = nextItems
                .map((it) => activeCategoryById[it.id])
                .filter(Boolean) as typeof activeCategories;
              await handleReorderBudgetCategories(nextOrder);
            }}
            getInfoContent={(it) => {
              const category = activeCategoryById[it.id];
              const categoryType = category?.metadata?.categoryType ?? 'standard';
              const included = !category?.metadata?.excludeFromOverallBudget;
              const typeDescription = categoryTypeHelper[categoryType] ?? 'General categories show up in budgets and reports.';
              const parts = [
                `Type: ${categoryType}`,
                typeDescription,
                included ? 'Included in overall budget.' : 'Excluded from overall budget.',
              ].filter(Boolean);
              return {
                title: category?.name ?? 'Category',
                message: parts.join('\n\n'),
              };
            }}
            getMenuTitle={(it) => activeCategoryById[it.id]?.name ?? it.name ?? 'Options'}
            getMenuItems={(it) => {
              const category = activeCategoryById[it.id];
              if (!category) return [];
              return [
                {
                  key: 'edit',
                  label: 'Edit',
                  icon: 'edit',
                  onPress: () => handleOpenCategoryEdit(category),
                },
                {
                  key: 'delete',
                  label: 'Delete',
                  icon: 'delete',
                  onPress: () => handleDeleteCategory(category.id, category.name),
                },
              ];
            }}
          />
        </View>

        <MultiStepFormBottomSheet
          visible={editingCategoryId !== null}
          onRequestClose={handleCloseCategoryModal}
          title={editingCategoryId === 'new' ? 'New Budget Category' : 'Edit Budget Category'}
          currentStep={categoryStep}
          totalSteps={2}
          primaryAction={{
            title: categoryStep === 1 ? 'Next' : editingCategoryId === 'new' ? 'Create' : 'Save',
            onPress: categoryStep === 1 ? handleNextStep : handleSaveCategoryDetails,
            loading: categoryStep === 2 && categorySaveStatus === 'saving',
            disabled:
              categoryStep === 1
                ? categorySaveStatus === 'saving' || !editingCategoryName.trim()
                : categorySaveStatus === 'saving',
          }}
          secondaryAction={{
            title: categoryStep === 1 ? 'Cancel' : 'Back',
            onPress: categoryStep === 1 ? handleCloseCategoryModal : handleBackStep,
            disabled: categorySaveStatus === 'saving',
          }}
          error={categorySaveError && categoryStep === 2 ? categorySaveError : undefined}
        >
          {categoryStep === 1 ? (
            <FormField
              label="Category Name"
              value={editingCategoryName}
              onChangeText={(text) => {
                setEditingCategoryName(text);
                setCategorySaveError('');
              }}
              placeholder="Enter category name"
              errorText={categorySaveError && !editingCategoryName.trim() ? categorySaveError : undefined}
              inputProps={{
                autoFocus: true,
                returnKeyType: 'next',
                onSubmitEditing: handleNextStep,
              }}
            />
          ) : (
            <View>
              <AppText variant="caption" style={[styles.categoryTypeHelper, getTextSecondaryStyle(uiKitTheme)]}>
                Choose optional flags for this budget category to customize how it behaves in budgets and reports.
              </AppText>
              <MultiSelectPicker
                label="Category Type"
                value={editingCategoryType}
                onChange={(value) => setEditingCategoryType(value as 'standard' | 'general' | 'itemized' | 'fee')}
                options={[
                  {
                    value: 'standard',
                    label: 'General',
                    description: categoryTypeHelper.standard,
                  },
                  {
                    value: 'itemized',
                    label: 'Itemized',
                    description: categoryTypeHelper.itemized,
                  },
                  {
                    value: 'fee',
                    label: 'Fee',
                    description: categoryTypeHelper.fee,
                  },
                ]}
                accessibilityLabel="Category type"
              />
            </View>
          )}
        </MultiStepFormBottomSheet>
      </AppScrollView>
    );
  }

  if (primaryTabKey === 'troubleshooting') {
    const selectedCount = Object.values(selectedIssuePaths).filter(Boolean).length;
    return (
      <AppScrollView style={styles.scroll} contentContainerStyle={styles.scrollContent} refreshControl={refreshControl}>
        <View style={styles.section}>
          <AppText
            variant="caption"
            style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
          >
            Offline Export
          </AppText>
          <View style={[surface.overflowHidden, getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.lg })]}>
            <AppText variant="body" style={getTextSecondaryStyle(uiKitTheme)}>
              This downloads a local cache snapshot. It may be incomplete or out of date. Treat the file as sensitive.
            </AppText>
            {exportError ? (
              <View style={styles.errorBanner}>
                <AppText variant="body" style={styles.errorText}>
                  {exportError}
                </AppText>
              </View>
            ) : null}
            {exportTimestamp ? (
              <AppText variant="caption" style={[styles.helperText, getTextSecondaryStyle(uiKitTheme)]}>
                Last export: {new Date(exportTimestamp).toLocaleString()}
              </AppText>
            ) : null}
            <AppButton
              title={exportStatus === 'saving' ? 'Exporting…' : 'Export JSON'}
              onPress={handleExportOfflineData}
              disabled={exportStatus === 'saving'}
              style={styles.inlineButton}
            />
          </View>
        </View>

        <View style={styles.section}>
          <AppText
            variant="caption"
            style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
          >
            Sync Issues
          </AppText>
          <View style={[surface.overflowHidden, getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.lg })]}>
            {syncActionError ? (
              <View style={styles.errorBanner}>
                <AppText variant="body" style={styles.errorText}>
                  {syncActionError}
                </AppText>
              </View>
            ) : null}
            {syncIssues.length === 0 ? (
              <>
                <AppText variant="body" style={getTextSecondaryStyle(uiKitTheme)}>
                  All clear. No sync issues detected.
                </AppText>
                <AppButton
                  title={syncActionStatus === 'working' ? 'Retrying…' : 'Retry Sync'}
                  onPress={handleRetrySync}
                  disabled={syncActionStatus === 'working'}
                  style={styles.inlineButton}
                />
              </>
            ) : (
              <>
                <View style={styles.inlineActions}>
                  <AppButton title="Select All" variant="secondary" onPress={handleSelectAllIssues} />
                  <AppButton title="Clear" variant="secondary" onPress={handleClearSelectedIssues} />
                </View>
                <View style={styles.listBlock}>
                  {syncIssues.map((issue) => (
                    <Pressable
                      key={issue.path}
                      onPress={() => handleToggleIssueSelect(issue.path)}
                      style={({ pressed }) => [styles.issueRow, pressed && styles.pressed]}
                    >
                      <MaterialIcons
                        name={selectedIssuePaths[issue.path] ? 'check-box' : 'check-box-outline-blank'}
                        size={20}
                        color={theme.colors.textSecondary}
                      />
                      <View style={styles.issueContent}>
                        <AppText variant="body">{issue.type || 'Request issue'}</AppText>
                        <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                          {issue.errorMessage || issue.status || 'Pending'}
                        </AppText>
                      </View>
                    </Pressable>
                  ))}
                </View>
                <View style={styles.inlineActions}>
                  <AppButton
                    title="Recreate"
                    onPress={handleRecreateSelectedIssues}
                    disabled={selectedCount === 0 || syncActionStatus === 'working'}
                  />
                  <AppButton
                    title="Discard"
                    variant="secondary"
                    onPress={handleDiscardSelectedIssues}
                    disabled={selectedCount === 0 || syncActionStatus === 'working'}
                  />
                </View>
                <AppButton
                  title={syncActionStatus === 'working' ? 'Retrying…' : 'Retry Sync'}
                  variant="secondary"
                  onPress={handleRetrySync}
                  disabled={syncActionStatus === 'working'}
                  style={styles.inlineButton}
                />
              </>
            )}
          </View>
        </View>
      </AppScrollView>
    );
  }

  if (primaryTabKey === 'users') {
    return (
      <AppScrollView style={styles.scroll} contentContainerStyle={styles.scrollContent} refreshControl={refreshControl}>
        {!isAdmin ? (
          <AppText variant="body">Only admins and owners can manage users.</AppText>
        ) : (
          <>
            {inviteError ? (
              <View style={styles.errorBanner}>
                <AppText variant="body" style={styles.errorText}>
                  {inviteError}
                </AppText>
              </View>
            ) : null}
            {!isPro && members.length >= maxUsers ? (
              <View style={styles.infoBanner}>
                <AppText variant="body" style={getTextSecondaryStyle(uiKitTheme)}>
                  Your plan allows {maxUsers} user. Upgrade to add more people.
                </AppText>
                <AppButton title="Upgrade" onPress={() => router.push('/paywall')} style={styles.inlineButton} />
              </View>
            ) : null}
            <View style={styles.section}>
              <AppText
                variant="caption"
                style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
              >
                Invite
              </AppText>
              <View style={[surface.overflowHidden, getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.lg })]}>
                <TextInput
                  placeholder="Email"
                  value={inviteEmail}
                  onChangeText={setInviteEmail}
                  autoCapitalize="none"
                  keyboardType="email-address"
                  style={[styles.input, textPrimaryStyle]}
                  placeholderTextColor={theme.colors.textSecondary}
                />
                <SegmentedControl
                  accessibilityLabel="Invite role"
                  value={inviteRole}
                  onChange={(value) => setInviteRole(value as 'admin' | 'user')}
                  options={[
                    { value: 'user', label: 'Member' },
                    { value: 'admin', label: 'Admin' },
                  ]}
                />
                <AppButton
                  title={inviteStatus === 'saving' ? 'Creating…' : 'Create Invite'}
                  onPress={handleCreateInvite}
                  disabled={inviteStatus === 'saving' || members.length >= maxUsers}
                  style={styles.inlineButton}
                />
                {inviteCopiedToken ? (
                  <AppText variant="caption" style={[styles.helperText, getTextSecondaryStyle(uiKitTheme)]}>
                    Invite link copied.
                  </AppText>
                ) : null}
              </View>
            </View>
            <View style={styles.section}>
              <AppText
                variant="caption"
                style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
              >
                Pending Invites
              </AppText>
              <View style={[surface.overflowHidden, getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.lg })]}>
                {pendingInvites.length === 0 ? (
                  <AppText variant="body" style={getTextSecondaryStyle(uiKitTheme)}>
                    No pending invites.
                  </AppText>
                ) : (
                  pendingInvites.map((invite) => (
                    <View key={invite.id} style={styles.listRow}>
                      <View style={styles.listRowInfo}>
                        <AppText variant="body">{invite.email}</AppText>
                        <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                          {invite.role}
                        </AppText>
                      </View>
                      <Pressable
                        onPress={() => handleCopyInviteLink(invite.token)}
                        style={({ pressed }) => [styles.actionChip, pressed && styles.pressed]}
                      >
                        <AppText variant="caption" style={styles.actionText}>
                          {inviteCopiedToken === invite.token ? 'Copied' : 'Copy link'}
                        </AppText>
                      </Pressable>
                    </View>
                  ))
                )}
              </View>
            </View>
            <View style={styles.section}>
              <AppText
                variant="caption"
                style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
              >
                Team
              </AppText>
              <View style={[surface.overflowHidden, getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.lg })]}>
                {members.length === 0 ? (
                  <AppText variant="body" style={getTextSecondaryStyle(uiKitTheme)}>
                    No members found.
                  </AppText>
                ) : (
                  members.map((member) => (
                    <View key={member.id} style={styles.listRow}>
                      <AppText variant="body">{member.name || member.email || member.id}</AppText>
                      <View style={styles.roleBadge}>
                        <AppText variant="caption" style={styles.roleBadgeText}>
                          {member.role}
                        </AppText>
                      </View>
                    </View>
                  ))
                )}
              </View>
            </View>
          </>
        )}
      </AppScrollView>
    );
  }

  if (primaryTabKey === 'account') {
    return (
      <AppScrollView style={styles.scroll} contentContainerStyle={styles.scrollContent} refreshControl={refreshControl}>
        <View style={styles.section}>
          <AppText
            variant="caption"
            style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
          >
            Account Info
          </AppText>
          <View style={[surface.overflowHidden, getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.lg })]}>
            <View style={[layout.rowBetween, styles.rowGap]}>
              <AppText variant="body" style={getTextSecondaryStyle(uiKitTheme)}>
                Name
              </AppText>
              <AppText variant="body" style={[styles.value, textEmphasis.value]}>
                {user?.displayName || '—'}
              </AppText>
            </View>
            <View style={[layout.rowBetween, styles.rowGap]}>
              <AppText variant="body" style={getTextSecondaryStyle(uiKitTheme)}>
                Email
              </AppText>
              <AppText variant="body" style={[styles.value, textEmphasis.value]}>
                {user?.email || '—'}
              </AppText>
            </View>
            <View style={[layout.rowBetween, styles.rowGap]}>
              <AppText variant="body" style={getTextSecondaryStyle(uiKitTheme)}>
                Role
              </AppText>
              <AppText variant="body" style={[styles.value, textEmphasis.value]}>
                {memberRole ?? '—'}
              </AppText>
            </View>
            <AppText variant="caption" style={[styles.helperText, getTextSecondaryStyle(uiKitTheme)]}>
              Role changes require an administrator.
            </AppText>
          </View>
        </View>

        <View style={styles.section}>
          <AppText
            variant="caption"
            style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
          >
            Subscription
          </AppText>
          <View style={[surface.overflowHidden, getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.lg })]}>
            <View style={[layout.rowBetween, styles.rowGap]}>
              <AppText variant="body" style={getTextSecondaryStyle(uiKitTheme)}>
                Plan
              </AppText>
              <AppText
                variant="body"
                style={[styles.value, textEmphasis.value, isPro && getTextAccentStyle(uiKitTheme)]}
              >
                {isPro ? 'Pro' : 'Free'}
              </AppText>
            </View>
          </View>
        </View>

        {!isOwner ? (
          <AppText variant="body">Only account owners can manage accounts.</AppText>
        ) : (
          <>
            {accountError ? (
              <View style={styles.errorBanner}>
                <AppText variant="body" style={styles.errorText}>
                  {accountError}
                </AppText>
              </View>
            ) : null}
            <View style={styles.section}>
              <AppText
                variant="caption"
                style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
              >
                Create Account
              </AppText>
              <View style={[surface.overflowHidden, getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.lg })]}>
                <TextInput
                  placeholder="Account name"
                  value={accountName}
                  onChangeText={setAccountName}
                  style={[styles.input, textPrimaryStyle]}
                  placeholderTextColor={theme.colors.textSecondary}
                />
                <TextInput
                  placeholder="First user email"
                  value={accountFirstEmail}
                  onChangeText={setAccountFirstEmail}
                  autoCapitalize="none"
                  keyboardType="email-address"
                  style={[styles.input, textPrimaryStyle]}
                  placeholderTextColor={theme.colors.textSecondary}
                />
                <AppButton
                  title={accountStatus === 'saving' ? 'Creating…' : 'Create Account'}
                  onPress={handleCreateAccount}
                  disabled={accountStatus === 'saving'}
                  style={styles.inlineButton}
                />
                {createdAccountInvite ? (
                  <View style={styles.inlineActions}>
                    <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                      Invite link ready.
                    </AppText>
                    <Pressable
                      onPress={() => handleCopyAccountInviteLink(createdAccountInvite.token)}
                      style={({ pressed }) => [styles.actionChip, pressed && styles.pressed]}
                    >
                      <AppText variant="caption" style={styles.actionText}>
                        {inviteCopiedToken === createdAccountInvite.token ? 'Copied' : 'Copy link'}
                      </AppText>
                    </Pressable>
                  </View>
                ) : null}
              </View>
            </View>
            <View style={styles.section}>
              <AppText
                variant="caption"
                style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
              >
                Accounts
              </AppText>
              <View style={[surface.overflowHidden, getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.lg })]}>
                {accounts.length === 0 ? (
                  <AppText variant="body" style={getTextSecondaryStyle(uiKitTheme)}>
                    No accounts found.
                  </AppText>
                ) : (
                  accounts.map((account) => (
                    <View key={account.accountId} style={styles.accountRow}>
                      <Pressable
                        onPress={() => handleToggleAccountExpand(account.accountId)}
                        style={({ pressed }) => [styles.accountHeader, pressed && styles.pressed]}
                      >
                        <AppText variant="body">{account.name || 'Untitled account'}</AppText>
                        <MaterialIcons
                          name={expandedAccounts[account.accountId] ? 'expand-less' : 'expand-more'}
                          size={20}
                          color={theme.colors.textSecondary}
                        />
                      </Pressable>
                      {expandedAccounts[account.accountId] ? (
                        <View style={styles.accountInvites}>
                          {(accountInvites[account.accountId] ?? []).length === 0 ? (
                            <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                              No pending invites.
                            </AppText>
                          ) : (
                            (accountInvites[account.accountId] ?? []).map((invite) => (
                              <View key={invite.id} style={styles.listRow}>
                                <View style={styles.listRowInfo}>
                                  <AppText variant="body">{invite.email}</AppText>
                                  <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                                    {invite.role}
                                  </AppText>
                                </View>
                                <Pressable
                                  onPress={() => handleCopyAccountInviteLink(invite.token)}
                                  style={({ pressed }) => [styles.actionChip, pressed && styles.pressed]}
                                >
                                  <AppText variant="caption" style={styles.actionText}>
                                    {inviteCopiedToken === invite.token ? 'Copied' : 'Copy link'}
                                  </AppText>
                                </Pressable>
                              </View>
                            ))
                          )}
                        </View>
                      ) : null}
                    </View>
                  ))
                )}
              </View>
            </View>
          </>
        )}
      </AppScrollView>
    );
  }

  return (
    <AppScrollView style={styles.scroll} contentContainerStyle={styles.scrollContent} refreshControl={refreshControl}>
      <View style={styles.section}>
        <InfoCard
          title="User Profile"
          titleRight={
            user ? (
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Edit profile"
                onPress={openUserProfileEditor}
                hitSlop={10}
                style={({ pressed }) => [styles.titleIconButton, pressed && styles.pressed]}
              >
                <MaterialIcons name="edit" size={16} color={theme.colors.textSecondary} />
              </Pressable>
            ) : null
          }
        >
          {!user ? (
            <AppText variant="body" style={getTextSecondaryStyle(uiKitTheme)}>
              You’re not signed in.
            </AppText>
          ) : (
            <>
              <InfoCard.Field label="Name" value={userDisplayNameInitial.trim() || '—'} />
              <InfoCard.Field label="Email" value={user.email || '—'} />
            </>
          )}
        </InfoCard>
      </View>

      <FormBottomSheet
        visible={userProfileEditorVisible}
        onRequestClose={closeUserProfileEditor}
        title="Edit profile"
        primaryAction={{
          title: 'Save',
          onPress: handleSaveUserProfile,
          loading: userProfileStatus === 'saving',
          disabled: userProfileStatus === 'saving' || !userDisplayNameDraft.trim() || !isUserProfileDirty,
        }}
        secondaryAction={{
          title: 'Cancel',
          onPress: closeUserProfileEditor,
          disabled: userProfileStatus === 'saving',
        }}
        error={userProfileError || undefined}
      >
        <FormField
          label="Full name"
          value={userDisplayNameDraft}
          onChangeText={(next) => {
            setUserProfileError('');
            setUserProfileStatus('idle');
            setUserDisplayNameDraft(next);
          }}
          placeholder="Your name"
          disabled={userProfileStatus === 'saving'}
          inputProps={{
            autoCapitalize: 'words',
            autoCorrect: false,
          }}
        />
      </FormBottomSheet>

      {isAdmin ? (
        <View style={styles.section}>
          <AppText
            variant="caption"
            style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
          >
            Business Profile
          </AppText>
          <View style={[surface.overflowHidden, getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.lg })]}>
            {profileError ? (
              <View style={styles.errorBanner}>
                <AppText variant="body" style={styles.errorText}>
                  {profileError}
                </AppText>
              </View>
            ) : null}
            {logoError ? (
              <View style={styles.errorBanner}>
                <AppText variant="body" style={styles.errorText}>
                  {logoError}
                </AppText>
              </View>
            ) : null}
            {logoPreviewUri ? (
              <View style={styles.logoPreview}>
                <Image source={{ uri: logoPreviewUri }} style={styles.logoImage} resizeMode="contain" />
              </View>
            ) : null}
            <AppButton title="Choose Logo" variant="secondary" onPress={handlePickLogo} />
            <AppText variant="caption" style={[styles.helperText, getTextSecondaryStyle(uiKitTheme)]}>
              PNG, JPG, or WebP. Max 10 MB.
            </AppText>
            <TextInput
              placeholder="Business name"
              value={profileDraft}
              onChangeText={setProfileDraft}
              style={[styles.input, textPrimaryStyle]}
              placeholderTextColor={theme.colors.textSecondary}
            />
            <AppButton
              title={profileStatus === 'saving' ? 'Saving…' : 'Save Business Profile'}
              onPress={handleSaveProfile}
              disabled={profileStatus === 'saving' || !profileDraft.trim()}
              style={styles.inlineButton}
            />
            {profileStatus === 'success' ? (
              <AppText variant="caption" style={[styles.successText, getTextSecondaryStyle(uiKitTheme)]}>
                Business profile saved.
              </AppText>
            ) : null}
          </View>
        </View>
      ) : null}

      <View style={styles.section}>
        <AppText
          variant="caption"
          style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
        >
          Appearance
        </AppText>
        <View style={[surface.overflowHidden, getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.lg })]}>
          <SegmentedControl
            accessibilityLabel="Appearance"
            value={appearanceMode}
            onChange={setAppearanceMode}
            options={[
              {
                value: 'system',
                label: 'Auto',
                icon: (
                  <MaterialIcons
                    name="brightness-auto"
                    size={18}
                    color={appearanceMode === 'system' ? theme.colors.primary : theme.colors.textSecondary}
                  />
                ),
              },
              {
                value: 'light',
                label: 'Light',
                icon: (
                  <MaterialIcons
                    name="light-mode"
                    size={18}
                    color={appearanceMode === 'light' ? theme.colors.primary : theme.colors.textSecondary}
                  />
                ),
              },
              {
                value: 'dark',
                label: 'Dark',
                icon: (
                  <MaterialIcons
                    name="dark-mode"
                    size={18}
                    color={appearanceMode === 'dark' ? theme.colors.primary : theme.colors.textSecondary}
                  />
                ),
              },
            ]}
          />
        </View>
      </View>

      {!isPro && <AppButton title="Upgrade to Pro" onPress={() => router.push('/paywall')} style={styles.button} />}
    </AppScrollView>
  );
}

export default function SettingsScreen() {
  const { accountId } = useAccountContextStore();
  const { user, signOut } = useAuthStore();
  const theme = useTheme();
  const [selectedPresetTabKey, setSelectedPresetTabKey] = useState<string>(PRESET_TABS[0]?.key ?? 'spaces');
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [memberRole, setMemberRole] = useState<'owner' | 'admin' | 'user' | null>(null);
  const router = useRouter();
  const handleRefresh = useCallback(async () => {
    setIsRefreshing(true);
    setIsRefreshing(false);
  }, []);

  useEffect(() => {
    if (!accountId || !user?.uid) {
      setMemberRole(null);
      return;
    }
    return subscribeToAccountMember(accountId, user.uid, (member) => {
      setMemberRole(member?.role ?? null);
    });
  }, [accountId, user?.uid]);

  const visibleTabs = useMemo(() => {
    const isAdmin = memberRole === 'owner' || memberRole === 'admin';
    const isOwner = memberRole === 'owner';
    return PRIMARY_TABS.filter((tab) => {
      if (tab.key === 'users') return isAdmin;
      if (tab.key === 'account') return isOwner;
      return true;
    });
  }, [memberRole]);

  const handleSignOut = useCallback(() => {
    if (isAuthBypassEnabled) {
      router.replace('/(auth)/sign-in?preview=1');
      return;
    }
    Alert.alert('Sign Out', 'Are you sure you want to sign out?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Sign Out',
        style: 'destructive',
        onPress: async () => {
          try {
            await signOut();
            router.replace('/(auth)/sign-in');
          } catch (error: any) {
            Alert.alert('Error', error.message || 'Failed to sign out');
          }
        },
      },
    ]);
  }, [router, signOut]);

  return (
    <Screen
      key={visibleTabs.map((tab) => tab.key).join('|')}
      title="Settings"
      includeBottomInset={false}
      refreshing={isRefreshing}
      onRefresh={handleRefresh}
      hideBackButton={true}
      infoContent={{
        title: 'Settings',
        message: 'Manage your account settings, presets, users, and troubleshooting tools.',
      }}
      tabs={visibleTabs}
      headerRight={
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={isAuthBypassEnabled ? 'Sign in' : 'Sign out'}
          hitSlop={10}
          onPress={handleSignOut}
          style={({ pressed }) => [styles.headerIconButton, pressed && styles.pressed]}
        >
          <MaterialIcons name={isAuthBypassEnabled ? 'login' : 'logout'} size={22} color={theme.colors.primary} />
        </Pressable>
      }
      renderBelowTabs={({ selectedKey }) =>
        selectedKey === 'presets' ? (
          <ScreenTabs tabs={PRESET_TABS} value={selectedPresetTabKey} onChange={setSelectedPresetTabKey} />
        ) : null
      }
    >
      <SettingsContent selectedPresetTabKey={selectedPresetTabKey} memberRole={memberRole} />
    </Screen>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  scroll: {
    flex: 1,
  },
  scrollContent: {
    paddingTop: 0,
  },
  section: {
    marginBottom: 18,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 8,
    marginBottom: 8,
  },
  sectionTitle: {
    marginBottom: 8,
  },
  helperText: {
    marginTop: 8,
  },
  categoryTypeHelper: {
    marginBottom: 24,
    lineHeight: 18,
  },
  rowGap: {
    marginBottom: 8,
  },
  value: {
    textAlign: 'right',
  },
  input: {
    borderWidth: 1,
    borderColor: '#DADADA',
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 10,
    marginBottom: 12,
  },
  inputSaving: {
    opacity: 0.6,
  },
  inlineButton: {
    marginTop: 4,
  },
  inlineActions: {
    flexDirection: 'row',
    gap: 8,
  },
  rowActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  actionChip: {
    borderWidth: 1,
    borderColor: '#DADADA',
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 6,
  },
  actionText: {
    color: '#4B4B4B',
  },
  inlineToggle: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  inlineToggleText: {
    color: '#6B6B6B',
  },
  pressed: {
    opacity: 0.7,
  },
  errorBanner: {
    borderWidth: 1,
    borderColor: '#D9534F',
    borderRadius: 10,
    padding: 10,
    marginBottom: 12,
  },
  infoBanner: {
    borderWidth: 1,
    borderColor: '#DADADA',
    borderRadius: 10,
    padding: 10,
    marginBottom: 12,
  },
  errorText: {
    color: '#D9534F',
  },
  successText: {
    marginTop: 8,
  },
  listRow: {
    marginBottom: 10,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
  },
  listRowInfo: {
    flex: 1,
    minWidth: 0,
  },
  listRowText: {
    marginBottom: 8,
  },
  vendorInput: {
    marginBottom: 0,
  },
  vendorCard: {
    paddingVertical: 8,
  },
  draggableRow: {
    paddingVertical: 4,
  },
  logoPreview: {
    height: 120,
    marginBottom: 12,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#DADADA',
    overflow: 'hidden',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#F5F5F5',
  },
  logoImage: {
    width: '100%',
    height: '100%',
  },
  nestedBlock: {
    marginTop: 12,
    padding: 10,
    borderWidth: 1,
    borderColor: '#E0E0E0',
    borderRadius: 10,
  },
  nestedRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginBottom: 8,
  },
  nestedInput: {
    flex: 1,
    marginBottom: 0,
  },
  iconButton: {
    padding: 6,
  },
  cardIconButton: {
    padding: 6,
    borderRadius: 999,
  },
  titleIconButton: {
    padding: 2,
  },
  rowBetween: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 8,
  },
  roleBadge: {
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 4,
    backgroundColor: '#F0F0F0',
  },
  roleBadgeText: {
    color: '#555555',
  },
  listBlock: {
    marginTop: 10,
    marginBottom: 10,
  },
  issueRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingVertical: 8,
  },
  issueContent: {
    flex: 1,
  },
  accountRow: {
    marginBottom: 12,
  },
  accountHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  accountInvites: {
    marginTop: 8,
  },
  button: {
    marginTop: 12,
  },
  headerIconButton: {
    padding: 12,
    alignItems: 'center',
    justifyContent: 'center',
    minWidth: 44,
    minHeight: 44,
  },
});
