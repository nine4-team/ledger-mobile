import React, {
  useRef,
  useState,
  useCallback,
  useEffect,
  forwardRef,
  useImperativeHandle,
} from 'react';
import { View, Platform } from 'react-native';
import { WebView, type WebViewMessageEvent } from 'react-native-webview';
import { Asset } from 'expo-asset';
import * as FileSystem from 'expo-file-system';

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

export type PdfTextResult = {
  pages: string[];
  fullText: string;
  stats: {
    pageCount: number;
    charCount: number;
    lineCount: number;
    durationMs: number;
  };
};

export type PdfImageResult = {
  dataUri: string;
  pageNumber: number;
  bbox: { xMin: number; yMin: number; xMax: number; yMax: number };
  pageHeight: number;
  score: number;
};

export type PdfExtractionBridgeRef = {
  extractText(fileUri: string): Promise<PdfTextResult>;
  extractImages(
    fileUri: string,
    options?: { minArea?: number },
  ): Promise<PdfImageResult[]>;
  extractTextAndImages(
    fileUri: string,
    options?: { minArea?: number },
  ): Promise<{
    text: PdfTextResult;
    images: PdfImageResult[];
  }>;
  isReady: boolean;
};

// ---------------------------------------------------------------------------
// Internal types
// ---------------------------------------------------------------------------

type PendingRequest = {
  resolve: (value: unknown) => void;
  reject: (reason: unknown) => void;
  timer: ReturnType<typeof setTimeout>;
};

type WebViewResponse = {
  id?: string;
  type: string;
  result?: unknown;
  error?: { message: string; stack?: string };
};

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** Timeout in ms for a single extraction request. */
const REQUEST_TIMEOUT_MS = 30_000;

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

/**
 * A hidden WebView that loads pdfjs-dist and exposes an imperative API for
 * PDF text and image extraction.
 *
 * Usage:
 * ```tsx
 * const bridgeRef = useRef<PdfExtractionBridgeRef>(null);
 *
 * <PdfExtractionBridge ref={bridgeRef} />
 *
 * // Later:
 * const result = await bridgeRef.current?.extractText(documentUri);
 * ```
 */
