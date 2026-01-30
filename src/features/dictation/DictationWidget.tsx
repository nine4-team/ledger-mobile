/**
 * Dictation Widget Wrapper (Optional Feature)
 * 
 * This is a placeholder component. To use dictation:
 * 1. Install: npm install git+ssh://git@github.com:nine4-team/react-dictation.git
 * 2. Import the actual component from react-dictation
 * 3. Replace this placeholder with the real implementation
 * 
 * See README.md in this directory for more details.
 */

import React from 'react';
import { View, StyleSheet } from 'react-native';
import { AppText } from '../../components/AppText';

interface DictationWidgetProps {
  onTranscript?: (text: string) => void;
}

export const DictationWidget: React.FC<DictationWidgetProps> = ({ onTranscript }) => {
  // Placeholder - replace with actual dictation widget implementation
  return (
    <View style={styles.container}>
      <AppText variant="caption">
        Dictation widget not installed. See src/features/dictation/README.md for setup instructions.
      </AppText>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    padding: 16,
    backgroundColor: '#f5f5f5',
    borderRadius: 8,
  },
});
