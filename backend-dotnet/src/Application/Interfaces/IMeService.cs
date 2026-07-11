namespace PurchaseAssistant.Application.Interfaces;

public interface IMeService
{
    Task GetProfileAsync();
    Task UpdateProfileAsync();
    Task BootstrapWorkspaceAsync();
    Task ListBusinessesAsync();
    Task UpdateBrandingAsync();
    Task UploadLogoAsync();
}
