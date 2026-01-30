# Dictation Widget (Optional Feature)

This is an **optional** feature that is **not enabled by default**. Apps that need dictation can opt-in.

## Setup

1. Install the dependency:
   ```bash
   npm install git+ssh://git@github.com:nine4-team/react-dictation.git
   ```

2. Import and use the component in your screen:
   ```tsx
   import { DictationWidget } from '@/features/dictation/DictationWidget';
   
   // In your component:
   <DictationWidget onTranscript={handleTranscript} />
   ```

3. See `/Users/benjaminmackenzie/Dev/memories` for reference implementation patterns.

## Note

This feature is **not imported** anywhere in the default template. You must explicitly add it to screens where you want dictation functionality.
