"use client";

import { useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
  LuArrowLeft,
  LuKeyRound,
  LuTrash2,
  LuSave,
} from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import {
  getUser,
  updateUser,
  deleteUser,
  resetUserPassword,
} from "../../lib/api/settings";
import type { UserPatchIn } from "../../lib/api/types";
import { Card } from "../../components/ui/Card";
import { Button } from "../../components/ui/Button";
import { Input } from "../../components/ui/Input";

function getRoleBadgeColor(role: string) {
  switch (role) {
    case "owner":
      return "bg-purple-100 text-purple-700";
    case "admin":
      return "bg-blue-100 text-blue-700";
    case "manager":
      return "bg-amber-100 text-amber-700";
    default:
      return "bg-gray-100 text-gray-600";
  }
}

function formatLastActive(iso: string | null): string {
  if (!iso) return "Never";
  const d = new Date(iso);
  const now = new Date();
  const diffMs = now.getTime() - d.getTime();
  const diffMin = Math.floor(diffMs / 60000);
  if (diffMin < 1) return "Just now";
  if (diffMin < 60) return `${diffMin}m ago`;
  const diffHr = Math.floor(diffMin / 60);
  if (diffHr < 24) return `${diffHr}h ago`;
  const diffDay = Math.floor(diffHr / 24);
  if (diffDay < 7) return `${diffDay}d ago`;
  return d.toLocaleDateString();
}

