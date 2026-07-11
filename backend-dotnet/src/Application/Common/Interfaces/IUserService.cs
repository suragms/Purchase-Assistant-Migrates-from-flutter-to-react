using PurchaseAssistant.Domain.Entities.Core;

namespace PurchaseAssistant.Application.Common.Interfaces;

public interface IUserService
{
    Task<User> GetCurrentUser();
    Task<Membership> GetMembership(Guid businessId);
    Task<User> GetUserInBusiness(Guid businessId, Guid userId);
}
