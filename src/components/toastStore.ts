import { create } from 'zustand';

type ToastState = {
  message: string | null;
  show: (message: string) => void;
  hide: () => void;
};

let timer: ReturnType<typeof setTimeout> | null = null;

export const useToastStore = create<ToastState>((set) => ({
  message: null,
  show: (message) => {
    if (timer) clearTimeout(timer);
    set({ message });
    timer = setTimeout(() => {
      set({ message: null });
      timer = null;
    }, 2500);
  },
  hide: () => {
    if (timer) clearTimeout(timer);
    timer = null;
    set({ message: null });
  },
}));

export const showToast = (message: string) => useToastStore.getState().show(message);
