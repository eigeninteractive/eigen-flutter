importScripts("https://www.gstatic.com/firebasejs/12.15.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/12.15.0/firebase-messaging-compat.js");
importScripts("firebase-config.js");

firebase.initializeApp(self.firebaseConfig);

firebase.messaging();
