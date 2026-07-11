using PurchaseAssistant.Application.Common.Interfaces;

namespace PurchaseAssistant.Infrastructure.Services;

public class PermissionService : IPermissionService
{
    private static readonly List<string> _permissionKeys = new()
    {
        "stock_edit", "purchase_create", "purchase_edit", "barcode_print",
        "reports_access", "export_access", "user_manage", "delete_access", "analytics_access",
    };

    private static readonly Dictionary<string, IReadOnlyDictionary<string, bool>> _roleDefaults = new()
    {
        ["owner"] = _permissionKeys.ToDictionary(k => k, _ => true),
        ["admin"] = _permissionKeys.ToDictionary(k => k, _ => true),
        ["manager"] = new Dictionary<string, bool>
        {
            ["stock_edit"] = true,
            ["purchase_create"] = true,
            ["purchase_edit"] = true,
            ["reports_access"] = true,
            ["barcode_print"] = true,
            ["export_access"] = true,
            ["user_manage"] = false,
            ["delete_access"] = false,
            ["analytics_access"] = true,
        },
        ["staff"] = new Dictionary<string, bool>
        {
            ["stock_edit"] = true,
            ["purchase_create"] = true,
            ["purchase_edit"] = false,
            ["reports_access"] = false,
            ["barcode_print"] = true,
            ["export_access"] = false,
            ["user_manage"] = false,
            ["delete_access"] = false,
            ["analytics_access"] = false,
        },
    };

    public IReadOnlyList<string> PermissionKeys => _permissionKeys.AsReadOnly();
    public IReadOnlyDictionary<string, IReadOnlyDictionary<string, bool>> RoleDefaults => _roleDefaults;

    public Dictionary<string, bool> EffectivePermissions(string role, Dictionary<string, bool>? overrides)
    {
        var basePerms = _roleDefaults.GetValueOrDefault(role, _roleDefaults["staff"]);
        var result = new Dictionary<string, bool>(basePerms);
        if (overrides != null)
        {
            if (overrides.TryGetValue("delete_items", out var di) && !result.ContainsKey("delete_access"))
                result["delete_access"] = di;
            foreach (var key in _permissionKeys)
            {
                if (overrides.TryGetValue(key, out var val))
                    result[key] = val;
            }
        }
        return result;
    }

    public bool ActorCanManageTarget(string actorRole, string targetRole)
    {
        if (targetRole == "owner" && actorRole == "admin")
            return false;
        return true;
    }
}
