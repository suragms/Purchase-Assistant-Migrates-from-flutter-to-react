import { api } from "./client";
import type {
  BusinessBrief,
  BusinessBrandingPatch,
  UserListOut,
  UserProfileOut,
  UserCreateIn,
  UserCreateOut,
  UserPatchIn,
  UserBulkIn,
  UserBulkOut,
  ResetPasswordOut,
  UserProfile,
} from "./types";

// ---- Current User Profile ----

export async function getMyProfile(): Promise<UserProfile> {
  const res = await api.get("/me/profile");
  return res.data;
}

export async function updateMyProfile(data: { name?: string }): Promise<UserProfile> {
  const res = await api.patch("/me/profile", data);
  return res.data;
}

// ---- Business Profile ----

export async function listBusinesses(): Promise<BusinessBrief[]> {
  const res = await api.get("/me/businesses");
  return res.data;
}

export async function updateBusinessBranding(
  businessId: string,
  data: BusinessBrandingPatch,
): Promise<BusinessBrief> {
  const res = await api.patch(`/me/businesses/${businessId}/branding`, data);
  return res.data;
}

export async function uploadBusinessLogo(
  businessId: string,
  file: File,
): Promise<BusinessBrief> {
  const formData = new FormData();
  formData.append("file", file);
  const res = await api.post(`/me/businesses/${businessId}/branding/logo`, formData, {
    headers: { "Content-Type": "multipart/form-data" },
  });
  return res.data;
}

// ---- User Management ----

export async function listUsers(
  businessId: string,
  includeInactive?: boolean,
): Promise<UserListOut[]> {
  const res = await api.get(`/businesses/${businessId}/users`, {
    params: includeInactive ? { include_inactive: true } : undefined,
  });
  return res.data;
}

export async function getUser(
  businessId: string,
  userId: string,
): Promise<UserProfileOut> {
  const res = await api.get(`/businesses/${businessId}/users/${userId}`);
  return res.data;
}

export async function createUser(
  businessId: string,
  data: UserCreateIn,
): Promise<UserCreateOut> {
  const res = await api.post(`/businesses/${businessId}/users`, data);
  return res.data;
}

export async function updateUser(
  businessId: string,
  userId: string,
  data: UserPatchIn,
): Promise<UserListOut> {
  const res = await api.patch(`/businesses/${businessId}/users/${userId}`, data);
  return res.data;
}

export async function deleteUser(
  businessId: string,
  userId: string,
): Promise<void> {
  await api.delete(`/businesses/${businessId}/users/${userId}`);
}

export async function resetUserPassword(
  businessId: string,
  userId: string,
): Promise<ResetPasswordOut> {
  const res = await api.post(`/businesses/${businessId}/users/${userId}/reset-password`);
  return res.data;
}

export async function bulkUsers(
  businessId: string,
  data: UserBulkIn,
): Promise<UserBulkOut> {
  const res = await api.post(`/businesses/${businessId}/users/bulk`, data);
  return res.data;
}

// ---- Exports / Backup ----

export async function downloadStockExcel(businessId: string): Promise<Blob> {
  const res = await api.get(`/businesses/${businessId}/exports/stock-inventory.xlsx`, {
    responseType: "blob",
  });
  return res.data;
}

export async function downloadPurchasesPdf(businessId: string): Promise<Blob> {
  const res = await api.get(`/businesses/${businessId}/exports/purchases-month.pdf`, {
    responseType: "blob",
  });
  return res.data;
}

export async function downloadJsonBackup(businessId: string): Promise<Blob> {
  const res = await api.get(`/businesses/${businessId}/exports/backup/export`, {
    responseType: "blob",
  });
  return res.data;
}

export async function downloadZipBackup(
  businessId: string,
  rangePreset: "month" | "quarter" | "all" = "month",
): Promise<Blob> {
  const res = await api.post(
    `/businesses/${businessId}/exports/backup`,
    { range_preset: rangePreset },
    { responseType: "blob" },
  );
  return res.data;
}