export default function UserProfilePage() {
  const navigate = useNavigate();
  const { userId } = useParams();
  const queryClient = useQueryClient();
  const { businessId, isOwner } = useAuthStore();

  const [editing, setEditing] = useState(false);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [role, setRole] = useState("");
  const [notes, setNotes] = useState("");
  const [credentialDialog, setCredentialDialog] = useState<{
    email: string;
    password: string;
  } | null>(null);
  const [confirmDelete, setConfirmDelete] = useState(false);

  const { data: user, isLoading } = useQuery({
    queryKey: ["user", businessId, userId],
    queryFn: () => getUser(businessId!, userId!),
    enabled: !!businessId && !!userId,
  });

  const patchMutation = useMutation({
    mutationFn: (data: UserPatchIn) => updateUser(businessId!, userId!, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["users"] });
      queryClient.invalidateQueries({ queryKey: ["user"] });
      setEditing(false);
    },
  });

  const resetPasswordMutation = useMutation({
    mutationFn: () => resetUserPassword(businessId!, userId!),
    onSuccess: (data) => {
      setCredentialDialog({
        email: data.login_email || "",
        password: data.new_password,
      });
    },
  });

  const deleteMutation = useMutation({
    mutationFn: () => deleteUser(businessId!, userId!),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["users"] });
      navigate("/settings/users");
    },
  });

  const startEditing = () => {
    if (!user) return;
    setName(user.name || "");
    setEmail(user.email || "");
    setPhone(user.phone || "");
    setRole(user.role || "staff");
    setNotes(user.notes || "");
    setEditing(true);
  };

  const handleSave = () => {
    patchMutation.mutate({
      full_name: name.trim() || null,
      email: email.trim() || null,
      phone: phone.trim() || null,
      role: role || null,
      notes: notes.trim() || null,
    });
  };

  if (isLoading) {
    return (
      <div className="min-h-screen bg-brand-background">
        <div className="sticky top-0 z-10 bg-brand-background border-b border-[rgba(215,231,227,0.42)]">
          <div className="flex items-center gap-3 px-4 py-3">
            <button
              onClick={() => navigate(-1)}
              className="p-2 -ml-2 rounded-xl hover:bg-brand-primary/10 text-brand-primary"
            >
              <LuArrowLeft size={20} />
            </button>
            <h1 className="text-lg font-bold text-text-primary">User profile</h1>
          </div>
        </div>
        <div className="px-4 py-4 max-w-2xl mx-auto">
          <Card padding="lg">
            <div className="animate-pulse space-y-4">
              <div className="flex gap-3">
                <div className="w-12 h-12 rounded-full bg-gray-200" />
                <div className="flex-1 space-y-2">
                  <div className="h-5 bg-gray-200 rounded w-1/3" />
                  <div className="h-4 bg-gray-200 rounded w-1/2" />
                </div>
              </div>
              <div className="h-4 bg-gray-200 rounded w-2/3" />
              <div className="h-4 bg-gray-200 rounded w-1/2" />
            </div>
          </Card>
        </div>
      </div>
    );
  }

  if (!user) {
    return (
      <div className="min-h-screen bg-brand-background">
        <div className="sticky top-0 z-10 bg-brand-background border-b border-[rgba(215,231,227,0.42)]">
          <div className="flex items-center gap-3 px-4 py-3">
            <button
              onClick={() => navigate(-1)}
              className="p-2 -ml-2 rounded-xl hover:bg-brand-primary/10 text-brand-primary"
            >
              <LuArrowLeft size={20} />
            </button>
            <h1 className="text-lg font-bold text-text-primary">User profile</h1>
          </div>
        </div>
        <div className="px-4 py-4 max-w-2xl mx-auto">
          <Card padding="lg">
            <p className="text-center text-text-muted">User not found.</p>
          </Card>
        </div>
      </div>
    );
  }

  const isOwnerUser = user.role === "owner";

  return (
    <div className="min-h-screen bg-brand-background">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-brand-background border-b border-[rgba(215,231,227,0.42)]">
        <div className="flex items-center gap-3 px-4 py-3">
          <button
            onClick={() => navigate(-1)}
            className="p-2 -ml-2 rounded-xl hover:bg-brand-primary/10 text-brand-primary"
          >
            <LuArrowLeft size={20} />
          </button>
          <h1 className="text-lg font-bold text-text-primary flex-1">
            {editing ? "Edit user" : "User profile"}
          </h1>
          {!editing && isOwner && !isOwnerUser && (
            <Button variant="outline" size="sm" onClick={startEditing}>
              Edit
            </Button>
          )}
        </div>
      </div>

      <div className="px-4 py-4 max-w-2xl mx-auto space-y-4">
        {/* Profile Card */}
        <Card padding="md">
          <div className="flex items-center gap-3 mb-4">
            <div className="w-12 h-12 rounded-full bg-brand-primary/10 flex items-center justify-center">
              <span className="text-brand-primary font-bold text-lg">
                {(user.name || user.email || "?").charAt(0).toUpperCase()}
              </span>
            </div>
            <div className="flex-1 min-w-0">
              {editing ? (
                <Input
                  label="Full name"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                />
              ) : (
                <>
                  <p className="font-semibold text-text-primary">{user.name || "—"}</p>
                  <span
                    className={`text-[10px] font-medium px-1.5 py-0.5 rounded-full ${getRoleBadgeColor(user.role)}`}
                  >
                    {user.role}
                  </span>
                </>
              )}
            </div>
          </div>

          <div className="space-y-3">
            {editing ? (
              <>
                <Input
                  label="Email"
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                />
                <Input
                  label="Phone"
                  type="tel"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                />
                <div>
                  <label className="block text-sm font-medium text-text-primary mb-1.5">
                    Role
                  </label>
                  <select
                    value={role}
                    onChange={(e) => setRole(e.target.value)}
                    className="w-full rounded-xl border border-brand-border bg-brand-surface px-3 py-2.5 text-sm text-text-primary focus:border-brand-primary focus:ring-1 focus:ring-brand-primary outline-none"
                  >
                    <option value="staff">Staff</option>
                    <option value="manager">Manager</option>
                    <option value="admin">Admin</option>
                  </select>
                </div>
                <Input
                  label="Notes"
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                />
              </>
            ) : (
              <>
                {user.email && (
                  <div>
                    <p className="text-xs text-text-muted">Email</p>
                    <p className="text-sm text-text-primary">{user.email}</p>
                  </div>
                )}
                {user.phone && (
                  <div>
                    <p className="text-xs text-text-muted">Phone</p>
                    <p className="text-sm text-text-primary">{user.phone}</p>
                  </div>
                )}
                {user.warehouse_name && (
                  <div>
                    <p className="text-xs text-text-muted">Warehouse</p>
                    <p className="text-sm text-text-primary">{user.warehouse_name}</p>
                  </div>
                )}
                {user.notes && (
                  <div>
                    <p className="text-xs text-text-muted">Notes</p>
                    <p className="text-sm text-text-primary">{user.notes}</p>
                  </div>
                )}
              </>
            )}
          </div>
        </Card>

        {/* Stats Card */}
        {!editing && (
          <Card padding="md">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-xs text-text-muted">Status</p>
                <p
                  className={`text-sm font-medium ${
                    user.is_blocked
                      ? "text-red-600"
                      : user.is_active
                        ? "text-green-600"
                        : "text-gray-500"
                  }`}
                >
                  {user.is_blocked
                    ? "Blocked"
                    : user.is_active
                      ? "Active"
                      : "Inactive"}
                </p>
              </div>
              <div>
                <p className="text-xs text-text-muted">Last active</p>
                <p className="text-sm text-text-primary">
                  {formatLastActive(user.last_active_at)}
                </p>
              </div>
              <div>
                <p className="text-xs text-text-muted">Today's purchases</p>
                <p className="text-sm text-text-primary">
                  {user.today_stats?.purchases_count ?? 0}
                </p>
              </div>
              <div>
                <p className="text-xs text-text-muted">7-day activity</p>
                <p className="text-sm text-text-primary">{user.activity_count_7d}</p>
              </div>
            </div>
          </Card>
        )}

        {/* Actions */}
        {editing ? (
          <div className="flex gap-3">
            <Button
              variant="outline"
              onClick={() => setEditing(false)}
              className="flex-1"
            >
              Cancel
            </Button>
            <Button
              onClick={handleSave}
              disabled={patchMutation.isPending}
              className="flex-1 gap-1.5"
            >
              <LuSave size={16} />
              {patchMutation.isPending ? "Saving…" : "Save"}
            </Button>
          </div>
        ) : (
          isOwner &&
          !isOwnerUser && (
            <Card padding="sm">
              <Button
                variant="outline"
                onClick={() => resetPasswordMutation.mutate()}
                disabled={resetPasswordMutation.isPending}
                className="w-full gap-1.5"
              >
                <LuKeyRound size={16} />
                {resetPasswordMutation.isPending
                  ? "Resetting…"
                  : "Reset password"}
              </Button>
              {!confirmDelete ? (
                <Button
                  variant="outline"
                  onClick={() => setConfirmDelete(true)}
                  className="w-full mt-2 gap-1.5 text-red-600 border-red-300 hover:bg-red-50"
                >
                  <LuTrash2 size={16} />
                  Delete user
                </Button>
              ) : (
                <div className="flex gap-2 mt-2">
                  <Button
                    variant="outline"
                    onClick={() => setConfirmDelete(false)}
                    className="flex-1"
                  >
                    Cancel
                  </Button>
                  <Button
                    onClick={() => deleteMutation.mutate()}
                    disabled={deleteMutation.isPending}
                    className="flex-1 gap-1.5 bg-red-600 hover:bg-red-700"
                  >
                    <LuTrash2 size={16} />
                    Confirm
                  </Button>
                </div>
              )}
            </Card>
          )
        )}
      </div>

      {/* Credential Dialog */}
      {credentialDialog && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40">
          <div className="bg-white rounded-2xl shadow-xl max-w-sm w-full mx-4 p-6">
            <h3 className="text-lg font-bold text-text-primary mb-3">
              New credentials
            </h3>
            <div className="space-y-1 mb-4">
              <p className="text-sm">
                <span className="text-text-muted">Email: </span>
                <span className="font-medium">{credentialDialog.email}</span>
              </p>
              <p className="text-sm">
                <span className="text-text-muted">Password: </span>
                <span className="font-bold">{credentialDialog.password}</span>
              </p>
            </div>
            <div className="flex gap-2">
              <Button
                variant="outline"
                className="flex-1"
                onClick={() => {
                  navigator.clipboard.writeText(
                    `Email: ${credentialDialog.email}\nPassword: ${credentialDialog.password}`,
                  );
                }}
              >
                Copy
              </Button>
              <Button
                className="flex-1"
                onClick={() => setCredentialDialog(null)}
              >
                Done
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
