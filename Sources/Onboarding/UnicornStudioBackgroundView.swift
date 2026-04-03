import SwiftUI
import WebKit

struct UnicornStudioBackgroundView: View {
    enum BackgroundStyle: Equatable {
        case dark
        case light
        case clear

        var uiColor: UIColor {
            switch self {
            case .dark:
                return .black
            case .light:
                return .white
            case .clear:
                return .clear
            }
        }

        var cssValue: String {
            switch self {
            case .dark:
                return "#000"
            case .light:
                return "#fff"
            case .clear:
                return "transparent"
            }
        }

        var isOpaque: Bool {
            self != .clear
        }
    }

    enum Source: Equatable {
        case projectID(String)
        case bundledJSON(String)
    }

    let source: Source
    var opacity: Double = 1
    var backgroundStyle: BackgroundStyle = .dark
    var allowsInteraction = false

    var body: some View {
        GeometryReader { proxy in
            let renderSize = CGSize(
                width: max(proxy.size.width.rounded(.up), 1),
                height: max(proxy.size.height.rounded(.up), 1)
            )

            UnicornStudioWebView(
                source: source,
                renderSize: renderSize,
                backgroundStyle: backgroundStyle,
                allowsInteraction: allowsInteraction
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
            .opacity(opacity)
            .clipped()
        }
        .allowsHitTesting(allowsInteraction)
        .accessibilityHidden(true)
    }
}

private struct UnicornStudioWebView: UIViewRepresentable {
    let source: UnicornStudioBackgroundView.Source
    let renderSize: CGSize
    let backgroundStyle: UnicornStudioBackgroundView.BackgroundStyle
    let allowsInteraction: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = backgroundStyle.isOpaque
        webView.backgroundColor = backgroundStyle.uiColor
        webView.scrollView.backgroundColor = backgroundStyle.uiColor
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isUserInteractionEnabled = allowsInteraction
        webView.allowsLinkPreview = false
        webView.navigationDelegate = context.coordinator

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = UnicornStudioEmbedHTML.document(
            source: source,
            renderSize: renderSize,
            backgroundStyle: backgroundStyle,
            allowsInteraction: allowsInteraction
        )

        webView.isOpaque = backgroundStyle.isOpaque
        webView.backgroundColor = backgroundStyle.uiColor
        webView.scrollView.backgroundColor = backgroundStyle.uiColor
        webView.isUserInteractionEnabled = allowsInteraction

        guard context.coordinator.lastHTML != html else {
            context.coordinator.applySize(renderSize, to: webView)
            return
        }

        context.coordinator.lastHTML = html
        context.coordinator.lastAppliedSize = renderSize
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?
        var lastAppliedSize: CGSize = .zero

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applySize(lastAppliedSize, to: webView)
        }

        func applySize(_ size: CGSize, to webView: WKWebView) {
            guard size.width > 1, size.height > 1 else { return }

            let width = Int(size.width.rounded(.up))
            let height = Int(size.height.rounded(.up))
            let js = """
            if (window.__flowApplySize) {
              window.__flowApplySize(\(width), \(height));
            }
            """

            webView.evaluateJavaScript(js, completionHandler: nil)
            lastAppliedSize = size
        }
    }
}