export const PdfExtractionBridge = forwardRef<PdfExtractionBridgeRef>(
  function PdfExtractionBridge(_props, ref) {
    const webViewRef = useRef<WebView>(null);
    const pendingRequests = useRef<Map<string, PendingRequest>>(new Map());
    const requestCounter = useRef(0);
    const [isReady, setIsReady] = useState(false);
    const [htmlUri, setHtmlUri] = useState<string | null>(null);

    // Load the HTML asset on mount
    useEffect(() => {
      let cancelled = false;
      (async () => {
        try {
          // eslint-disable-next-line @typescript-eslint/no-var-requires
          const [asset] = await Asset.loadAsync(
            require('./pdfExtractionWebView.html'),
          );
          if (!cancelled && asset.localUri) {
            setHtmlUri(asset.localUri);
          }
        } catch (e) {
          console.error('[PdfExtractionBridge] Failed to load HTML asset:', e);
        }
      })();
      return () => {
        cancelled = true;
      };
    }, []);

    // Clean up pending requests on unmount
    useEffect(() => {
      return () => {
        for (const [, pending] of pendingRequests.current) {
          clearTimeout(pending.timer);
          pending.reject(new Error('PdfExtractionBridge unmounted'));
        }
        pendingRequests.current.clear();
      };
    }, []);

    // ------------------------------------------------------------------
    // Generate a unique request ID
    // ------------------------------------------------------------------
    const nextRequestId = useCallback((): string => {
      requestCounter.current += 1;
      return `req-${Date.now()}-${requestCounter.current}`;
    }, []);

    // ------------------------------------------------------------------
    // Send a request to the WebView and return a promise for the response
    // ------------------------------------------------------------------
    const sendRequest = useCallback(
      <T,>(payload: Record<string, unknown>): Promise<T> => {
        return new Promise<T>((resolve, reject) => {
          if (!isReady || !webViewRef.current) {
            reject(
              new Error(
                'PdfExtractionBridge is not ready. Wait for the WebView to load.',
              ),
            );
            return;
          }

          const id = nextRequestId();
          const timer = setTimeout(() => {
            const pending = pendingRequests.current.get(id);
            if (pending) {
              pendingRequests.current.delete(id);
              pending.reject(
                new Error(
                  `PDF extraction timed out after ${REQUEST_TIMEOUT_MS}ms`,
                ),
              );
            }
          }, REQUEST_TIMEOUT_MS);

          pendingRequests.current.set(id, {
            resolve: resolve as (v: unknown) => void,
            reject,
            timer,
          });

          const message = JSON.stringify({ ...payload, id });
          webViewRef.current.postMessage(message);
        });
      },
      [isReady, nextRequestId],
    );

    // ------------------------------------------------------------------
    // Read a file URI to base64
    // ------------------------------------------------------------------
    const readFileAsBase64 = useCallback(
      async (fileUri: string): Promise<string> => {
        const base64 = await FileSystem.readAsStringAsync(fileUri, {
          encoding: FileSystem.EncodingType.Base64,
        });
        return base64;
      },
      [],
    );

    // ------------------------------------------------------------------
    // Imperative API exposed via ref
    // ------------------------------------------------------------------
    useImperativeHandle(
      ref,
      () => ({
        get isReady() {
          return isReady;
        },

        async extractText(fileUri: string): Promise<PdfTextResult> {
          const pdfBase64 = await readFileAsBase64(fileUri);
          return sendRequest<PdfTextResult>({
            type: 'extract-text',
            pdfBase64,
          });
        },

        async extractImages(
          fileUri: string,
          options?: { minArea?: number },
        ): Promise<PdfImageResult[]> {
          const pdfBase64 = await readFileAsBase64(fileUri);
          return sendRequest<PdfImageResult[]>({
            type: 'extract-images',
            pdfBase64,
            imageOptions: options || {},
          });
        },

        async extractTextAndImages(
          fileUri: string,
          options?: { minArea?: number },
        ): Promise<{ text: PdfTextResult; images: PdfImageResult[] }> {
          const pdfBase64 = await readFileAsBase64(fileUri);
          return sendRequest<{
            text: PdfTextResult;
            images: PdfImageResult[];
          }>({
            type: 'extract-text-and-images',
            pdfBase64,
            imageOptions: options || {},
          });
        },
      }),
      [isReady, readFileAsBase64, sendRequest],
    );

    // ------------------------------------------------------------------
    // Handle messages from the WebView
    // ------------------------------------------------------------------
    const handleMessage = useCallback((event: WebViewMessageEvent) => {
      let data: WebViewResponse;
      try {
        data = JSON.parse(event.nativeEvent.data) as WebViewResponse;
      } catch {
        console.warn(
          '[PdfExtractionBridge] Failed to parse WebView message:',
          event.nativeEvent.data,
        );
        return;
      }

      // Handle the "ready" signal from the WebView
      if (data.type === 'ready') {
        setIsReady(true);
        return;
      }

      // Handle initialization errors (no id)
      if (data.type === 'error' && !data.id) {
        console.error(
          '[PdfExtractionBridge] WebView initialization error:',
          data.error?.message,
        );
        return;
      }

      // Handle request responses
      const id = data.id;
      if (!id) return;

      const pending = pendingRequests.current.get(id);
      if (!pending) return;

      pendingRequests.current.delete(id);
      clearTimeout(pending.timer);

      if (data.type === 'error') {
        const errorMessage =
          data.error?.message || 'Unknown PDF extraction error';
        pending.reject(new Error(errorMessage));
      } else {
        pending.resolve(data.result);
      }
    }, []);

    // ------------------------------------------------------------------
    // Handle WebView errors
    // ------------------------------------------------------------------
    const handleError = useCallback(
      (syntheticEvent: { nativeEvent: { description?: string } }) => {
        const { description } = syntheticEvent.nativeEvent;
        console.error(
          '[PdfExtractionBridge] WebView error:',
          description || 'Unknown error',
        );

        // Reject all pending requests on WebView crash
        for (const [id, pending] of pendingRequests.current) {
          clearTimeout(pending.timer);
          pending.reject(
            new Error(`WebView error: ${description || 'Unknown error'}`),
          );
          pendingRequests.current.delete(id);
        }

        setIsReady(false);
      },
      [],
    );

    // Don't render the WebView until we have the HTML asset URI
    if (!htmlUri) {
      return null;
    }

    return (
      <View
        style={{
          width: 0,
          height: 0,
          overflow: 'hidden',
          position: 'absolute',
          opacity: 0,
        }}
        pointerEvents="none"
      >
        <WebView
          ref={webViewRef}
          source={{ uri: htmlUri }}
          originWhitelist={['*']}
          javaScriptEnabled
          domStorageEnabled
          allowFileAccess
          allowFileAccessFromFileURLs
          allowUniversalAccessFromFileURLs
          onMessage={handleMessage}
          onError={handleError}
          onHttpError={(syntheticEvent) => {
            console.warn(
              '[PdfExtractionBridge] WebView HTTP error:',
              syntheticEvent.nativeEvent.statusCode,
            );
          }}
          // Prevent the WebView from being visible or interactive
          scrollEnabled={false}
          bounces={false}
          // Android: run in a separate process for stability
          {...(Platform.OS === 'android' && {
            androidLayerType: 'software',
          })}
        />
      </View>
    );
  },
);
