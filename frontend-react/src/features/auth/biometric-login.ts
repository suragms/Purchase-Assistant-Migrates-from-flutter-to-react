const BIO_EMAIL_KEY = "hexa_biometric_email";

export const BiometricLogin = {
  savedEmail(): string | null {
    try {
      return localStorage.getItem(BIO_EMAIL_KEY);
    } catch {
      return null;
    }
  },
  saveEmail(email: string) {
    try {
      localStorage.setItem(BIO_EMAIL_KEY, email);
    } catch {
      // silently fail
    }
  },
  clear() {
    try {
      localStorage.removeItem(BIO_EMAIL_KEY);
    } catch {
      // silently fail
    }
  },
  isAvailable(): boolean {
    try {
      return (
        typeof window !== "undefined" &&
        typeof window.PublicKeyCredential !== "undefined"
      );
    } catch {
      return false;
    }
  },
};