private enum UnicornStudioEmbedHTML {
    static func document(
        source: UnicornStudioBackgroundView.Source,
        renderSize: CGSize,
        backgroundStyle: UnicornStudioBackgroundView.BackgroundStyle,
        allowsInteraction: Bool
    ) -> String {
        let sceneBootScript: String
        let initialWidth = Int(renderSize.width.rounded(.up))
        let initialHeight = Int(renderSize.height.rounded(.up))
        let backgroundColorValue = backgroundStyle.cssValue

        switch source {
        case .projectID(let projectID):
            sceneBootScript = """
              const startScene = function() {
                applySize(\(initialWidth), \(initialHeight));
                if (!window.UnicornStudio?.init) { return; }
                window.UnicornStudio.init();
                requestAnimationFrame(function() {
                  applySize(\(initialWidth), \(initialHeight));
                });
              };
            """

            return baseDocument(
                sceneMarkup: #"<div id="scene" data-us-project="\#(projectID)"></div>"#,
                sceneBootScript: sceneBootScript,
                initialWidth: initialWidth,
                initialHeight: initialHeight,
                backgroundColorValue: backgroundColorValue,
                allowsInteraction: allowsInteraction
            )
        case .bundledJSON(let resourceName):
            guard let sceneJSONString = bundledJSONString(named: resourceName),
                  let encodedJSONString = encodedJavaScriptString(sceneJSONString) else {
                return baseDocument(
                    sceneMarkup: #"<div id="scene"></div>"#,
                    sceneBootScript: "const startScene = function() {};",
                    initialWidth: initialWidth,
                    initialHeight: initialHeight,
                    backgroundColorValue: backgroundColorValue,
                    allowsInteraction: allowsInteraction
                )
            }

            sceneBootScript = """
              const sceneJSONString = \(encodedJSONString);
              const sceneBlob = new Blob([sceneJSONString], { type: "application/json" });
              const sceneURL = URL.createObjectURL(sceneBlob);
              const startScene = function() {
                applySize(\(initialWidth), \(initialHeight));
                if (!window.UnicornStudio?.addScene) { return; }
                window.UnicornStudio.addScene({
                  elementId: "scene",
                  filePath: sceneURL,
                  lazyLoad: false,
                  altText: "Halo background animation",
                  ariaLabel: "Halo background animation"
                });
                requestAnimationFrame(function() {
                  applySize(\(initialWidth), \(initialHeight));
                });
              };
            """

            return baseDocument(
                sceneMarkup: #"<div id="scene"></div>"#,
                sceneBootScript: sceneBootScript,
                initialWidth: initialWidth,
                initialHeight: initialHeight,
                backgroundColorValue: backgroundColorValue,
                allowsInteraction: allowsInteraction
            )
        }
    }

    private static func baseDocument(
        sceneMarkup: String,
        sceneBootScript: String,
        initialWidth: Int,
        initialHeight: Int,
        backgroundColorValue: String,
        allowsInteraction: Bool
    ) -> String {
        let scenePointerEvents = allowsInteraction ? "auto" : "none"
        let sceneTouchAction = allowsInteraction ? "none" : "auto"
        let interactionBootstrap = allowsInteraction ? """
              function createSyntheticTouchEvent(type, clientX, clientY) {
                var scene = document.getElementById("scene");
                if (!scene) { return null; }

                var pageX = clientX + window.scrollX;
                var pageY = clientY + window.scrollY;
                var touchFallback = {
                  identifier: 1,
                  target: scene,
                  clientX: clientX,
                  clientY: clientY,
                  pageX: pageX,
                  pageY: pageY,
                  screenX: clientX,
                  screenY: clientY,
                  radiusX: 1,
                  radiusY: 1,
                  rotationAngle: 0,
                  force: 1
                };
                var activeTouches = (type === "touchend" || type === "touchcancel") ? [] : [touchFallback];

                try {
                  var touch = new Touch(touchFallback);
                  activeTouches = (type === "touchend" || type === "touchcancel") ? [] : [touch];
                  return new TouchEvent(type, {
                    bubbles: true,
                    cancelable: true,
                    touches: activeTouches,
                    targetTouches: activeTouches,
                    changedTouches: [touch]
                  });
                } catch (error) {
                  var fallbackEvent = new Event(type, {
                    bubbles: true,
                    cancelable: true
                  });
                  Object.defineProperty(fallbackEvent, "touches", { value: activeTouches });
                  Object.defineProperty(fallbackEvent, "targetTouches", { value: activeTouches });
                  Object.defineProperty(fallbackEvent, "changedTouches", { value: [activeTouches[0] || touchFallback] });
                  Object.defineProperty(fallbackEvent, "pageX", { value: pageX });
                  Object.defineProperty(fallbackEvent, "pageY", { value: pageY });
                  Object.defineProperty(fallbackEvent, "clientX", { value: clientX });
                  Object.defineProperty(fallbackEvent, "clientY", { value: clientY });
                  return fallbackEvent;
                }
              }

              function relayPointerEvent(type, clientX, clientY) {
                var scene = document.getElementById("scene");
                if (!scene) { return; }

                var baseInit = {
                  clientX: clientX,
                  clientY: clientY,
                  bubbles: true,
                  cancelable: true,
                  view: window
                };

                try {
                  var pointerInit = Object.assign({
                    pointerType: "touch",
                    isPrimary: true,
                    pointerId: 1
                  }, baseInit);
                  scene.dispatchEvent(new PointerEvent(type, pointerInit));
                  window.dispatchEvent(new PointerEvent(type, pointerInit));
                } catch (error) {
                  var mouseType = "mousemove";
                  if (type === "pointerdown") { mouseType = "mousedown"; }
                  if (type === "pointerup" || type === "pointercancel") { mouseType = "mouseup"; }

                  scene.dispatchEvent(new MouseEvent(mouseType, baseInit));
                  window.dispatchEvent(new MouseEvent(mouseType, baseInit));
                }
              }

              function installTouchBridge() {
                var scene = document.getElementById("scene");
                if (!scene) { return; }

                var eventTypeForTouch = function(eventType) {
                  if (eventType === "touchstart") { return "pointerdown"; }
                  if (eventType === "touchend") { return "pointerup"; }
                  if (eventType === "touchcancel") { return "pointercancel"; }
                  return "pointermove";
                };

                var handleTouch = function(event) {
                  var touch = (event.touches && event.touches[0]) || (event.changedTouches && event.changedTouches[0]);
                  if (!touch) { return; }
                  var syntheticTouchEvent = createSyntheticTouchEvent(event.type, touch.clientX, touch.clientY);
                  if (syntheticTouchEvent) {
                    window.dispatchEvent(syntheticTouchEvent);
                  }
                  relayPointerEvent(eventTypeForTouch(event.type), touch.clientX, touch.clientY);
                };

                var touchOptions = { passive: false };
                scene.addEventListener("touchstart", function(event) {
                  event.preventDefault();
                  handleTouch(event);
                }, touchOptions);
                scene.addEventListener("touchmove", function(event) {
                  event.preventDefault();
                  handleTouch(event);
                }, touchOptions);
                scene.addEventListener("touchend", function(event) {
                  event.preventDefault();
                  handleTouch(event);
                }, touchOptions);
                scene.addEventListener("touchcancel", function(event) {
                  event.preventDefault();
                  handleTouch(event);
                }, touchOptions);
              }
        """ : ""

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta
            name="viewport"
            content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover"
          >
          <style>
            :root {
              --scene-width: \(initialWidth)px;
              --scene-height: \(initialHeight)px;
            }

            html, body {
              margin: 0;
              width: var(--scene-width);
              height: var(--scene-height);
              overflow: hidden;
              background: \(backgroundColorValue);
            }

            body {
              background: \(backgroundColorValue) !important;
              position: fixed;
              inset: 0;
            }

            #scene {
              position: fixed;
              inset: 0;
              width: var(--scene-width);
              height: var(--scene-height);
              pointer-events: \(scenePointerEvents);
              touch-action: \(sceneTouchAction);
              background: \(backgroundColorValue);
              overflow: hidden;
            }

