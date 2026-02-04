import type { Checklist } from './spacesService';

export type SpaceTemplate = {
  id: string;
  name: string;
  notes?: string;
  checklists?: Checklist[];
};

export const SPACE_TEMPLATES: SpaceTemplate[] = [
  {
    id: 'storage',
    name: 'Storage',
    notes: 'Standard storage setup',
    checklists: [
      {
        id: 'storage_setup',
        name: 'Storage setup',
        items: [
          { id: 'label_bins', text: 'Label bins', isChecked: false },
          { id: 'safety_check', text: 'Safety check', isChecked: false },
        ],
      },
    ],
  },
  {
    id: 'showroom',
    name: 'Showroom',
    notes: 'Display-ready space',
    checklists: [
      {
        id: 'display',
        name: 'Display prep',
        items: [
          { id: 'lighting', text: 'Lighting set', isChecked: false },
          { id: 'clean', text: 'Clean surfaces', isChecked: false },
        ],
      },
    ],
  },
];
