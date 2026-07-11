namespace PurchaseAssistant.Application.Common.Interfaces;

public interface IPermissionService
{
    IReadOnlyList<string> PermissionKeys { get; }
    IReadOnlyDictionary<string, IReadOnlyDictionary<string, bool>> RoleDefaults { get; }
    Dictionary<string, bool> EffectivePermissions(string role, Dictionary<string, bool>? overrides);
    bool ActorCanManageTarget(string actorRole, string targetRole);
}
