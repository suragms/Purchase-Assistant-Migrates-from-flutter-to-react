namespace PurchaseAssistant.Application.DTOs.Dashboard;

public record DashboardOut(
    decimal TotalPurchase, decimal Paid, decimal Pending, decimal? Profit,
    List<DashboardTopItem> TopItems, List<DashboardTopCategory> TopCategories);

public record DashboardTopItem(Guid Id, string Name, decimal TotalAmount, decimal? Profit);
public record DashboardTopCategory(string Name, decimal TotalAmount, int ItemCount);
