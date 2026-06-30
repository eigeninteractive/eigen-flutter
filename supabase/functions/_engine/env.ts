export interface FirebaseEnv {
  clientEmail: string;
  projectId: string;
  key: string;
}

export const getFirebaseEnv = () => {
  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL");
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID");
  const key = Deno.env.get("FIREBASE_PRIVATE_KEY");
  if (!clientEmail || !projectId || !key) return null;
  return { clientEmail, projectId, key } as FirebaseEnv;
};