            canvas {
              background: \(backgroundColorValue) !important;
              pointer-events: \(scenePointerEvents);
            }
          </style>
        </head>
        <body>
          \(sceneMarkup)
          <script type="text/javascript">
            !function(){
              function applySize(width, height) {
                var scene = document.getElementById("scene");
                var widthPx = width + "px";
                var heightPx = height + "px";

                document.documentElement.style.setProperty("--scene-width", widthPx);
                document.documentElement.style.setProperty("--scene-height", heightPx);
                document.documentElement.style.width = widthPx;
                document.documentElement.style.height = heightPx;
                document.body.style.width = widthPx;
                document.body.style.height = heightPx;

                if (scene) {
                  scene.style.width = widthPx;
                  scene.style.height = heightPx;
                }

                requestAnimationFrame(function() {
                  window.dispatchEvent(new Event("resize"));
                });
              }

              window.__flowApplySize = applySize;
              applySize(\(initialWidth), \(initialHeight));

              \(interactionBootstrap)
              \(sceneBootScript)

              var u = window.UnicornStudio;
              function boot() {
                \(allowsInteraction ? "installTouchBridge();" : "")
                startScene();
              }

              if (u && u.init) {
                if (document.readyState === "loading") {
                  document.addEventListener("DOMContentLoaded", boot);
                } else {
                  boot();
                }
              } else {
                window.UnicornStudio = { isInitialized: false };
                var i = document.createElement("script");
                i.src = "https://cdn.jsdelivr.net/gh/hiunicornstudio/unicornstudio.js@v2.1.6/dist/unicornStudio.umd.js";
                i.onload = function() {
                  u = window.UnicornStudio;
                  if (document.readyState === "loading") {
                    document.addEventListener("DOMContentLoaded", boot);
                  } else {
                    boot();
                  }
                };
                (document.head || document.body).appendChild(i);
              }
            }();
          </script>
        </body>
        </html>
        """
    }

    private static func bundledJSONString(named resourceName: String) -> String? {
        guard let resourceURL = Bundle.main.url(forResource: resourceName, withExtension: nil) else {
            return nil
        }
        return try? String(contentsOf: resourceURL, encoding: .utf8)
    }

    private static func encodedJavaScriptString(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        return encoded
    }
}
