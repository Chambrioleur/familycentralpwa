// Vorlage für die Zugangsdaten. Zum Einrichten:
//
//   cp frontend/config.example.js frontend/config.js
//
// Dann in config.js die eigenen Werte eintragen. config.js ist per .gitignore
// vom Repo ausgeschlossen und muss beim Netlify-Deploy mit hochgeladen werden.
//
// Beide Werte hier sind öffentlich unkritisch: der anon key ist für den Einsatz
// im Browser gedacht und durch Row Level Security abgesichert, der VAPID-Public-Key
// ist ohnehin öffentlich. Der private VAPID-Schlüssel gehört NICHT hierher, der
// liegt ausschliesslich als Supabase-Secret bei den Edge Functions.
window.FZ_CONFIG = {
  // Project Settings → API → Project URL
  SUPABASE_URL: "https://EURE-PROJEKT-ID.supabase.co",

  // Project Settings → API → anon public
  SUPABASE_ANON_KEY: "EUER_ANON_KEY",

  // Siehe README Schritt 6 (VAPID-Schlüsselpaar), hier der PUBLIC Key.
  // Leer lassen, wenn keine Push-Benachrichtigungen genutzt werden.
  VAPID_PUBLIC_KEY: "EUER_VAPID_PUBLIC_KEY",
};
