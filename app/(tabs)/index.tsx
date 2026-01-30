import { ScrollView, StyleSheet, View } from 'react-native';

import { AppText } from '../../src/components/AppText';
import { ExpandableCard } from '../../src/components/ExpandableCard';
import { ItemCard } from '../../src/components/ItemPreviewCard';
import { GroupedItemCard } from '../../src/components';
import { Screen } from '../../src/components/Screen';
import { useScreenTabs } from '../../src/components/ScreenTabs';
import { CARD_LIST_GAP, layout } from '../../src/ui';

export default function ComponentsScreen() {
  return (
    <Screen 
      title="Components"
      tabs={[
        { key: 'cards', label: 'Cards', accessibilityLabel: 'Cards tab' },
        { key: 'tab-two', label: 'Tab Two', accessibilityLabel: 'Tab Two' },
        { key: 'tab-three', label: 'Tab Three', accessibilityLabel: 'Tab Three' },
      ]}
      initialTabKey="cards"
    >
      <ComponentsScreenContent />
    </Screen>
  );
}

function ComponentsScreenContent() {
  const screenTabs = useScreenTabs();
  const selectedKey = screenTabs?.selectedKey ?? 'cards';

  if (selectedKey === 'cards') {
    return (
      <ScrollView 
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        <ExpandableCard
          title="Expandable Card"
          expandableRow1={{ label: 'Expandable Field 1', value: 'Expandable Field 3' }}
          expandableRow2={{ label: 'Expandable Field 2', value: 'Expandable Field 4' }}
          alwaysShowRow1={{ label: 'Always Show 1', value: 'Always Show Value 1' }}
          alwaysShowRow2={{ label: 'Always Show 2', value: 'Always Show Value 2' }}
          menuBadgeEnabled
          menuBadgeLabel="Badge"
          menuItems={[
            {
              key: 'action-with-subactions',
              label: 'Action 1',
              defaultSelectedSubactionKey: 'subaction-1',
              subactions: [
                { key: 'subaction-1', label: 'Subaction 1', onPress: () => console.log('Subaction 1 pressed') },
                { key: 'subaction-2', label: 'Subaction 2', onPress: () => console.log('Subaction 2 pressed') },
              ],
            },
            { key: 'edit', label: 'Edit', onPress: () => console.log('Edit pressed') },
            { key: 'delete', label: 'Delete', onPress: () => console.log('Delete pressed') },
          ]}
        />

        <ItemCard
          description="CB2 — Pebble Side Table (white oak), sculpted profile with a softly rounded edge and a compact footprint for tight living spaces"
          sku="CB2-PS-001"
          sourceLabel="Wayfair"
          priceLabel="$249.00"
          statusLabel="In project"
          locationLabel="Living room North wall"
          defaultSelected={false}
          onSelectedChange={(next) => console.log('Selected changed', next)}
          bookmarked={true}
          onBookmarkPress={() => console.log('Bookmark pressed')}
          onAddImagePress={() => console.log('Add image pressed')}
          onMenuPress={() => console.log('Menu pressed')}
          onPress={() => console.log('Item card pressed')}
        />

        <GroupedItemCard
          summary={{
            description: 'Wayfair — Pillow Insert (Down alternative)',
            sku: 'WF-PI-STD-001',
            sourceLabel: 'Wayfair',
            locationLabel: 'Guest room Closet',
            thumbnailUri:
              'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=240&q=80',
          }}
          countLabel="×2"
          totalLabel="$59.98"
          defaultSelected={false}
          onSelectedChange={(next: boolean) => console.log('Group selected', next)}
          items={[
            {
              description: 'Wayfair — Pillow Insert (Down alternative)',
              sku: 'WF-PI-STD-001',
              sourceLabel: 'Wayfair',
              priceLabel: '$29.99',
              statusLabel: 'In project',
              locationLabel: 'Guest room Closet',
              thumbnailUri:
                'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=240&q=80',
              defaultSelected: true,
              onSelectedChange: (next: boolean) => console.log('Child item 1 selected', next),
              bookmarked: false,
              onBookmarkPress: () => console.log('Child item 1 bookmark pressed'),
              onAddImagePress: () => console.log('Child item 1 add image pressed'),
              onMenuPress: () => console.log('Child item 1 menu pressed'),
              onPress: () => console.log('Child item 1 pressed'),
            },
            {
              description: 'Wayfair — Pillow Insert (Down alternative)',
              sku: 'WF-PI-STD-001',
              sourceLabel: 'Wayfair',
              priceLabel: '$29.99',
              statusLabel: 'In project',
              locationLabel: 'Guest room Closet',
              thumbnailUri:
                'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=240&q=80',
              defaultSelected: false,
              onSelectedChange: (next: boolean) => console.log('Child item 2 selected', next),
              bookmarked: true,
              onBookmarkPress: () => console.log('Child item 2 bookmark pressed'),
              onAddImagePress: () => console.log('Child item 2 add image pressed'),
              onMenuPress: () => console.log('Child item 2 menu pressed'),
              onPress: () => console.log('Child item 2 pressed'),
            },
          ]}
          defaultExpanded={false}
        />

      </ScrollView>
    );
  }

  if (selectedKey === 'tab-two') {
    return (
      <View style={styles.placeholder}>
        <AppText variant="body">Tab Two content goes here.</AppText>
      </View>
    );
  }

  return (
    <View style={styles.placeholder}>
      <AppText variant="body">Tab Three content goes here.</AppText>
    </View>
  );
}

const styles = StyleSheet.create({
  scrollContent: {
    paddingTop: layout.screenBodyTopMd.paddingTop,
    gap: CARD_LIST_GAP,
  },
  placeholder: {
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
});
