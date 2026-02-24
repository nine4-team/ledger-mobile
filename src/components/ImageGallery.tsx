import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Animated,
  Dimensions,
  Image,
  Modal,
  Pressable,
  StyleSheet,
  View,
} from 'react-native';
import { PanGestureHandler, PinchGestureHandler, State, TapGestureHandler } from 'react-native-gesture-handler';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { resolveAttachmentUri } from '../offline/media';
import type { AttachmentRef } from '../offline/media';
import { useUIKitTheme } from '../theme/ThemeProvider';
import { AppText } from './AppText';

export type ImageGalleryProps = {
  images: AttachmentRef[];
  initialIndex?: number;
  visible: boolean;
  onRequestClose: () => void;
  onPinToggle?: (image: AttachmentRef, index: number) => void;
};

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get('window');
const MIN_ZOOM = 1;
const MAX_ZOOM = 5;
const ZOOM_STEP = 0.5;
const AUTO_HIDE_DELAY = 2200;

export function ImageGallery({
  images,
  initialIndex = 0,
  visible,
  onRequestClose,
  onPinToggle,
}: ImageGalleryProps) {
  const uiKitTheme = useUIKitTheme();
  const insets = useSafeAreaInsets();
  const [currentIndex, setCurrentIndex] = useState(initialIndex);
  const [zoom, setZoom] = useState(1);
  const [controlsVisible, setControlsVisible] = useState(true);
  const [lastInteractionTime, setLastInteractionTime] = useState(Date.now());
  const [imageSize, setImageSize] = useState({ width: SCREEN_WIDTH, height: SCREEN_HEIGHT });

  const zoomAnim = useRef(new Animated.Value(1)).current;
  const pinchScale = useRef(new Animated.Value(1)).current;
  const translateX = useRef(new Animated.Value(0)).current;
  const translateY = useRef(new Animated.Value(0)).current;
  const controlsOpacity = useRef(new Animated.Value(1)).current;
  const lastScaleRef = useRef(1);
  const lastTranslateRef = useRef({ x: 0, y: 0 });
  const panRef = useRef(null);
  const pinchRef = useRef(null);

  const currentImage = images[currentIndex];
  const resolvedUri = currentImage ? resolveAttachmentUri(currentImage) : null;
  const scale = useMemo(() => Animated.multiply(zoomAnim, pinchScale), [zoomAnim, pinchScale]);
  const { baseWidth, baseHeight } = useMemo(() => {
    const scaleToFit = Math.min(SCREEN_WIDTH / imageSize.width, SCREEN_HEIGHT / imageSize.height);
    return {
      baseWidth: imageSize.width * scaleToFit,
      baseHeight: imageSize.height * scaleToFit,
    };
  }, [imageSize]);

  useEffect(() => {
    if (!resolvedUri) return;
    let isActive = true;
    Image.getSize(
      resolvedUri,
      (width, height) => {
        if (isActive) {
          setImageSize({ width, height });
        }
      },
      () => {
        if (isActive) {
          setImageSize({ width: SCREEN_WIDTH, height: SCREEN_HEIGHT });
        }
      }
    );
    return () => {
      isActive = false;
    };
  }, [resolvedUri]);

  // Update current index when initialIndex changes
  useEffect(() => {
    if (visible && initialIndex >= 0 && initialIndex < images.length) {
      setCurrentIndex(initialIndex);
    }
  }, [visible, initialIndex, images.length]);

  // Reset zoom/pan when switching images
  useEffect(() => {
    if (visible) {
      setZoom(1);
      lastScaleRef.current = 1;
      zoomAnim.setValue(1);
      pinchScale.setValue(1);
      translateX.setValue(0);
      translateY.setValue(0);
      lastTranslateRef.current = { x: 0, y: 0 };
      setControlsVisible(true);
      controlsOpacity.setValue(1);
    }
  }, [currentIndex, visible, zoomAnim, pinchScale, translateX, translateY, controlsOpacity]);

  // Auto-hide controls when not zoomed
  useEffect(() => {
    if (!visible || zoom > 1.01) return;

    const interval = setInterval(() => {
      const now = Date.now();
      if (now - lastInteractionTime > AUTO_HIDE_DELAY) {
        setControlsVisible(false);
        Animated.timing(controlsOpacity, {
          toValue: 0,
          duration: 200,
          useNativeDriver: true,
        }).start();
      }
    }, 100);

    return () => clearInterval(interval);
  }, [visible, zoom, lastInteractionTime, controlsOpacity]);

  const updateInteractionTime = useCallback(() => {
    setLastInteractionTime(Date.now());
    if (!controlsVisible) {
      setControlsVisible(true);
      Animated.timing(controlsOpacity, {
        toValue: 1,
        duration: 200,
        useNativeDriver: true,
      }).start();
    }
  }, [controlsVisible, controlsOpacity]);

  useEffect(() => {
    const xSub = translateX.addListener(({ value }) => {
      lastTranslateRef.current.x = value;
    });
    const ySub = translateY.addListener(({ value }) => {
      lastTranslateRef.current.y = value;
    });
    return () => {
      translateX.removeListener(xSub);
      translateY.removeListener(ySub);
    };
  }, [translateX, translateY]);

  const clampScale = useCallback(
    (value: number) => Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, value)),
    []
  );

  const clampPan = useCallback(
    (nextScale: number, nextTranslate: { x: number; y: number }) => {
      const scaledWidth = baseWidth * nextScale;
      const scaledHeight = baseHeight * nextScale;
      const maxPanX = Math.max(0, (scaledWidth - SCREEN_WIDTH) / 2);
      const maxPanY = Math.max(0, (scaledHeight - SCREEN_HEIGHT) / 2);
      return {
        x: Math.max(-maxPanX, Math.min(maxPanX, nextTranslate.x)),
        y: Math.max(-maxPanY, Math.min(maxPanY, nextTranslate.y)),
      };
    },
    [baseWidth, baseHeight]
  );

  const applyTranslate = useCallback(
    (x: number, y: number) => {
      translateX.setValue(x);
      translateY.setValue(y);
      lastTranslateRef.current = { x, y };
    },
    [translateX, translateY]
  );

  useEffect(() => {
    const clampedPan = clampPan(lastScaleRef.current, lastTranslateRef.current);
    applyTranslate(clampedPan.x, clampedPan.y);
  }, [applyTranslate, clampPan, baseWidth, baseHeight]);

  const handleZoom = useCallback(
    (newZoom: number) => {
      const clampedZoom = clampScale(newZoom);
      lastScaleRef.current = clampedZoom;
      setZoom(clampedZoom);
      Animated.spring(zoomAnim, {
        toValue: clampedZoom,
        useNativeDriver: true,
      }).start();
      pinchScale.setValue(1);
      const clampedPan = clampPan(clampedZoom, lastTranslateRef.current);
      applyTranslate(clampedPan.x, clampedPan.y);
      updateInteractionTime();
    },
    [applyTranslate, zoomAnim, clampPan, clampScale, pinchScale, updateInteractionTime]
  );

  const handleZoomIn = useCallback(() => {
    handleZoom(zoom + ZOOM_STEP);
  }, [zoom, handleZoom]);

  const handleZoomOut = useCallback(() => {
    handleZoom(zoom - ZOOM_STEP);
  }, [zoom, handleZoom]);

  const handleResetZoom = useCallback(() => {
    lastScaleRef.current = 1;
    setZoom(1);
    Animated.spring(zoomAnim, {
      toValue: 1,
      useNativeDriver: true,
    }).start();
    pinchScale.setValue(1);
    applyTranslate(0, 0);
    updateInteractionTime();
  }, [applyTranslate, zoomAnim, pinchScale, updateInteractionTime]);

  const onPanGestureEvent = useMemo(
    () =>
      Animated.event(
        [
          {
            nativeEvent: {
              translationX: translateX,
              translationY: translateY,
            },
          },
        ],
        { useNativeDriver: false }
      ),
    [translateX, translateY]
  );

  const handlePanStateChange = useCallback(
    (event: any) => {
      const { state } = event.nativeEvent;
      if (state === State.BEGAN) {
        updateInteractionTime();
        translateX.setOffset(lastTranslateRef.current.x);
        translateX.setValue(0);
        translateY.setOffset(lastTranslateRef.current.y);
        translateY.setValue(0);
      }
      if (state === State.END || state === State.CANCELLED || state === State.FAILED) {
        translateX.flattenOffset();
        translateY.flattenOffset();
        const clampedPan = clampPan(lastScaleRef.current, lastTranslateRef.current);
        applyTranslate(clampedPan.x, clampedPan.y);
      }
    },
    [applyTranslate, clampPan, translateX, translateY, updateInteractionTime]
  );

  const onPinchGestureEvent = useMemo(
    () =>
      Animated.event(
        [
          {
            nativeEvent: {
              scale: pinchScale,
            },
          },
        ],
        { useNativeDriver: false }
      ),
    [pinchScale]
  );

  const handlePinchStateChange = useCallback(
    (event: any) => {
      const { state, scale: gestureScale } = event.nativeEvent;
      if (state === State.BEGAN) {
        updateInteractionTime();
      }
      if (state === State.END || state === State.CANCELLED || state === State.FAILED) {
        const nextScale = clampScale(lastScaleRef.current * gestureScale);
        lastScaleRef.current = nextScale;
        setZoom(nextScale);
        Animated.spring(zoomAnim, {
          toValue: nextScale,
          useNativeDriver: true,
        }).start();
        pinchScale.setValue(1);
        const clampedPan = clampPan(nextScale, lastTranslateRef.current);
        applyTranslate(clampedPan.x, clampedPan.y);
      }
    },
    [applyTranslate, zoomAnim, clampPan, clampScale, pinchScale, updateInteractionTime]
  );

  const handleDoubleTap = useCallback(
    (event: any) => {
      const { state, x, y } = event.nativeEvent;
      if (state !== State.ACTIVE) return;
      updateInteractionTime();
      const nextScale = zoom > 1.01 ? 1 : 2;
      const scaleRatio = nextScale / zoom;
      const tapX = x - SCREEN_WIDTH / 2;
      const tapY = y - SCREEN_HEIGHT / 2;
      const nextTranslate = {
        x: lastTranslateRef.current.x * scaleRatio + tapX * (1 - scaleRatio),
        y: lastTranslateRef.current.y * scaleRatio + tapY * (1 - scaleRatio),
      };
      const clampedPan = clampPan(nextScale, nextTranslate);
      lastScaleRef.current = nextScale;
      setZoom(nextScale);
      Animated.spring(zoomAnim, {
        toValue: nextScale,
        useNativeDriver: true,
      }).start();
      pinchScale.setValue(1);
      applyTranslate(clampedPan.x, clampedPan.y);
    },
    [applyTranslate, zoomAnim, clampPan, pinchScale, updateInteractionTime, zoom]
  );

  const handlePrev = useCallback(() => {
    updateInteractionTime();
    const newIndex = currentIndex > 0 ? currentIndex - 1 : images.length - 1;
    setCurrentIndex(newIndex);
  }, [currentIndex, images.length, updateInteractionTime]);

  const handleNext = useCallback(() => {
    updateInteractionTime();
    const newIndex = currentIndex < images.length - 1 ? currentIndex + 1 : 0;
    setCurrentIndex(newIndex);
  }, [currentIndex, images.length, updateInteractionTime]);

  const handleClose = useCallback(() => {
    onRequestClose();
  }, [onRequestClose]);

  const handleBackgroundPress = useCallback(() => {
    updateInteractionTime();
    setControlsVisible((prev) => !prev);
    Animated.timing(controlsOpacity, {
      toValue: controlsVisible ? 0 : 1,
      duration: 200,
      useNativeDriver: true,
    }).start();
  }, [controlsVisible, controlsOpacity, updateInteractionTime]);

  if (!visible || !currentImage) return null;

  const canZoomIn = zoom < MAX_ZOOM;
  const canZoomOut = zoom > MIN_ZOOM;
  const showResetZoom = zoom > 1.01;

  return (
    <Modal
      visible={visible}
      transparent
      animationType="fade"
      onRequestClose={handleClose}
      statusBarTranslucent
    >
      <View style={styles.container}>
        <Pressable
          style={StyleSheet.absoluteFill}
          onPress={handleBackgroundPress}
          accessibilityRole="button"
          accessibilityLabel="Toggle controls"
        >
          <View style={[styles.background, { backgroundColor: 'rgba(0, 0, 0, 0.95)' }]} />
        </Pressable>

        {resolvedUri ? (
          <View style={styles.mediaStage} pointerEvents="box-none">
            <TapGestureHandler onHandlerStateChange={handleDoubleTap} numberOfTaps={2}>
              <PinchGestureHandler
                ref={pinchRef}
                simultaneousHandlers={panRef}
                onGestureEvent={onPinchGestureEvent}
                onHandlerStateChange={handlePinchStateChange}
              >
                <Animated.View>
                  <PanGestureHandler
                    ref={panRef}
                    simultaneousHandlers={pinchRef}
                    enabled={zoom > 1.01}
                    onGestureEvent={onPanGestureEvent}
                    onHandlerStateChange={handlePanStateChange}
                  >
                    <Animated.View
                      style={[
                        styles.imageContainer,
                        {
                          width: baseWidth,
                          height: baseHeight,
                          transform: [{ scale }, { translateX }, { translateY }],
                        },
                      ]}
                    >
                      <Image
                        source={{ uri: resolvedUri }}
                        style={[styles.image, { width: baseWidth, height: baseHeight }]}
                        resizeMode="contain"
                        accessibilityIgnoresInvertColors
                      />
                    </Animated.View>
                  </PanGestureHandler>
                </Animated.View>
              </PinchGestureHandler>
            </TapGestureHandler>
          </View>
        ) : (
          <View style={styles.placeholderContainer}>
            <MaterialIcons name="image-not-supported" size={64} color={uiKitTheme.text.secondary} />
            <AppText variant="body" style={styles.placeholderText}>
              Image not available
            </AppText>
          </View>
        )}

        {/* Close button always interactive, outside the pointerEvents gate */}
        <Animated.View
          style={[
            styles.topBar,
            {
              opacity: controlsOpacity,
              paddingTop: insets.top + 12,
              position: 'absolute',
              top: 0,
              left: 0,
              right: 0,
              zIndex: 10,
            },
          ]}
          pointerEvents="box-none"
        >
          <Pressable
            onPress={handleClose}
            style={styles.closeButton}
            accessibilityRole="button"
            accessibilityLabel="Close gallery"
          >
            <MaterialIcons name="close" size={24} color="#FFFFFF" />
          </Pressable>

          {onPinToggle && (
            <Pressable
              onPress={() => {
                onPinToggle(currentImage, currentIndex);
                handleClose();
              }}
              style={styles.pinButton}
              accessibilityRole="button"
              accessibilityLabel="Pin image"
            >
              <MaterialIcons name="push-pin" size={24} color="#FFFFFF" />
            </Pressable>
          )}
        </Animated.View>

        <Animated.View
          style={[
            styles.controls,
            {
              opacity: controlsOpacity,
              paddingTop: insets.top + 12,
              paddingBottom: insets.bottom + 12,
            },
          ]}
          pointerEvents={controlsVisible ? 'auto' : 'none'}
        >
          <View style={styles.topBar} pointerEvents="none" />

          {images.length > 1 && (
            <View style={styles.navigation}>
              <Pressable
                onPress={handlePrev}
                style={styles.navButton}
                accessibilityRole="button"
                accessibilityLabel="Previous image"
              >
                <MaterialIcons name="chevron-left" size={32} color="#FFFFFF" />
              </Pressable>
              <Pressable
                onPress={handleNext}
                style={styles.navButton}
                accessibilityRole="button"
                accessibilityLabel="Next image"
              >
                <MaterialIcons name="chevron-right" size={32} color="#FFFFFF" />
              </Pressable>
            </View>
          )}

          <View style={styles.zoomControls}>
            <Pressable
              onPress={handleZoomOut}
              disabled={!canZoomOut}
              style={[styles.zoomButton, !canZoomOut && styles.zoomButtonDisabled]}
              accessibilityRole="button"
              accessibilityLabel="Zoom out"
            >
              <MaterialIcons name="remove" size={24} color={canZoomOut ? '#FFFFFF' : '#666666'} />
            </Pressable>
            {showResetZoom && (
              <Pressable
                onPress={handleResetZoom}
                style={styles.zoomButton}
                accessibilityRole="button"
                accessibilityLabel="Reset zoom"
              >
                <MaterialIcons name="crop-free" size={24} color="#FFFFFF" />
              </Pressable>
            )}
            <Pressable
              onPress={handleZoomIn}
              disabled={!canZoomIn}
              style={[styles.zoomButton, !canZoomIn && styles.zoomButtonDisabled]}
              accessibilityRole="button"
              accessibilityLabel="Zoom in"
            >
              <MaterialIcons name="add" size={24} color={canZoomIn ? '#FFFFFF' : '#666666'} />
            </Pressable>
          </View>

          <View style={styles.infoBar}>
            <AppText variant="caption" style={styles.infoText}>
              {currentIndex + 1} of {images.length}
            </AppText>
            {currentImage.fileName && (
              <AppText variant="caption" style={styles.infoText} numberOfLines={1}>
                {currentImage.fileName}
              </AppText>
            )}
          </View>
        </Animated.View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  background: {
    ...StyleSheet.absoluteFillObject,
  },
  mediaStage: {
    position: 'absolute',
    width: SCREEN_WIDTH,
    height: SCREEN_HEIGHT,
    justifyContent: 'center',
    alignItems: 'center',
  },
  imageContainer: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  image: {
    width: '100%',
    height: '100%',
  },
  placeholderContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    gap: 16,
  },
  placeholderText: {
    color: '#FFFFFF',
  },
  controls: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: 'space-between',
  },
  topBar: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
  },
  closeButton: {
    padding: 8,
  },
  pinButton: {
    padding: 8,
  },
  navigation: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    position: 'absolute',
    left: 0,
    right: 0,
    top: '50%',
    transform: [{ translateY: -20 }],
  },
  navButton: {
    padding: 12,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    borderRadius: 999,
  },
  zoomControls: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    gap: 12,
    paddingVertical: 16,
  },
  zoomButton: {
    padding: 12,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    borderRadius: 999,
  },
  zoomButtonDisabled: {
    opacity: 0.5,
  },
  infoBar: {
    alignItems: 'center',
    gap: 4,
    paddingHorizontal: 16,
  },
  infoText: {
    color: '#FFFFFF',
  },
});
