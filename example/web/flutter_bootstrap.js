{{flutter_js}}
{{flutter_build_config}}

(async () => {
  if ("serviceWorker" in navigator) {
    await navigator.serviceWorker
      .register("firebase-messaging-sw.js", {
        scope: "/firebase-cloud-messaging-push-scope",
      })
      .catch((error) => {
        console.warn(
          "Firebase Messaging service worker registration failed",
          error,
        );
      });
  }

  _flutter.loader.load();
})();
