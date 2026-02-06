import { useContext, useEffect, useState } from 'react';
import { NavigationContext } from '@react-navigation/native';

export function useOptionalIsFocused(defaultValue = true): boolean {
  const navigation = useContext(NavigationContext);
  const [isFocused, setIsFocused] = useState<boolean>(
    () => navigation?.isFocused?.() ?? defaultValue
  );

  useEffect(() => {
    if (!navigation) return;
    const update = () => setIsFocused(navigation.isFocused());
    update();
    const unsubscribeFocus = navigation.addListener?.('focus', update);
    const unsubscribeBlur = navigation.addListener?.('blur', update);
    return () => {
      if (typeof unsubscribeFocus === 'function') unsubscribeFocus();
      if (typeof unsubscribeBlur === 'function') unsubscribeBlur();
    };
  }, [navigation]);

  return isFocused;
}
