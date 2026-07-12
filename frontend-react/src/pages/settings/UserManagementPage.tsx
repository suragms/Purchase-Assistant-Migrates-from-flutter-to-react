"use client";

import { useState, useCallback } from "react";
import { useNavigate } from "react-router-dom";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
  LuArrowLeft,
  LuSearch,
  LuPlus,
  LuRefreshCw,
  LuMoreVertical,
  LuUser,
  LuKeyRound,
  LuCopy,
  LuTrash2,
  LuCheck,
  LuX,
} from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import {
  listUsers,
  createUser,
  deleteUser,
  resetUserPassword,
  bulkUsers,
} from "../../lib/api/settings";
import type { UserListOut, UserCreateIn } from "../../lib/api/types";
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

function getStatus(user: UserListOut) {
  if (user.is_blocked) return { label: "Blocked", color: "text-red-600" };
  if (!user.is_active) return { label: "Inactive", color: "text-gray-500" };
  return { label: "Active", color: "text-green-600" };
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

export default function UserManagementPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { businessId, isOwner } = useAuthStore();

  const [search, setSearch] = useState("");
  const [roleFilter, setRoleFilter] = useState<string | null>(null);
  const [selectMode, setSelectMode] = useState(false);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [showCreateSheet, setShowCreateSheet] = useState(false);
  const [actionMenuId, setActionMenuId] = useState<string | null>(null);
  const [credentialDialog, setCredentialDialog] = useState<{
    name: string;
    email: string;
    password: string;
    phone?: string;
  } | null>(null);

  const canAdmin = isOwner;

  const { data: users, isLoading } = useQuery({
    queryKey: ["users", businessId],
    queryFn: () => listUsers(businessId!),
    enabled: !!businessId,
  });

  const filtered = (users || []).filter((u) => {
    const matchesSearch =
      !search ||
      u.name?.toLowerCase().includes(search.toLowerCase()) ||
      u.email.toLowerCase().includes(search.toLowerCase());
    const matchesRole = !roleFilter || u.role === roleFilter;
    return matchesSearch && matchesRole;
  });

  const toggleSelect = useCallback((id: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const bulkMutation = useMutation({
    mutationFn: (action: "activate" | "deactivate" | "block" | "delete") =>
      bulkUsers(businessId!, {
        user_ids: Array.from(selected),
        action,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["users"] });
      setSelected(new Set());
      setSelectMode(false);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (userId: string) => deleteUser(businessId!, userId),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["users"] }),
  });

  const resetPasswordMutation = useMutation({
    mutationFn: ({ userId }: { userId: string; userName: string; userPhone: string }) =>
      resetUserPassword(businessId!, userId),
    onSuccess: (data, variables) => {
      setCredentialDialog({
        name: variables.userName || "User",
        email: data.login_email || "",
        password: data.new_password,
        phone: variables.userPhone,
      });
    },
  });

  return (
    <div className="min-h-screen bg-brand-background">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-brand-background border-b border-[rgba(215,231,227,0.42)]">
        <div className="flex items-center gap-3 px-4 py-3">
          <button
            onClick={() => {
              if (selectMode) {
                setSelectMode(false);
                setSelected(new Set());
              } else {
                navigate(-1);
              }
            }}
            className="p-2 -ml-2 rounded-xl hover:bg-brand-primary/10 text-brand-primary"
          >
            {selectMode ? <LuX size={20} /> : <LuArrowLeft size={20} />}
          </button>
          <h1 className="text-lg font-bold text-text-primary flex-1">
            {selectMode ? `${selected.size} selected` : "Users"}
          </h1>
          {canAdmin && (
            <button
              onClick={() => {
                setSelectMode(!selectMode);
                if (selectMode) setSelected(new Set());
              }}
              className="p-2 rounded-xl hover:bg-brand-primary/10 text-brand-primary"
            >
              {selectMode ? <LuCheck size={20} /> : <LuUser size={20} />}
            </button>
          )}
          <button
            onClick={() => queryClient.invalidateQueries({ queryKey: ["users"] })}
            className="p-2 rounded-xl hover:bg-brand-primary/10 text-brand-primary"
          >
            <LuRefreshCw size={18} />
          </button>
          {canAdmin && !selectMode && (
            <Button
              onClick={() => setShowCreateSheet(true)}
              size="sm"
              className="gap-1.5"
            >
              <LuPlus size={16} />
              Add
            </Button>
          )}
        </div>
      </div>

      {/* Bulk Actions Bar */}
      {selectMode && canAdmin && selected.size > 0 && (
        <div className="px-4 py-2 bg-brand-surface border-b border-brand-border flex gap-2 flex-wrap justify-center">
          <Button
            size="sm"
            variant="outline"
            onClick={() => bulkMutation.mutate("activate")}
          >
            Activate
          </Button>
          <Button
            size="sm"
            variant="outline"
            onClick={() => bulkMutation.mutate("deactivate")}
          >
            Deactivate
          </Button>
          <Button
            size="sm"
            variant="outline"
            onClick={() => bulkMutation.mutate("block")}
          >
            Block
          </Button>
          <Button
            size="sm"
            variant="outline"
            onClick={() => bulkMutation.mutate("delete")}
            className="text-red-600 border-red-300 hover:bg-red-50"
          >
            Delete
          </Button>
        </div>
      )}

      <div className="px-4 py-3 space-y-3 max-w-2xl mx-auto">
        {/* Search */}
        <div className="relative">
          <LuSearch
            size={16}
            className="absolute left-3 top-1/2 -translate-y-1/2 text-text-muted"
          />
          <input
            type="text"
            placeholder="Search users…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-9 pr-3 py-2.5 rounded-xl border border-brand-border bg-brand-surface text-sm text-text-primary placeholder:text-text-muted focus:border-brand-primary focus:ring-1 focus:ring-brand-primary outline-none"
          />
        </div>

        {/* Role Filter Chips */}
        <div className="flex gap-2 flex-wrap">
          {[
            { value: null, label: "All" },
            { value: "staff", label: "Staff" },
            { value: "manager", label: "Manager" },
            { value: "admin", label: "Admin" },
            { value: "owner", label: "Owner" },
          ].map((r) => (
            <button
              key={r.value ?? "all"}
              onClick={() => setRoleFilter(r.value)}
              className={`px-3 py-1 rounded-full text-xs font-medium transition-colors ${
                roleFilter === r.value
                  ? "bg-brand-primary text-white"
                  : "bg-brand-surface border border-brand-border text-text-muted hover:border-brand-primary/40"
              }`}
            >
              {r.label}
            </button>
          ))}
        </div>

        {/* User List */}
        {isLoading ? (
          <div className="space-y-3">
            {[1, 2, 3].map((i) => (
              <Card key={i} padding="md">
                <div className="animate-pulse flex gap-3">
                  <div className="w-10 h-10 rounded-full bg-gray-200" />
                  <div className="flex-1 space-y-2">
                    <div className="h-4 bg-gray-200 rounded w-1/3" />
                    <div className="h-3 bg-gray-200 rounded w-1/2" />
                  </div>
                </div>
              </Card>
            ))}
          </div>
        ) : filtered.length === 0 ? (
          <Card padding="lg">
            <p className="text-center text-text-muted">No users match your filters.</p>
          </Card>
        ) : (
          <div className="space-y-2">
            {filtered.map((user) => {
              const status = getStatus(user);
              const isSelected = selected.has(user.id);
              return (
                <Card
                  key={user.id}
                  padding="md"
                  className={`transition-colors ${
                    selectMode
                      ? isSelected
                        ? "ring-2 ring-brand-primary bg-brand-primary/5"
                        : ""
                      : "hover:shadow-sm cursor-pointer"
                  }`}
                  onClick={() => {
                    if (selectMode) {
                      toggleSelect(user.id);
                    } else {
                      navigate(`/settings/users/${user.id}`);
                    }
                  }}
                >
                  <div className="flex items-start gap-3">
                    {selectMode && (
                      <div className="pt-1">
                        <div
                          className={`w-5 h-5 rounded border-2 flex items-center justify-center ${
                            isSelected
                              ? "bg-brand-primary border-brand-primary"
                              : "border-gray-300"
                          }`}
                        >
                          {isSelected && <LuCheck size={12} className="text-white" />}
                        </div>
                      </div>
                    )}
                    <div className="w-10 h-10 rounded-full bg-brand-primary/10 flex items-center justify-center flex-shrink-0">
                      <span className="text-brand-primary font-bold text-sm">
                        {(user.name || user.email || "?").charAt(0).toUpperCase()}
                      </span>
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="font-semibold text-sm text-text-primary truncate">
                          {user.name || "—"}
                        </span>
                        <span
                          className={`text-[10px] font-medium px-1.5 py-0.5 rounded-full ${getRoleBadgeColor(user.role)}`}
                        >
                          {user.role}
                        </span>
                      </div>
                      <p className="text-xs text-text-muted truncate">{user.email}</p>
                      <div className="flex items-center gap-3 mt-1">
                        <span className="text-[10px] text-text-muted">
                          Last active: {formatLastActive(user.last_active_at)}
                        </span>
                        <span className={`text-[10px] font-medium ${status.color}`}>
                          {status.label}
                        </span>
                      </div>
                    </div>
                    {canAdmin && !selectMode && (
                      <div className="relative">
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            setActionMenuId(
                              actionMenuId === user.id ? null : user.id,
                            );
                          }}
                          className="p-1.5 rounded-lg hover:bg-gray-100"
                        >
                          <LuMoreVertical size={16} className="text-text-muted" />
                        </button>
                        {actionMenuId === user.id && (
                          <>
                            <div
                              className="fixed inset-0 z-10"
                              onClick={() => setActionMenuId(null)}
                            />
                            <div className="absolute right-0 top-full mt-1 z-20 bg-white rounded-xl shadow-lg border border-brand-border py-1 min-w-[160px]">
                              <button
                                onClick={(e) => {
                                  e.stopPropagation();
                                  setActionMenuId(null);
                                  navigate(`/settings/users/${user.id}`);
                                }}
                                className="w-full px-3 py-2 text-left text-sm hover:bg-gray-50 flex items-center gap-2"
                              >
                                <LuUser size={14} />
                                View profile
                              </button>
                              <button
                                onClick={(e) => {
                                  e.stopPropagation();
                                  setActionMenuId(null);
                                  resetPasswordMutation.mutate({
                                    userId: user.id,
                                    userName: user.name || "",
                                    userPhone: user.phone || "",
                                  });
                                }}
                                className="w-full px-3 py-2 text-left text-sm hover:bg-gray-50 flex items-center gap-2"
                              >
                                <LuKeyRound size={14} />
                                Reset password
                              </button>
                              {user.role !== "owner" && (
                                <>
                                  <button
                                    onClick={(e) => {
                                      e.stopPropagation();
                                      setActionMenuId(null);
                                      navigator.clipboard.writeText(user.email);
                                    }}
                                    className="w-full px-3 py-2 text-left text-sm hover:bg-gray-50 flex items-center gap-2"
                                  >
                                    <LuCopy size={14} />
                                    Copy email
                                  </button>
                                  <button
                                    onClick={(e) => {
                                      e.stopPropagation();
                                      setActionMenuId(null);
                                      deleteMutation.mutate(user.id);
                                    }}
                                    className="w-full px-3 py-2 text-left text-sm hover:bg-red-50 text-red-600 flex items-center gap-2"
                                  >
                                    <LuTrash2 size={14} />
                                    Delete
                                  </button>
                                </>
                              )}
                            </div>
                          </>
                        )}
                      </div>
                    )}
                  </div>
                </Card>
              );
            })}
          </div>
        )}
      </div>

      {/* Create User Bottom Sheet */}
      {showCreateSheet && (
        <CreateUserSheet
          businessId={businessId!}
          onClose={() => setShowCreateSheet(false)}
          onCreated={(creds) => {
            setShowCreateSheet(false);
            queryClient.invalidateQueries({ queryKey: ["users"] });
            if (creds) {
              setCredentialDialog(creds);
            }
          }}
        />
      )}

      {/* Credential Dialog */}
      {credentialDialog && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40">
          <div className="bg-white rounded-2xl shadow-xl max-w-sm w-full mx-4 p-6">
            <h3 className="text-lg font-bold text-text-primary mb-3">
              Share credentials
            </h3>
            <div className="space-y-1 mb-4">
              <p className="text-sm">
                <span className="text-text-muted">Name: </span>
                <span className="font-medium">{credentialDialog.name}</span>
              </p>
              <p className="text-sm">
                <span className="text-text-muted">Email: </span>
                <span className="font-medium">{credentialDialog.email}</span>
              </p>
              <p className="text-sm">
                <span className="text-text-muted">Password: </span>
                <span className="font-bold">{credentialDialog.password}</span>
              </p>
              {credentialDialog.phone && (
                <p className="text-sm">
                  <span className="text-text-muted">Phone: </span>
                  <span className="font-medium">{credentialDialog.phone}</span>
                </p>
              )}
            </div>
            <div className="flex gap-2">
              <Button
                variant="outline"
                className="flex-1"
                onClick={() => {
                  const lines = [
                    "Harisree workspace login",
                    `Name: ${credentialDialog.name}`,
                    `Email: ${credentialDialog.email}`,
                    `Password: ${credentialDialog.password}`,
                  ];
                  if (credentialDialog.phone) {
                    lines.push(`Phone: ${credentialDialog.phone}`);
                  }
                  navigator.clipboard.writeText(lines.join("\n"));
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

function CreateUserSheet({
  businessId,
  onClose,
  onCreated,
}: {
  businessId: string;
  onClose: () => void;
  onCreated: (creds: { name: string; email: string; password: string; phone?: string } | null) => void;
}) {
  const queryClient = useQueryClient();
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [role, setRole] = useState("staff");
  const [password, setPassword] = useState("");
  const [notes, setNotes] = useState("");
  const [isActive, setIsActive] = useState(true);
  const [formError, setFormError] = useState<string | null>(null);

  const createMutation = useMutation({
    mutationFn: (data: UserCreateIn) => createUser(businessId, data),
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ["users"] });
      const gen = data.generated_password;
      const pwd = gen || (password.trim() || null);
      if (pwd) {
        onCreated({
          name: data.user.name || "User",
          email: data.login_email || data.user.email,
          password: pwd,
          phone: phone.trim() || undefined,
        });
      } else {
        onCreated(null);
      }
    },
    onError: (error: any) => {
      const status = error?.response?.status;
      const detail = error?.response?.data?.detail;
      if (status === 409) {
        setFormError("A user with this email or phone already exists.");
      } else if (status === 400) {
        setFormError(typeof detail === "string" ? detail : "Invalid input. Check fields and try again.");
      } else {
        setFormError("Something went wrong. Please try again.");
      }
    },
  });

  const handleSubmit = () => {
    setFormError(null);
    if (!name.trim() || !phone.trim()) return;
    createMutation.mutate({
      full_name: name.trim(),
      email: email.trim() || undefined,
      phone: phone.trim(),
      role: role as "admin" | "manager" | "staff",
      password: password.trim() || undefined,
      notes: notes.trim() || undefined,
      is_active: isActive,
    });
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/40">
      <div className="bg-white rounded-t-2xl shadow-xl w-full max-w-lg p-6 max-h-[85vh] overflow-y-auto">
        <h3 className="text-lg font-bold text-text-primary mb-4">Add user</h3>
        <div className="space-y-3">
          <Input
            label="Full name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            required
          />
          <Input
            label="Email (optional)"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            helperText="Auto-generated from phone if left empty"
          />
          <Input
            label="Phone number"
            type="tel"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            required
          />
          <Input
            label="Notes (optional)"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
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
            label="Password (optional)"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            helperText="Leave empty to generate a readable password"
          />
          <div className="flex items-center gap-3 py-2">
            <span className="text-sm text-text-primary">Active</span>
            <button
              onClick={() => setIsActive(!isActive)}
              className={`relative w-11 h-6 rounded-full transition-colors ${
                isActive ? "bg-brand-primary" : "bg-gray-300"
              }`}
            >
              <div
                className={`absolute top-0.5 w-5 h-5 rounded-full bg-white shadow transition-transform ${
                  isActive ? "translate-x-5.5" : "translate-x-0.5"
                }`}
              />
            </button>
          </div>
          {formError && (
            <p className="text-sm text-red-600 bg-red-50 rounded-lg px-3 py-2">
              {formError}
            </p>
          )}
          <div className="flex gap-3 pt-2">
            <Button variant="outline" onClick={onClose} className="flex-1">
              Cancel
            </Button>
            <Button
              onClick={handleSubmit}
              disabled={
                createMutation.isPending ||
                !name.trim() ||
                !phone.trim()
              }
              className="flex-1"
            >
              {createMutation.isPending ? "Creating…" : "Create user"}
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
